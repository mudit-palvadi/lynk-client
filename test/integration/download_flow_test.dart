import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/services/download_service.dart';
import 'package:client/features/file_receive/domain/usecases/decrypt_file_use_case.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

/// The download path, end to end through the client's own layers.
///
/// Notifier -> repository -> remote data source -> Dio -> (fake) backend, plus
/// the real decryption use case turning the downloaded ciphertext back into the
/// original file.
void main() {
  const aesKey = 'fedcba9876543210fedcba9876543210';

  // Shared preferences need an initialised binding, and the decrypt use case
  // runs in a real isolate, so these cases run on the real event loop rather
  // than inside a fake clock.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
    sandbox = await Directory.systemTemp.createTemp('lynk-download-test');
    PathProviderPlatform.instance = _FakePathProvider(sandbox.path);
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('transfer preview', () {
    test('reads the transfer and its download urls over http', () async {
      final backend = FakeBackend();
      final container = await _container(backend);

      final seeded = await _seedTransfer(container, backend, 'note.bin');
      final notifier = container.read(downloadProvider.notifier);

      await notifier.loadTransferPreview(
        seeded.id,
        accessToken: seeded.accessToken ?? '',
      );

      // `loadTransferPreview` folds the metadata result with an async
      // callback, so it returns before the download urls have been fetched.
      // Wait for the state to settle rather than racing it.
      await _waitUntil(
        () => container.read(downloadProvider).downloadFiles.isNotEmpty,
        description: 'the download urls to arrive',
      );

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.preview, reason: state.errorMessage);
      expect(state.transfer!.id, seeded.id);
      expect(state.downloadFiles, hasLength(1));
      expect(state.downloadFiles.first.name, 'note.bin');
      expect(state.downloadFiles.first.downloadUrl, isNotNull);
      expect(
        state.downloadFiles.first.downloadUrl,
        startsWith('https://r2.test/'),
      );
    });

    test('a second link stops the download already running', () async {
      final backend = FakeBackend();
      final holding = _HoldingDownload();
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(dio: backend.createDio()),
          ),
          downloadServiceProvider.overrideWithValue(holding),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final firstTransfer = await _seedTransfer(
        container,
        backend,
        'first.bin',
        contents: [1, 2, 3, 4],
      );
      final secondTransfer = await _seedTransfer(
        container,
        backend,
        'second.bin',
        contents: [5, 6, 7, 8],
      );
      final notifier = container.read(downloadProvider.notifier);
      await notifier.loadTransferPreview(
        firstTransfer.id,
        accessToken: firstTransfer.accessToken ?? '',
      );
      await _waitUntil(
        () => container.read(downloadProvider).downloadFiles.isNotEmpty,
        description: 'the first download urls to arrive',
      );

      final running = notifier.startDownload(aesKey: aesKey);
      await holding.started.future;
      await notifier.loadTransferPreview(
        secondTransfer.id,
        accessToken: secondTransfer.accessToken ?? '',
      );
      await running;
      await _waitUntil(
        () =>
            container.read(downloadProvider).transfer?.id ==
                secondTransfer.id &&
            container.read(downloadProvider).downloadFiles.isNotEmpty,
        description: 'the second preview to replace the first download',
      );

      expect(holding.cancelled, isTrue);
      expect(
        container.read(downloadProvider).phase,
        isNot(DownloadPhase.failed),
      );
      expect(
        container.read(downloadProvider).errorMessage,
        isNot(contains('Failed downloading')),
      );
    });

    test('a missing transfer surfaces the backend error', () async {
      final backend = FakeBackend();
      final container = await _container(backend);

      final notifier = container.read(downloadProvider.notifier);
      await notifier.loadTransferPreview('does-not-exist');

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.failed);
      expect(state.errorMessage, isNotNull);
    });
  });

  group('encrypt and decrypt round trip', () {
    test('recovers the original bytes', () {
      final plaintext = Uint8List.fromList(
        List<int>.generate(10 * 1024, (i) => (i * 31) % 256),
      );

      final encrypted = EncryptFileUseCase().executeBytes(
        inputBytes: plaintext,
        aesKey32Bytes: aesKey,
      );
      expect(encrypted, isNot(equals(plaintext)));
      // 16 byte IV prefix, then AES-CBC with PKCS7 padding.
      expect(encrypted.length % 16, 0);
      expect(encrypted.length, greaterThan(plaintext.length));

      final decrypted = DecryptFileUseCase().executeBytes(
        encryptedBytes: encrypted,
        aesKey32Bytes: aesKey,
      );
      expect(decrypted, plaintext);
    });

    test('the wrong key does not recover the bytes', () {
      final plaintext = Uint8List.fromList(List<int>.filled(64, 7));

      final encrypted = EncryptFileUseCase().executeBytes(
        inputBytes: plaintext,
        aesKey32Bytes: aesKey,
      );

      expect(
        () => DecryptFileUseCase().executeBytes(
          encryptedBytes: encrypted,
          aesKey32Bytes: '00000000000000000000000000000000',
        ),
        throwsA(anything),
      );
    });

    test('a truncated payload is rejected', () {
      expect(
        () => DecryptFileUseCase().executeBytes(
          encryptedBytes: Uint8List(8),
          aesKey32Bytes: aesKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('download', () {
    test('writes the decrypted file where the app expects it', () async {
      final backend = FakeBackend();
      final container = await _container(backend);

      final plaintext = Uint8List.fromList(
        List<int>.generate(2048, (i) => (i * 17) % 256),
      );
      final encrypted = EncryptFileUseCase().executeBytes(
        inputBytes: plaintext,
        aesKey32Bytes: aesKey,
      );

      final seeded = await _seedTransfer(
        container,
        backend,
        'note.bin',
        contents: encrypted,
      );

      final notifier = container.read(downloadProvider.notifier);
      await notifier.loadTransferPreview(
        seeded.id,
        accessToken: seeded.accessToken ?? '',
      );
      await _waitUntil(
        () => container.read(downloadProvider).downloadFiles.isNotEmpty,
        description: 'the download urls to arrive',
      );

      // The decryption runs in an isolate, which needs the real event loop.
      await notifier.startDownload(aesKey: aesKey);
      await _waitUntil(
        () =>
            container.read(downloadProvider).phase == DownloadPhase.completed ||
            container.read(downloadProvider).phase == DownloadPhase.failed,
        description: 'the download to finish',
      );

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed, reason: state.errorMessage);
      expect(state.downloadedPaths, hasLength(1));

      final written = File(state.downloadedPaths.single);
      expect(written.existsSync(), isTrue);
      expect(written.readAsBytesSync(), plaintext);
    });

    test('a download without a key fails instead of writing garbage', () async {
      final backend = FakeBackend();
      final container = await _container(backend);

      final seeded = await _seedTransfer(container, backend, 'note.bin');
      final notifier = container.read(downloadProvider.notifier);
      await notifier.loadTransferPreview(
        seeded.id,
        accessToken: seeded.accessToken ?? '',
      );
      await _waitUntil(
        () => container.read(downloadProvider).downloadFiles.isNotEmpty,
        description: 'the download urls to arrive',
      );

      await notifier.startDownload();

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.failed);
      expect(state.errorMessage, contains('key'));
    });

    test('a hostile file name cannot escape the download directory', () async {
      // The name is chosen by the sender and echoed back by the server, so a
      // malicious sender could try to write outside the download folder.
      final backend = FakeBackend();
      final container = await _container(backend);

      final plaintext = Uint8List.fromList(
        List<int>.generate(256, (i) => (i * 7) % 256),
      );
      final encrypted = EncryptFileUseCase().executeBytes(
        inputBytes: plaintext,
        aesKey32Bytes: aesKey,
      );

      final seeded = await _seedTransfer(
        container,
        backend,
        '../escaped.txt',
        contents: encrypted,
      );

      final notifier = container.read(downloadProvider.notifier);
      await notifier.loadTransferPreview(
        seeded.id,
        accessToken: seeded.accessToken ?? '',
      );
      await _waitUntil(
        () => container.read(downloadProvider).downloadFiles.isNotEmpty,
        description: 'the download urls to arrive',
      );

      await notifier.startDownload(aesKey: aesKey);
      await _waitUntil(
        () =>
            container.read(downloadProvider).phase == DownloadPhase.completed ||
            container.read(downloadProvider).phase == DownloadPhase.failed,
        description: 'the download to finish',
      );

      final state = container.read(downloadProvider);
      expect(state.phase, DownloadPhase.completed, reason: state.errorMessage);
      expect(state.downloadedPaths, hasLength(1));

      // The file landed inside the download directory...
      final written = state.downloadedPaths.single;
      expect(written, startsWith(sandbox.path));
      expect(File(written).existsSync(), isTrue);
      expect(File(written).readAsBytesSync(), plaintext);

      // ...and not one level up, where the traversal would have landed.
      expect(
        File('${sandbox.parent.path}/escaped.txt').existsSync(),
        isFalse,
        reason: 'the file was written outside the download directory',
      );
    });
    test(
      'a sender that is still uploading is waited for, not failed',
      () async {
        // A sender shows the QR code before it uploads anything, so a receiver
        // can arrive while the files are still on their way. The server answers
        // 409 in that window, which is a temporary state and not an error.
        final backend = FakeBackend();
        final container = await _container(backend);

        final plaintext = Uint8List.fromList(
          List<int>.generate(256, (i) => (i * 7) % 256),
        );
        final encrypted = EncryptFileUseCase().executeBytes(
          inputBytes: plaintext,
          aesKey32Bytes: aesKey,
        );

        final seeded = await _seedTransfer(
          container,
          backend,
          'note.bin',
          contents: encrypted,
          completeUpload: false,
        );

        final notifier = container.read(downloadProvider.notifier);
        notifier.readyPollInterval = const Duration(milliseconds: 50);
        notifier.readyTimeout = const Duration(seconds: 10);

        await notifier.loadTransferPreview(
          seeded.id,
          accessToken: seeded.accessToken ?? '',
        );
        await _waitUntil(
          () => container.read(downloadProvider).transfer != null,
          description: 'the transfer details to arrive',
        );

        // The preview must not ask for the files yet: the server would answer
        // 409, and that says nothing useful.
        var state = container.read(downloadProvider);
        expect(state.phase, DownloadPhase.preview);
        expect(state.downloadFiles, isEmpty);

        // The sender finishes uploading a moment later, the way a sender does
        // once its direct-connection window has passed.
        final repository = container.read(transferRepositoryProvider);
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 200)).then((
            _,
          ) async {
            await repository.completeFileUpload(
              transferId: seeded.id,
              fileId: seeded.files.first.id,
              senderSecret: seeded.senderSecret,
            );
          }),
        );

        await notifier.startDownload(aesKey: aesKey);
        await _waitUntil(
          () =>
              container.read(downloadProvider).phase ==
                  DownloadPhase.completed ||
              container.read(downloadProvider).phase == DownloadPhase.failed,
          description: 'the download to finish',
        );

        state = container.read(downloadProvider);
        expect(
          state.phase,
          DownloadPhase.completed,
          reason: state.errorMessage,
        );
        expect(state.downloadedPaths, hasLength(1));
        expect(File(state.downloadedPaths.single).readAsBytesSync(), plaintext);
      },
    );

    test(
      'a sender that never uploads ends with a message that says so',
      () async {
        final backend = FakeBackend();
        final container = await _container(backend);

        final seeded = await _seedTransfer(
          container,
          backend,
          'note.bin',
          completeUpload: false,
        );

        final notifier = container.read(downloadProvider.notifier);
        notifier.readyPollInterval = const Duration(milliseconds: 50);
        notifier.readyTimeout = const Duration(milliseconds: 300);

        await notifier.loadTransferPreview(
          seeded.id,
          accessToken: seeded.accessToken ?? '',
        );
        await notifier.startDownload(aesKey: aesKey);

        final state = container.read(downloadProvider);
        expect(state.phase, DownloadPhase.failed);
        expect(state.errorMessage, contains('still uploading'));
        // The raw exception text must never reach the user.
        expect(state.errorMessage, isNot(contains('DioException')));
      },
    );
  });
}

/// Waits for [condition] to become true, polling on the real clock.
///
/// The notifier folds results with async callbacks, so a returned future does
/// not mean the state has been written yet.
Future<void> _waitUntil(
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $description.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Creates a transfer through the client's own repository so the backend ends
/// up holding a file the download flow can fetch.
///
/// The sender uploads the file and then marks it complete, which is what
/// moves the transfer to "ready". Pass `completeUpload: false` to leave the
/// transfer in the "uploading" state a sender is in while it waits for a
/// receiver.
Future<Transfer> _seedTransfer(
  ProviderContainer container,
  FakeBackend backend,
  String fileName, {
  List<int>? contents,
  bool completeUpload = true,
}) async {
  final repository = container.read(transferRepositoryProvider);
  final result = await repository.createTransfer([
    FileItem(
      id: '',
      name: fileName,
      size: 1024,
      contentType: 'application/octet-stream',
      status: FileStatus.pending,
    ),
  ]);
  expect(result.isSuccess, isTrue, reason: 'create transfer failed');

  final uploadUrl = result.value!.files.first.uploadUrl!;
  if (contents != null) {
    // The fake backend keeps the uploaded bytes under the presigned url, so
    // the download service can serve them back.
    backend.uploadedObjects[uploadUrl] = contents;
  }

  if (completeUpload) {
    final completed = await repository.completeFileUpload(
      transferId: result.value!.id,
      fileId: result.value!.files.first.id,
      senderSecret: result.value!.senderSecret,
    );
    expect(completed.isSuccess, isTrue, reason: 'complete upload failed');
  }

  return result.value!;
}

Future<ProviderContainer> _container(FakeBackend backend) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(ApiClient(dio: backend.createDio())),
      downloadServiceProvider.overrideWithValue(
        _FakeDownloadService(backend.uploadedObjects),
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Points path_provider at the test sandbox instead of the platform channel.
///
/// The platform interface exposes `...Path` methods; the `...Directory`
/// helpers on the base class are the ones path_provider calls.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// Serves the bytes the fake backend holds for a presigned url.
class _FakeDownloadService extends DownloadService {
  _FakeDownloadService(this.objects);

  final Map<String, List<int>> objects;

  @override
  Future<void> downloadFileFromR2({
    required String downloadUrl,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final bytes = objects[downloadUrl];
    if (bytes == null) {
      throw Exception('R2 download error (404): unknown url $downloadUrl');
    }
    File(savePath).writeAsBytesSync(bytes);
    onProgress(bytes.length, bytes.length);
  }
}

/// Stays inside the download until the caller cancels that token.
class _HoldingDownload extends DownloadService {
  final started = Completer<void>();
  var cancelled = false;

  @override
  Future<void> downloadFileFromR2({
    required String downloadUrl,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!started.isCompleted) started.complete();
    final stopped = Completer<void>();
    cancelToken?.whenCancel.then((_) {
      cancelled = true;
      if (!stopped.isCompleted) stopped.complete();
    });
    await stopped.future;
    throw DioException(
      requestOptions: RequestOptions(path: downloadUrl),
      type: DioExceptionType.cancel,
    );
  }
}
