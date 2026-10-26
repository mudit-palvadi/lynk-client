import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/services/upload_service.dart';
import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
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

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
  });

  group('upload attempt isolation', () {
    test(
      'a repeated start while create is pending creates only one transfer',
      () async {
        final run = await _Run.create();
        final first = run.notifier.startUpload();
        await run.createEntered.future;
        await run.notifier.startUpload();
        run.releaseCreate.complete();
        await first;

        expect(run.createCalls, 1);
        expect(run.uploads.payloads, hasLength(1));
        expect(run.container.read(uploadProvider).phase, UploadPhase.completed);
      },
    );

    test('cancelling during create cannot later upload or complete', () async {
      final run = await _Run.create();
      final first = run.notifier.startUpload();
      await run.createEntered.future;
      run.notifier.cancelUpload();
      run.releaseCreate.complete();
      await first;

      expect(run.uploads.payloads, isEmpty);
      expect(run.container.read(uploadProvider).phase, UploadPhase.cancelled);
    });

    test(
      'a cancelled create cannot overwrite a newer transfer or its key',
      () async {
        final run = await _Run.create();
        final first = run.notifier.startUpload();
        await run.createEntered.future;
        run.notifier.cancelUpload();
        run.notifier.reset();
        final plain = Uint8List.fromList([8, 7, 6]);
        run.notifier.setFilesForTesting([
          PlatformFile(name: 'new.bin', size: plain.length, bytes: plain),
        ]);
        await run.notifier.startUpload();
        final newer = run.container.read(uploadProvider);
        run.releaseCreate.complete();
        await first;

        final finalState = run.container.read(uploadProvider);
        expect(finalState.transfer!.id, newer.transfer!.id);
        expect(finalState.aesKey, newer.aesKey);
        expect(finalState.selectedFiles.single.name, 'new.bin');
        expect(run.uploads.payloads, hasLength(1));
        expect(
          DecryptFileUseCase().executeBytes(
            encryptedBytes: run.uploads.payloads.single,
            aesKey32Bytes: finalState.aesKey!,
          ),
          plain,
        );
      },
    );

    test(
      'late R2 progress and completion cannot change a replacement send',
      () async {
        final run = await _Run.create();
        run.uploads.holdFirst = true;
        final first = run.notifier.startUpload();
        await run.createEntered.future;
        run.releaseCreate.complete();
        await run.uploads.entered.future;
        run.notifier.cancelUpload();
        run.notifier.reset();
        run.notifier.setFilesForTesting([
          PlatformFile(
            name: 'replacement.bin',
            size: 1,
            bytes: Uint8List.fromList([9]),
          ),
        ]);
        await run.notifier.startUpload();
        final newer = run.container.read(uploadProvider);
        run.uploads.lateProgress!(1, 100);
        run.uploads.release.complete();
        await first;
        expect(run.container.read(uploadProvider), newer);
        expect(run.completeCalls, 1);
      },
    );

    test(
      'old direct cleanup cannot delete a newer send of the same source',
      () async {
        final old = _HeldSender();
        final newer = _HeldSender();
        var factories = 0;
        final run = await _Run.create(
          factory:
              ({
                required signalingUrl,
                required sessionId,
                accessToken,
                aesKey,
                required onFallbackToCloud,
              }) async => factories++ == 0 ? old : newer,
        );
        final directory = await Directory.systemTemp.createTemp(
          'lynk-race-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final source = await File(
          '${directory.path}/same.bin',
        ).writeAsBytes([1, 2, 3]);
        void select() => run.notifier.setFilesForTesting([
          PlatformFile(name: 'same.bin', size: 3, path: source.path),
        ]);
        select();
        final first = run.notifier.runP2PSession(
          sessionId: 'old',
          aesKey: 'a' * 32,
        );
        await old.entered.future;
        run.notifier.cancelUpload();
        run.notifier.reset();
        select();
        final second = run.notifier.runP2PSession(
          sessionId: 'new',
          aesKey: 'b' * 32,
        );
        await newer.entered.future;
        expect(old.files.single.path, isNot(newer.files.single.path));
        final before = run.container.read(uploadProvider);
        old.progress?.call(1);
        old.release.complete();
        expect(await first, isFalse);
        expect(run.container.read(uploadProvider), before);
        expect(newer.disposed, isFalse);
        expect(await newer.files.single.exists(), isTrue);
        expect(
          DecryptFileUseCase().executeBytes(
            encryptedBytes: await newer.files.single.readAsBytes(),
            aesKey32Bytes: 'b' * 32,
          ),
          [1, 2, 3],
        );
        newer.release.complete();
        expect(await second, isTrue);
        expect(await source.readAsBytes(), [1, 2, 3]);
        expect(await newer.files.single.exists(), isFalse);
      },
    );

    test(
      'a direct factory returning after cancellation is disposed without sending',
      () async {
        final pending = Completer<P2PSenderSession>();
        final entered = Completer<void>();
        final session = _HeldSender();
        final run = await _Run.create(
          factory:
              ({
                required signalingUrl,
                required sessionId,
                accessToken,
                aesKey,
                required onFallbackToCloud,
              }) {
                entered.complete();
                return pending.future;
              },
        );
        run.notifier.setFilesForTesting([]);
        final operation = run.notifier.runP2PSession(
          sessionId: 'old',
          aesKey: 'a' * 32,
        );
        await entered.future;
        run.notifier.cancelUpload();
        pending.complete(session);
        expect(await operation, isFalse);
        expect(session.disposed, isTrue);
        expect(session.entered.isCompleted, isFalse);
        expect(run.container.read(uploadProvider).phase, UploadPhase.cancelled);
      },
    );
  });
}

class _Run {
  _Run(this.container, this.uploads);

  final ProviderContainer container;
  final _Uploads uploads;
  final createEntered = Completer<void>();
  final releaseCreate = Completer<void>();
  int createCalls = 0;
  int completeCalls = 0;

  UploadNotifier get notifier => container.read(uploadProvider.notifier);

  static Future<_Run> create({P2PSenderSessionFactory? factory}) async {
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
    final prefs = await SharedPreferences.getInstance();
    final backend = FakeBackend();
    final dio = Dio();
    final uploads = _Uploads();
    late _Run run;
    dio.httpClientAdapter = FakeHttpAdapter((request) async {
      if (request.path.endsWith('/complete')) run.completeCalls++;
      if (request.method == 'POST' && request.path == 'transfers') {
        run.createCalls++;
        if (run.createCalls == 1) {
          run.createEntered.complete();
          await run.releaseCreate.future;
        }
      }
      return backend.handle(request);
    });
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        uploadServiceProvider.overrideWithValue(uploads),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (factory != null)
          p2pSessionFactoryProvider.overrideWithValue(factory),
      ],
    );
    run = _Run(container, uploads);
    addTearDown(container.dispose);
    run.notifier.setFilesForTesting([
      PlatformFile(
        name: 'old.bin',
        size: 3,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ]);
    return run;
  }
}

class _Uploads extends UploadService {
  final payloads = <Uint8List>[];
  bool holdFirst = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  void Function(int, int)? lateProgress;

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
    payloads.add(bytes ?? await file!.readAsBytes());
    if (holdFirst && payloads.length == 1) {
      lateProgress = onProgress;
      entered.complete();
      await release.future;
    }
    onProgress(size, size);
  }
}

class _HeldSender implements P2PSenderSession {
  final entered = Completer<void>();
  final release = Completer<void>();
  List<File> files = [];
  void Function(int)? progress;
  bool disposed = false;
  @override
  bool get isOpen => true;
  @override
  Future<void> waitUntilOpen({required Duration timeout}) async {}
  @override
  void cancelWait() {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> sendFiles(
    List<File> files, {
    void Function(int)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    this.files = files;
    progress = onProgress;
    entered.complete();
    await release.future;
  }
}
