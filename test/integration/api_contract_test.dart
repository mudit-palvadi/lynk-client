import 'dart:convert';
import 'dart:io';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/providers/receiver_providers.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/features/file_receive/data/models/receiver_session_model.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';
import 'package:client/features/file_transfer/data/models/file_item_model.dart';
import 'package:client/features/file_transfer/data/models/transfer_model.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_http_adapter.dart';

/// Keeps the client honest about the API it speaks.
///
/// The contract lives in the backend repo
/// (`backend/tests/fixtures/lynk_api_contract.json`) and is asserted there
/// against the real FastAPI routes. This test asserts the same file against
/// the Flutter client.
///
/// The two repos are versioned separately, so this is what turns a silent
/// client break into a red test: rename a field on the backend and this fails
/// before the client ships.
void main() {
  // Shared preferences need an initialised binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The backend is a separate checkout, so the fixture may not be there.
  final fixtureFile = File('../backend/tests/fixtures/lynk_api_contract.json');
  final skipReason = fixtureFile.existsSync()
      ? null
      : 'backend checkout not found next to client/ (expected ../backend)';

  late final Map<String, dynamic> contract;

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
    if (fixtureFile.existsSync()) {
      contract =
          jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    }
  });

  setUp(() {
    // Installs the in-memory preferences store; without it the shared
    // preferences plugin would look for a platform implementation.
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
  });

  group('the client calls the endpoints the contract declares', () {
    for (final endpoint in _endpointsOf(fixtureFile)) {
      if (!(endpoint['client_uses'] as bool? ?? false)) continue;

      test(
        '${endpoint['method']} ${endpoint['path']}',
        () async {
          final container = await _container(endpoint);
          addTearDown(container.dispose);

          await _callClient(container, endpoint);

          final request = container.read(_adapterProvider)!.requests.single;
          expect(request.method, endpoint['method']);
          expect(
            request.path,
            _resolve(endpoint['client_path'] as String),
            reason: 'the client must call the path the contract declares',
          );
        },
        skip: skipReason,
      );
    }
  });

  group('the client parses the responses the contract declares', () {
    for (final endpoint in _endpointsOf(fixtureFile)) {
      final model = endpoint['client_model'] as String?;
      final sample = endpoint['response_sample'] as Map<String, dynamic>?;
      if (model == null || sample == null) continue;

      test(
        '${endpoint['method']} ${endpoint['path']} ($model)',
        () {
          switch (model) {
            case 'TransferModel':
              final parsed = TransferModel.fromJson(sample);
              expect(parsed.id, sample['transfer_id']);
              expect(parsed.totalFiles, sample['total_files']);
              expect(parsed.totalSize, sample['total_size']);
              expect(parsed.expiresMultiplier, sample['expires_in']);
              final sampleFile =
                  (sample['files'] as List).first as Map<String, dynamic>;
              expect(parsed.files.first.id, sampleFile['file_id']);
              expect(parsed.files.first.name, sampleFile['file_name']);
              expect(parsed.files.first.uploadUrl, sampleFile['upload_url']);
              break;
            case 'FileItemModel':
              final sampleFile =
                  (sample['files'] as List).first as Map<String, dynamic>;
              final parsed = FileItemModel.fromJson(sampleFile);
              expect(parsed.id, sampleFile['file_id']);
              expect(parsed.name, sampleFile['file_name']);
              expect(parsed.downloadUrl, sampleFile['download_url']);
              break;
            case 'ReceiverSessionModel':
              final parsed = ReceiverSessionModel.fromJson(sample);
              expect(parsed.id, sample['session_id']);
              expect(parsed.status.name, sample['status']);
              if (sample['transfer_id'] != null) {
                expect(parsed.transferId, sample['transfer_id']);
              }
              if (sample['wrapped_key'] != null) {
                expect(parsed.wrappedKey, sample['wrapped_key']);
              }
              break;
            default:
              fail('unknown client model $model in the contract');
          }
        },
        skip: skipReason,
      );
    }
  });

  group('the client understands every status the contract declares', () {
    test('transfer statuses', () {
      for (final status in _enums(contract, 'transfer_status')) {
        expect(
          TransferStatus.values.map((value) => value.name),
          contains(status),
          reason: 'the client cannot represent transfer status $status',
        );
      }
    }, skip: skipReason);

    test('file statuses', () {
      for (final status in _enums(contract, 'file_status')) {
        expect(
          FileStatus.values.map((value) => value.name),
          contains(status),
          reason: 'the client cannot represent file status $status',
        );
      }
    }, skip: skipReason);

    test('receiver session statuses', () {
      for (final status in _enums(contract, 'receiver_session_status')) {
        expect(
          ReceiverSessionStatus.values.map((value) => value.name),
          contains(status),
          reason: 'the client cannot represent session status $status',
        );
      }
    }, skip: skipReason);
  });
}

/// The fixture endpoints, or an empty list when the backend is not checked
/// out. Used to generate the test names at collection time.
List<Map<String, dynamic>> _endpointsOf(File fixtureFile) {
  if (!fixtureFile.existsSync()) return const [];
  final decoded = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  return (decoded['endpoints'] as List).cast<Map<String, dynamic>>();
}

List<String> _enums(Map<String, dynamic> contract, String name) {
  final enums = contract['enums'] as Map<String, dynamic>?;
  return ((enums?[name] as List?) ?? const []).cast<String>();
}

/// Fills the placeholders in a contract path with the ids the test uses.
String _resolve(String template) => template
    .replaceAll('{transfer_id}', _transferId)
    .replaceAll('{file_id}', _fileId)
    .replaceAll('{session_id}', _sessionId);

const String _transferId = 'contract-transfer';
const String _fileId = 'contract-file';
const String _sessionId = 'contract-session';

/// Drives the client call that the contract endpoint describes.
Future<void> _callClient(
  ProviderContainer container,
  Map<String, dynamic> endpoint,
) async {
  final path = endpoint['path'] as String;
  final method = endpoint['method'] as String;
  final transfers = container.read(transferRemoteDataSourceProvider);
  final receivers = container.read(receiverRemoteDataSourceProvider);

  if (path == '/transfers' && method == 'POST') {
    await transfers.createTransfer([
      FileItemModel(
        id: _fileId,
        name: 'contract.bin',
        size: 1024,
        contentType: 'application/octet-stream',
        status: FileStatus.pending,
      ),
    ]);
    return;
  }
  if (path.endsWith('/complete')) {
    await transfers.completeFileUpload(transferId: _transferId, fileId: _fileId);
    return;
  }
  if (path == '/transfers/{transfer_id}' && method == 'GET') {
    await transfers.getTransferMetadata(_transferId);
    return;
  }
  if (path == '/transfers/{transfer_id}' && method == 'DELETE') {
    await transfers.cancelTransfer(_transferId);
    return;
  }
  if (path.endsWith('/downloads')) {
    await transfers.getDownloadUrls(transferId: _transferId);
    return;
  }
  if (path == '/receiver-sessions' && method == 'POST') {
    await receivers.createReceiverSession();
    return;
  }
  if (path.endsWith('/attach-transfer')) {
    await receivers.attachTransfer(
      sessionId: _sessionId,
      transferId: _transferId,
      wrappedKey: 'contract-wrapped-key',
    );
    return;
  }
  if (path == '/receiver-sessions/{session_id}' && method == 'GET') {
    await receivers.getReceiverSession(_sessionId);
    return;
  }
  if (path == '/receiver-sessions/{session_id}' && method == 'DELETE') {
    await receivers.cancelReceiverSession(_sessionId);
    return;
  }

  fail('the client has no call for $method $path');
}

/// The adapter the container was built with, so a test can read the request
/// the client actually made.
final _adapterProvider = Provider<FakeHttpAdapter?>((ref) => null);

Future<ProviderContainer> _container(Map<String, dynamic> endpoint) async {
  final prefs = await SharedPreferences.getInstance();
  final adapter = FakeHttpAdapter((request) {
    final sample = endpoint['response_sample'];
    if (sample == null) {
      return ResponseBody.fromString('', 204);
    }
    return jsonResponse(200, sample);
  });

  final dio = Dio();
  dio.httpClientAdapter = adapter;

  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      sharedPreferencesProvider.overrideWithValue(prefs),
      _adapterProvider.overrideWithValue(adapter),
    ],
  );
  return container;
}
