import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'fake_http_adapter.dart';

/// An in-memory stand-in for the Lynk backend.
///
/// It answers with exactly the field names the real FastAPI service returns
/// (see `backend/tests/fixtures/lynk_api_contract.json`), so a test that passes
/// against this fake is a statement about the wire format rather than about a
/// convenient mock.
///
/// It is still a fake: it cannot catch a 500, an R2 content-type rejection, a
/// Redis TTL bug, or the two sides agreeing that `total_size` means ciphertext
/// while the backend means plaintext. It does catch the failures that break
/// clients quietly - renamed fields, changed status values, wrong request
/// bodies, wrong call order.
class FakeBackend {
  FakeBackend();

  final Map<String, _FakeTransfer> _transfers = <String, _FakeTransfer>{};
  final Map<String, _FakeSession> _sessions = <String, _FakeSession>{};

  /// Bytes "uploaded" to the fake R2, keyed by the presigned url.
  final Map<String, List<int>> uploadedObjects = <String, List<int>>{};

  int _counter = 0;

  /// The adapter the last created Dio is wired to, for assertions.
  FakeHttpAdapter? adapter;

  String _nextId(String prefix) => '$prefix-${++_counter}';

  /// A Dio wired to this backend. Pass it to `ApiClient(dio: ...)` so the real
  /// base url and interceptor are exercised too.
  Dio createDio() {
    final dio = Dio();
    adapter = FakeHttpAdapter(handle);
    dio.httpClientAdapter = adapter!;
    return dio;
  }

  FutureOr<ResponseBody> handle(RecordedRequest request) {
    final path = request.path;
    final method = request.method;

    if (method == 'POST' && path == 'transfers') {
      return jsonResponse(201, _createTransfer(request.body));
    }

    if (method == 'GET' && path.startsWith('transfers/')) {
      final transfer = _transfers[path.substring('transfers/'.length)];
      if (transfer == null) return _notFound();
      return jsonResponse(200, _transferMetadata(transfer));
    }

    if (method == 'POST' && path.endsWith('/downloads')) {
      final transferId = path
          .substring('transfers/'.length)
          .substring(0, path.length - 'transfers/'.length - '/downloads'.length);
      final transfer = _transfers[transferId];
      if (transfer == null) return _notFound();
      return jsonResponse(200, _downloadUrls(transfer, request.body));
    }

    if (method == 'POST' && path.contains('/files/') && path.endsWith('/complete')) {
      final parts = path.split('/');
      final transfer = _transfers[parts[1]];
      if (transfer == null) return _notFound();
      final file = transfer.files.firstWhere(
        (candidate) => candidate.fileId == parts[3],
        orElse: () => throw StateError('unknown file ${parts[3]}'),
      );
      file.status = 'uploaded';
      if (transfer.files.every((candidate) => candidate.status == 'uploaded')) {
        transfer.status = 'ready';
      }
      return jsonResponse(200, {
        'file_id': file.fileId,
        'status': file.status,
        'transfer_status': transfer.status,
      });
    }

    if (method == 'DELETE' && path.startsWith('transfers/')) {
      _transfers.remove(path.substring('transfers/'.length));
      return ResponseBody.fromString('', 204);
    }

    if (method == 'POST' && path == 'receiver-sessions') {
      final session = _FakeSession(_nextId('session'));
      _sessions[session.sessionId] = session;
      return jsonResponse(201, {
        'session_id': session.sessionId,
        'status': session.status,
        'expires_in': 600,
      });
    }

    if (method == 'GET' && path.startsWith('receiver-sessions/')) {
      final session = _sessions[path.substring('receiver-sessions/'.length)];
      if (session == null) return _notFound();
      return jsonResponse(200, _sessionPayload(session));
    }

    if (method == 'POST' && path.endsWith('/attach-transfer')) {
      final sessionId = path
          .substring('receiver-sessions/'.length)
          .substring(0, path.length - 'receiver-sessions/'.length - '/attach-transfer'.length);
      final session = _sessions[sessionId];
      if (session == null) return _notFound();
      final body = (request.body as Map?)?.cast<String, dynamic>() ?? {};
      session.transferId = body['transfer_id'] as String?;
      session.wrappedKey = body['wrapped_key'] as String?;
      session.status = 'attached';
      return jsonResponse(200, <String, dynamic>{});
    }

    if (method == 'DELETE' && path.startsWith('receiver-sessions/')) {
      _sessions.remove(path.substring('receiver-sessions/'.length));
      return ResponseBody.fromString('', 204);
    }

    return ResponseBody.fromString(
      jsonEncode({'detail': 'no route for $method $path'}),
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, dynamic> _createTransfer(Object? body) {
    final payload = (body as Map?)?.cast<String, dynamic>() ?? {};
    final files = (payload['files'] as List?)?.cast<Map>() ?? <Map>[];

    final transfer = _FakeTransfer(_nextId('transfer'));
    for (final file in files) {
      final entry = _FakeFile(
        _nextId('file'),
        file['file_name'] as String? ?? '',
        (file['file_size'] as num?)?.toInt() ?? 0,
        file['content_type'] as String? ?? '',
      );
      transfer.files.add(entry);
      transfer.totalSize += entry.fileSize;
    }
    _transfers[transfer.transferId] = transfer;

    return {
      'transfer_id': transfer.transferId,
      'status': transfer.status,
      'total_files': transfer.files.length,
      'total_size': transfer.totalSize,
      'expires_in': 3600,
      'files': [
        for (final file in transfer.files)
          {
            'file_id': file.fileId,
            'file_name': file.fileName,
            'file_size': file.fileSize,
            'upload_url': _objectUrl(transfer.transferId, file.fileId),
          },
      ],
    };
  }

  Map<String, dynamic> _transferMetadata(_FakeTransfer transfer) => {
    'transfer_id': transfer.transferId,
    'status': transfer.status,
    'total_files': transfer.files.length,
    'total_size': transfer.totalSize,
    'expires_in': 3600,
    'files': [
      for (final file in transfer.files)
        {
          'file_id': file.fileId,
          'file_name': file.fileName,
          'file_size': file.fileSize,
          'content_type': file.contentType,
        },
    ],
  };

  Map<String, dynamic> _downloadUrls(_FakeTransfer transfer, Object? body) {
    final payload = (body as Map?)?.cast<String, dynamic>() ?? {};
    final requested = (payload['file_ids'] as List?)?.cast<String>();
    final files = transfer.files
        .where(
          (file) => requested == null || requested.contains(file.fileId),
        )
        .toList();

    return {
      'files': [
        for (final file in files)
          {
            'file_id': file.fileId,
            'file_name': file.fileName,
            'download_url': _objectUrl(transfer.transferId, file.fileId),
            'expires_in': 900,
          },
      ],
    };
  }

  Map<String, dynamic> _sessionPayload(_FakeSession session) => {
    'session_id': session.sessionId,
    'status': session.status,
    if (session.transferId != null) 'transfer_id': session.transferId,
    if (session.wrappedKey != null) 'wrapped_key': session.wrappedKey,
    'expires_in': 600,
  };

  String _objectUrl(String transferId, String fileId) =>
      'https://r2.test/objects/$transferId/$fileId';

  ResponseBody _notFound() => ResponseBody.fromString(
    jsonEncode({'detail': 'not found'}),
    404,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeTransfer {
  _FakeTransfer(this.transferId);

  final String transferId;
  final List<_FakeFile> files = <_FakeFile>[];
  String status = 'uploading';
  int totalSize = 0;
}

class _FakeFile {
  _FakeFile(this.fileId, this.fileName, this.fileSize, this.contentType);

  final String fileId;
  final String fileName;
  final int fileSize;
  final String contentType;
  String status = 'pending';
}

class _FakeSession {
  _FakeSession(this.sessionId);

  final String sessionId;
  String status = 'waiting';
  String? transferId;
  String? wrappedKey;
}
