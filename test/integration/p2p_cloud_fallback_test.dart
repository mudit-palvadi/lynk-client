import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/services/download_service.dart';
import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/core/services/webrtc_peer.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'fedcba9876543210fedcba9876543210';
  setUpAll(() {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
  });

  group('Cloud readiness while choosing reception', () {
    for (final scenario in [
      'already ready',
      'paired with stale preview',
      'ready during negotiation',
      'ready before initialization returns',
      'channel opens during metadata',
      'metadata failure',
      'direct still uploading',
      'cancel during metadata',
      'replace preview during metadata',
      'duplicate start',
    ]) {
      final alreadyReady = scenario == 'already ready';
      final paired = scenario == 'paired with stale preview';
      final directWins = [
        'channel opens during metadata',
        'metadata failure',
        'direct still uploading',
      ].contains(scenario);
      final cancelled = scenario == 'cancel during metadata';
      final replaced = scenario == 'replace preview during metadata';
      final slowInitialization =
          scenario == 'ready before initialization returns';
      test(scenario, () async {
        final sandbox = await Directory.systemTemp.createTemp('lynk-fallback');
        final oldPaths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Paths(sandbox.path);
        addTearDown(() async {
          PathProviderPlatform.instance = oldPaths;
          await sandbox.delete(recursive: true);
        });
        SharedPreferences.setMockInitialValues({});
        final backend = FakeBackend();
        final session = _Receiver();
        final cloud = _Cloud(backend.uploadedObjects);
        final initialization = Completer<void>();
        final metadataRequested = Completer<void>();
        final releaseMetadata = Completer<void>();
        final dio = backend.createDio();
        var watchEnabled = false;
        final holdMetadata =
            scenario == 'channel opens during metadata' ||
            cancelled ||
            replaced;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              if (watchEnabled &&
                  options.method == 'GET' &&
                  options.path.startsWith('transfers/')) {
                expect(options.headers['X-Lynk-Access-Token'], isNotEmpty);
                if (!metadataRequested.isCompleted) {
                  metadataRequested.complete();
                }
                if (holdMetadata) await releaseMetadata.future;
                if (scenario == 'metadata failure') {
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.connectionError,
                    ),
                  );
                  return;
                }
              }
              handler.next(options);
            },
          ),
        );
        var directCalls = 0;
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
            downloadServiceProvider.overrideWithValue(cloud),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            p2pReceiverSessionFactoryProvider.overrideWithValue(({
              required Uri signalingUrl,
              required PeerRole role,
              required String sessionId,
              String? accessToken,
              String? aesKey,
              void Function()? onFallbackToCloud,
            }) async {
              directCalls++;
              if (slowInitialization) await initialization.future;
              return session;
            }),
          ],
        );
        addTearDown(container.dispose);
        final repo = container.read(transferRepositoryProvider);
        final encrypted = EncryptFileUseCase().executeBytes(
          inputBytes: Uint8List.fromList([7, 8, 9]),
          aesKey32Bytes: key,
        );
        final created = (await repo.createTransfer([
          FileItem(
            id: '',
            name: 'cloud.txt',
            size: encrypted.length,
            contentType: 'text/plain',
            status: FileStatus.pending,
          ),
        ])).value!;
        backend.uploadedObjects[created.files.single.uploadUrl!] = encrypted;
        Future<void> completeUpload() async {
          final result = await repo.completeFileUpload(
            transferId: created.id,
            fileId: created.files.single.id,
            senderSecret: created.senderSecret,
          );
          expect(result.isSuccess, isTrue);
        }

        if (alreadyReady) await completeUpload();
        final notifier = container.read(downloadProvider.notifier)
          ..readyPollInterval = const Duration(milliseconds: 10);
        await notifier.loadTransferPreview(
          created.id,
          accessToken: created.accessToken!,
        );
        if (paired) await completeUpload();
        watchEnabled = true;
        var finished = false;
        final reception = notifier
            .startReception(aesKey: key, viaPairing: paired)
            .then((_) => finished = true);
        // Always release an old implementation's pending direct attempt so a
        // regression fails an assertion rather than hanging the test runner.
        addTearDown(() async {
          if (!initialization.isCompleted) initialization.complete();
          if (!releaseMetadata.isCompleted) releaseMetadata.complete();
          notifier.cancelDownload();
          session.onFallbackToCloud?.call();
          await reception;
          await pumpEventQueue();
        });
        if (!alreadyReady && !paired) {
          if (slowInitialization) {
            await _until(() => directCalls == 1);
          } else {
            await _until(() => session.files.hasListener);
          }
          if (holdMetadata || scenario == 'metadata failure') {
            await metadataRequested.future.timeout(const Duration(seconds: 2));
          }
          if (cancelled || replaced) {
            watchEnabled = false;
            if (cancelled) {
              notifier.cancelDownload();
            } else {
              await notifier.loadTransferPreview(
                created.id,
                accessToken: created.accessToken!,
              );
            }
            releaseMetadata.complete();
            await reception.timeout(const Duration(seconds: 2));
            await pumpEventQueue();
            expect(
              container.read(downloadProvider).phase,
              cancelled ? DownloadPhase.cancelled : DownloadPhase.preview,
            );
            expect(session.disposed, isTrue);
            expect(cloud.downloads, 0);
            return;
          }
          if (scenario == 'duplicate start') {
            await notifier
                .startReception(aesKey: key)
                .timeout(const Duration(seconds: 2));
          }
          if (scenario != 'direct still uploading') await completeUpload();
          if (directWins) {
            session.open = true;
            if (holdMetadata) releaseMetadata.complete();
            await Future<void>.delayed(const Duration(milliseconds: 40));
            expect(cloud.downloads, 0);
            final packed = await File(
              '${sandbox.path}/direct.enc',
            ).writeAsBytes(encrypted);
            session.files.add(
              ReceivedFile(
                file: packed,
                name: 'cloud.txt',
                expectedSize: encrypted.length,
              ),
            );
            session.done.complete();
          }
        }
        try {
          await reception.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          session.onFallbackToCloud?.call();
          await reception;
          fail('Ready cloud data still waited for the P2P timeout.');
        }
        expect(finished, isTrue);
        expect(directCalls, alreadyReady || paired ? 0 : 1);
        expect(cloud.downloads, directWins ? 0 : 1);
        expect(container.read(downloadProvider).phase, DownloadPhase.completed);
        final path = container.read(downloadProvider).downloadedPaths.single;
        expect(await File(path).readAsBytes(), [7, 8, 9]);
        if (!alreadyReady && !paired) {
          if (slowInitialization) {
            initialization.complete();
            await _until(() => session.disposed);
          }
          expect(session.disposed, isTrue);
          session.onFallbackToCloud?.call();
          await pumpEventQueue();
          expect(cloud.downloads, directWins ? 0 : 1);
        }
      });
    }
  });
}

Future<void> _until(bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed > const Duration(seconds: 2)) {
      fail('Direct attempt did not start.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Receiver implements P2PFileSession {
  final files = StreamController<ReceivedFile>.broadcast();
  final done = Completer<void>();
  bool disposed = false;
  bool open = false;
  @override
  bool get isOpen => open;
  @override
  void Function()? onFallbackToCloud;
  @override
  Stream<ReceivedFile> get onFileReceived => files.stream;
  @override
  Future<void> get transferDone => done.future;
  @override
  Future<void> dispose() async {
    disposed = true;
    await files.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cloud extends DownloadService {
  _Cloud(this.objects);
  final Map<String, List<int>> objects;
  int downloads = 0;
  @override
  Future<void> downloadFileFromR2({
    required String downloadUrl,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    downloads++;
    final bytes = objects[downloadUrl]!;
    await File(savePath).writeAsBytes(bytes);
    onProgress(bytes.length, bytes.length);
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
