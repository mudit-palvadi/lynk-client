import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/core/services/webrtc_peer.dart';
import 'package:client/features/file_receive/domain/usecases/decrypt_file_use_case.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
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

  group('P2P receive completion', () {
    for (final scenario in [
      (files: 1, transportFirst: true, decryptFails: false),
      (files: 2, transportFirst: true, decryptFails: false),
      (files: 1, transportFirst: false, decryptFails: false),
      (files: 2, transportFirst: false, decryptFails: false),
      (files: 1, transportFirst: true, decryptFails: true),
    ]) {
      final fileCount = scenario.files;
      test(
        'receives $fileCount file(s), done first: ${scenario.transportFirst}, decrypt failure: ${scenario.decryptFails}',
        () async {
          final sandbox = await Directory.systemTemp.createTemp(
            'lynk-p2p-receive',
          );
          final oldPaths = PathProviderPlatform.instance;
          PathProviderPlatform.instance = _FakePaths(sandbox.path);
          addTearDown(() async {
            PathProviderPlatform.instance = oldPaths;
            await sandbox.delete(recursive: true);
          });
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final backend = FakeBackend();
          final session = _FakeReceiver();
          final decryptor = _HeldDecryption(fail: scenario.decryptFails);
          final container = ProviderContainer(
            overrides: [
              apiClientProvider.overrideWithValue(
                ApiClient(dio: backend.createDio()),
              ),
              sharedPreferencesProvider.overrideWithValue(prefs),
              decryptFileUseCaseProvider.overrideWithValue(decryptor),
              p2pReceiverSessionFactoryProvider.overrideWithValue(({
                required Uri signalingUrl,
                required PeerRole role,
                required String sessionId,
                String? accessToken,
                String? aesKey,
                void Function()? onFallbackToCloud,
              }) async {
                expect(role, PeerRole.receiver);
                return session;
              }),
            ],
          );
          addTearDown(container.dispose);
          final files = List.generate(
            fileCount,
            (index) => FileItem(
              id: '',
              name: 'note-$index.txt',
              size: 32,
              contentType: 'text/plain',
              status: FileStatus.pending,
            ),
          );
          final created = await container
              .read(transferRepositoryProvider)
              .createTransfer(files);
          expect(created.isSuccess, isTrue);
          final transfer = created.value!;
          final notifier = container.read(downloadProvider.notifier)
            ..readyTimeout = Duration.zero;
          await notifier.loadTransferPreview(
            transfer.id,
            accessToken: transfer.accessToken ?? '',
          );

          var finished = false;
          final reception = notifier
              .startReception(aesKey: key)
              .then((_) => finished = true);
          addTearDown(() async {
            if (!decryptor.release.isCompleted) decryptor.release.complete();
            await decryptor.settled.future;
            await pumpEventQueue();
            if (!finished) session.onFallbackToCloud?.call();
            await reception;
          });
          await _until(() => session.files.hasListener);
          final plaintexts = <List<int>>[];
          for (var index = 0; index < fileCount; index++) {
            final plaintext = Uint8List.fromList([index, 1, 2, 3, 4]);
            plaintexts.add(plaintext);
            final encrypted = EncryptFileUseCase().executeBytes(
              inputBytes: plaintext,
              aesKey32Bytes: key,
            );
            final file = File(
              '${sandbox.path}/${index == fileCount - 1 ? 'held' : 'first'}.enc',
            );
            await file.writeAsBytes(encrypted);
            session.files.add(
              ReceivedFile(
                file: file,
                name: files[index].name,
                expectedSize: encrypted.length,
              ),
            );
            if (index < fileCount - 1) {
              await _until(
                () => container.read(downloadProvider).overallProgress > 0,
              );
            }
          }
          await decryptor.started.future;
          if (scenario.transportFirst) session.done.complete();
          await pumpEventQueue();

          expect(
            finished,
            isFalse,
            reason: 'Transport done is not decryption/delivery done.',
          );
          expect(session.disposed, isFalse);
          decryptor.release.complete();
          if (!scenario.transportFirst) {
            await _until(
              () => container.read(downloadProvider).overallProgress == 1,
            );
            expect(
              finished,
              isFalse,
              reason: 'File delivery alone is not transport done.',
            );
            session.done.complete();
          }
          await reception.timeout(const Duration(seconds: 3));

          final state = container.read(downloadProvider);
          if (scenario.decryptFails) {
            expect(state.phase, DownloadPhase.failed);
            expect(state.downloadedPaths, isEmpty);
            expect(session.disposed, isTrue);
            return;
          }
          expect(
            state.phase,
            DownloadPhase.completed,
            reason: state.errorMessage,
          );
          expect(state.downloadedPaths, hasLength(fileCount));
          for (var index = 0; index < fileCount; index++) {
            expect(
              await File(state.downloadedPaths[index]).readAsBytes(),
              plaintexts[index],
            );
          }
          expect(session.disposed, isTrue);
        },
      );
    }
  });
}

Future<void> _until(bool Function() ready) async {
  final deadline = Stopwatch()..start();
  while (!ready()) {
    if (deadline.elapsed > const Duration(seconds: 3)) {
      fail('Receiver did not reach the expected stage.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeReceiver implements P2PFileSession {
  final files = StreamController<ReceivedFile>.broadcast();
  final done = Completer<void>();
  bool disposed = false;

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

class _HeldDecryption extends DecryptFileUseCase {
  _HeldDecryption({this.fail = false});
  final bool fail;
  final started = Completer<void>();
  final release = Completer<void>();
  final settled = Completer<void>();

  @override
  Future<File> execute({
    required File encryptedFile,
    required String aesKey32Bytes,
    required String outputPath,
  }) async {
    if (encryptedFile.path.endsWith('held.enc')) {
      started.complete();
      await release.future;
    }
    try {
      if (fail) throw StateError('Simulated decryption failure');
      return await super.execute(
        encryptedFile: encryptedFile,
        aesKey32Bytes: aesKey32Bytes,
        outputPath: outputPath,
      );
    } finally {
      if (encryptedFile.path.endsWith('held.enc')) settled.complete();
    }
  }
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
