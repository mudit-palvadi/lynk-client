import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/services/upload_service.dart';
import 'package:client/features/file_receive/domain/usecases/decrypt_file_use_case.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';
import 'support/fake_http_adapter.dart';

/// The cloud upload path, end to end through the client's own layers.
///
/// Notifier -> repository -> remote data source -> Dio -> (fake) backend, with
/// the real [ApiClient] in front of it, so the request building, the request
/// body shape and the response parsing are all the production ones.
///
/// The R2 leg is the one part that cannot be reached without changing
/// production code (UploadService builds its own Dio), so it is faked at the
/// service boundary. Everything up to and including the bytes handed to R2 is
/// the real thing.
void main() {
  setUpAll(() {
    // ApiClient reads the base url from dotenv, which throws when dotenv was
    // never initialised.
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
  });

  group('cloud upload', () {
    test('creates the transfer, uploads the ciphertext and completes the file',
        () async {
      final backend = FakeBackend();
      final uploads = _FakeUploadService();
      final container = await _container(backend: backend, uploads: uploads);

      final plaintext = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));
      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([
        PlatformFile(name: 'note.bin', size: plaintext.length, bytes: plaintext),
      ]);

      await notifier.startUpload();

      final state = container.read(uploadProvider);
      expect(state.phase, UploadPhase.completed, reason: state.errorMessage);

      // 1. The transfer is created first.
      final adapter = backend.adapter!;
      expect(adapter.requests, hasLength(2));

      final create = adapter.requests[0];
      expect(create.method, 'POST');
      expect(create.path, 'transfers');
      expect(create.uri.toString(),
          'https://api.test.local/api/v1/transfers');

      final body = (create.body as Map).cast<String, dynamic>();
      final files = (body['files'] as List).cast<Map>();
      expect(files, hasLength(1));
      expect(files.single['file_name'], 'note.bin');
      expect(files.single['content_type'], 'application/octet-stream');
      // The backend must be told the size of the ciphertext, not the
      // plaintext: the file is encrypted before it is uploaded.
      expect(files.single['file_size'],
          ((plaintext.length ~/ 16) + 1) * 16 + 16);
      // The client never sends an upload url, the backend issues one.
      expect(files.single.containsKey('upload_url'), isFalse);

      // 2. The encrypted bytes reach the upload service.
      expect(uploads.objects, hasLength(1));
      final uploaded = uploads.objects.single;
      expect(uploaded.name, 'note.bin');
      expect(uploaded.uploadUrl, startsWith('https://r2.test/objects/'));
      expect(uploaded.bytes, isNotNull);

      // 3. The transfer is completed, with the ids the backend issued.
      final complete = adapter.requests[1];
      expect(complete.method, 'POST');
      expect(
        complete.path,
        'transfers/${state.transfer!.id}/files/${state.transfer!.files.first.id}/complete',
      );
      expect(state.transfer!.senderSecret, isNotEmpty);
      expect(state.transfer!.accessToken, isNotEmpty);
      expect(
        complete.headers.entries
            .firstWhere(
              (entry) => entry.key.toLowerCase() == 'x-lynk-sender-secret',
            )
            .value,
        state.transfer!.senderSecret,
      );
      expect(complete.rawBody ?? '', isNot(contains(state.aesKey)));
    });

    test('the uploaded bytes decrypt back to the original file', () async {
      final backend = FakeBackend();
      final uploads = _FakeUploadService();
      final container = await _container(backend: backend, uploads: uploads);

      final plaintext = Uint8List.fromList(
        List<int>.generate(4096, (i) => (i * 7) % 256),
      );
      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([
        PlatformFile(name: 'payload.bin', size: plaintext.length, bytes: plaintext),
      ]);

      await notifier.startUpload();

      final state = container.read(uploadProvider);
      expect(state.phase, UploadPhase.completed, reason: state.errorMessage);

      final aesKey = state.aesKey!;
      final uploaded = uploads.objects.single.bytes;

      // The bytes on the wire are the ciphertext of the file, and they are
      // recoverable with the key the app kept in memory.
      expect(uploaded, isNot(equals(plaintext)));
      final decrypted = DecryptFileUseCase().executeBytes(
        encryptedBytes: uploaded,
        aesKey32Bytes: aesKey,
      );
      expect(decrypted, plaintext);
    });

    test('the AES key never leaves the device', () async {
      final backend = FakeBackend();
      final uploads = _FakeUploadService();
      final container = await _container(backend: backend, uploads: uploads);

      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([
        PlatformFile(name: 'secret.bin', size: 64, bytes: Uint8List(64)),
      ]);

      await notifier.startUpload();

      final aesKey = container.read(uploadProvider).aesKey!;
      for (final request in backend.adapter!.requests) {
        expect(request.rawBody ?? '', isNot(contains(aesKey)));
        expect(request.uri.toString(), isNot(contains(aesKey)));
        for (final value in request.queryParameters.values) {
          expect(value.toString(), isNot(contains(aesKey)));
        }
      }
    });

    test('a rejected transfer surfaces as a failure, not a silent success',
        () async {
      final uploads = _FakeUploadService();
      final failing = Dio();
      failing.httpClientAdapter = FakeHttpAdapter(
        (request) => jsonResponse(500, {'detail': 'boom'}),
      );

      final container = await _container(
        backend: FakeBackend(),
        uploads: uploads,
        dio: failing,
      );

      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([
        PlatformFile(name: 'doomed.bin', size: 10, bytes: Uint8List(10)),
      ]);

      await notifier.startUpload();

      final state = container.read(uploadProvider);
      expect(state.phase, UploadPhase.failed);
      expect(state.errorMessage, isNotNull);
      // Nothing was uploaded when the transfer could not be created.
      expect(uploads.objects, isEmpty);
    });
  });
}

Future<ProviderContainer> _container({
  required FakeBackend backend,
  required _FakeUploadService uploads,
  Dio? dio,
}) async {
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(dio: dio ?? backend.createDio()),
      ),
      uploadServiceProvider.overrideWithValue(uploads),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Captures what the app hands to R2 instead of uploading it.
class _FakeUploadService extends UploadService {
  final List<_UploadedObject> objects = <_UploadedObject>[];

  @override
  Future<void> uploadFileToR2({
    required String name,
    required int size,
    required String contentType,
    required String uploadUrl,
    File? file,
    Uint8List? bytes,
    required void Function(int sent, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    objects.add(_UploadedObject(
      name: name,
      size: size,
      contentType: contentType,
      uploadUrl: uploadUrl,
      bytes: bytes ?? Uint8List.fromList(await file!.readAsBytes()),
    ));
    onProgress(size, size);
  }
}

class _UploadedObject {
  _UploadedObject({
    required this.name,
    required this.size,
    required this.contentType,
    required this.uploadUrl,
    required this.bytes,
  });

  final String name;
  final int size;
  final String contentType;
  final String uploadUrl;
  final Uint8List bytes;
}
