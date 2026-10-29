import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/errors/failures.dart';
import 'package:client/core/errors/result.dart';
import 'package:client/core/providers/ad_consent_provider.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/core/services/webrtc_peer.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/domain/repositories/transfer_repository.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:client/features/file_transfer/presentation/pages/download_progress_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_ad_consent.dart';

const _firstKey = '0123456789abcdef0123456789abcdef';
const _secondKey = 'fedcba9876543210fedcba9876543210';
String _link(String id, String key, String token) =>
    'https://lynkshare.app/send/$id#$key&a=$token';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sender QR Direct reception through the real router', () {
    for (final cold in [true, false]) {
      testWidgets(
        '${cold ? 'cold' : 'warm'} link joins Direct before cloud URLs',
        (tester) async {
          final run = await _Run.launch(tester, cold: cold);
          if (!cold) {
            await tester.binding.handlePushRoute(
              _link('first', _firstKey, 'first-token'),
            );
          }
          await _pumpUntil(tester, () => run.sessions.isNotEmpty);
          expect(run.joins, [('first', _firstKey, 'first-token')]);
          run.expectNativeConfiguration();
          expect(run.repo.cloudRequests, isEmpty);
          expect(
            run.container.read(downloadProvider).phase,
            DownloadPhase.downloading,
          );
          expect(run.container.read(downloadProvider).aesKey, _firstKey);
          await run.deliverFile(tester, _firstKey);
          await run.close(tester);
        },
      );
    }

    for (final replacement in [
      (key: _secondKey, token: 'first-token'),
      (key: _firstKey, token: 'replacement-token'),
    ]) {
      testWidgets(
        'same transfer reloads changed ${replacement.key == _secondKey ? 'key' : 'token'}',
        (tester) async {
          final run = await _Run.launch(tester, cold: true);
          await _pumpUntil(tester, () => run.sessions.isNotEmpty);
          final original = run.sessions.single;
          await tester.binding.handlePushRoute(
            _link('first', replacement.key, replacement.token),
          );
          await _pumpUntil(tester, () => run.joins.length == 2);
          expect(run.joins.last, ('first', replacement.key, replacement.token));
          expect(run.repo.metadataRequests, [
            ('first', 'first-token'),
            ('first', replacement.token),
          ]);
          expect(original.disposed, isTrue);
          expect(run.repo.cloudRequests, isEmpty);
          run.expectNativeConfiguration();
          await run.deliverFile(tester, replacement.key);
          await run.close(tester);
        },
      );
    }

    testWidgets(
      'a replacement sender link reloads and retires the old Direct session',
      (tester) async {
        final run = await _Run.launch(tester, cold: true);
        await _pumpUntil(tester, () => run.sessions.isNotEmpty);
        final original = run.sessions.single;
        await tester.binding.handlePushRoute(
          _link('second', _secondKey, 'second-token'),
        );
        await _expectSecondPreview(tester, run.repo);
        await _pumpUntil(tester, () => run.joins.length == 2);
        expect(run.joins.last, ('second', _secondKey, 'second-token'));
        run.expectNativeConfiguration();
        expect(original.disposed, isTrue);
        expect(run.container.read(downloadProvider).transfer?.id, 'second');
        expect(run.repo.cloudRequests, isEmpty);
        await run.close(tester);
      },
    );

    testWidgets(
      'a newer link wins while the previous metadata request is pending',
      (tester) async {
        final repo = _Repository()..holdFirst = true;
        final run = await _Run.launch(tester, cold: true, repository: repo);
        await _pumpUntil(tester, () => repo.metadataRequests.isNotEmpty);
        await tester.binding.handlePushRoute(
          _link('second', _secondKey, 'second-token'),
        );
        await _expectSecondPreview(tester, run.repo);
        await _pumpUntil(tester, () => run.joins.isNotEmpty);
        repo.first.complete(Result.success(_transfer('first')));
        await tester.pump();
        expect(run.joins, [('second', _secondKey, 'second-token')]);
        run.expectNativeConfiguration();
        expect(run.container.read(downloadProvider).transfer?.id, 'second');
        expect(run.repo.cloudRequests, isEmpty);
        await run.close(tester);
      },
    );
  });
}

Future<void> _expectSecondPreview(WidgetTester tester, _Repository repo) async {
  await _pumpUntil(tester, () {
    final screens = tester.widgetList<DownloadProgressScreen>(
      find.byType(DownloadProgressScreen),
    );
    return screens.any((screen) => screen.transferId == 'second');
  });
  await tester.pump(const Duration(milliseconds: 100));
  expect(repo.metadataRequests, contains(('second', 'second-token')));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (ready()) return;
  }
  fail(
    'The expected receive stage was not reached; '
    'receive screens: ${find.byType(DownloadProgressScreen).evaluate().length}.',
  );
}

Transfer _transfer(String id) => Transfer(
  id: id,
  status: TransferStatus.uploading,
  totalFiles: 1,
  totalSize: 32,
  files: [
    const FileItem(
      id: 'file',
      name: 'note.txt',
      size: 32,
      contentType: 'application/octet-stream',
      status: FileStatus.pending,
    ),
  ],
);

class _Run {
  _Run(this.repo, this.sandbox);
  final _Repository repo;
  final Directory sandbox;
  final joins = <(String, String?, String?)>[];
  final sessions = <_Receiver>[];
  final configurations = <(Uri, PeerRole, String, int, int)>[];
  late ProviderContainer container;
  bool closed = false;

  static Future<_Run> launch(
    WidgetTester tester, {
    required bool cold,
    _Repository? repository,
  }) async {
    final sandbox = await tester.runAsync(
      () => Directory.systemTemp.createTemp('lynk-qr-link-'),
    );
    final run = _Run(repository ?? _Repository(), sandbox!);
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(run.sandbox.path);
    addTearDown(() async {
      PathProviderPlatform.instance = previousPaths;
      if (!run.repo.first.isCompleted) {
        run.repo.first.complete(
          Result.failure(const NetworkFailure('test finished')),
        );
      }
      await tester.runAsync(() => run.sandbox.delete(recursive: true));
    });
    SharedPreferences.setMockInitialValues({
      'ads_enabled': false,
      'has_onboarded': true,
      'has_seen_home_tutorial': true,
    });
    final prefs = await SharedPreferences.getInstance();
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
    PendingDeepLink.clear();
    tester.binding.platformDispatcher.defaultRouteNameTestValue = cold
        ? _link('first', _firstKey, 'first-token')
        : '/upload';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    addTearDown(PendingDeepLink.clear);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          adConsentServiceProvider.overrideWithValue(FakeAdConsent()),
          transferRepositoryProvider.overrideWithValue(run.repo),
          p2pReceiverSessionFactoryProvider.overrideWithValue(({
            required Uri signalingUrl,
            required PeerRole role,
            required String sessionId,
            String? accessToken,
            String? aesKey,
            void Function()? onFallbackToCloud,
            int maxFiles = 10,
            int maxBytes = 0,
          }) async {
            run.configurations.add((
              signalingUrl,
              role,
              sessionId,
              maxFiles,
              maxBytes,
            ));
            run.joins.add((sessionId, aesKey, accessToken));
            final receiver = _Receiver();
            run.sessions.add(receiver);
            return receiver;
          }),
        ],
        child: const LynkApp(),
      ),
    );
    run.container = ProviderScope.containerOf(
      tester.element(find.byType(LynkApp)),
    );
    addTearDown(() => run.close(tester));
    return run;
  }

  void expectNativeConfiguration() {
    for (final (uri, role, id, maxFiles, maxBytes) in configurations) {
      expect(uri.scheme, 'wss');
      expect(uri.host, 'api.test.local');
      expect(uri.path, '/ws/signaling/$id');
      expect(uri.port, anyOf(0, 443));
      expect(role, PeerRole.receiver);
      expect(maxFiles, 1);
      expect(maxBytes, 32);
    }
  }

  Future<void> deliverFile(WidgetTester tester, String key) async {
    final session = sessions.last;
    await _pumpUntil(tester, () => session.files.hasListener);
    final plain = Uint8List.fromList([7, 8, 9]);
    final packed = EncryptFileUseCase().executeBytes(
      inputBytes: plain,
      aesKey32Bytes: key,
    );
    final encrypted = File('${sandbox.path}/received.enc');
    await tester.runAsync(() => encrypted.writeAsBytes(packed));
    session.files.add(
      ReceivedFile(
        file: encrypted,
        name: 'note.txt',
        expectedSize: packed.length,
      ),
    );
    session.done.complete();
    await _pumpUntil(
      tester,
      () => container.read(downloadProvider).phase == DownloadPhase.completed,
    );
    final saved = container.read(downloadProvider).downloadedPaths.single;
    expect(await tester.runAsync(() => File(saved).readAsBytes()), plain);
    expect(session.receipts, [(1, packed.length)]);
    expect(repo.cloudRequests, isEmpty);
  }

  Future<void> close(WidgetTester tester) async {
    if (closed) return;
    closed = true;
    container.read(downloadProvider.notifier).cancelDownload();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => pumpEventQueue());
  }
}

class _Repository implements TransferRepository {
  final metadataRequests = <(String, String?)>[];
  final cloudRequests = <String>[];
  final first = Completer<Result<Transfer>>();
  bool holdFirst = false;

  @override
  Future<Result<Transfer>> getTransferMetadata(
    String transferId, {
    String? accessToken,
  }) async {
    metadataRequests.add((transferId, accessToken));
    if (holdFirst && transferId == 'first') return first.future;
    return Result.success(_transfer(transferId));
  }

  @override
  Future<Result<List<FileItem>>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  }) async {
    cloudRequests.add(transferId);
    return Result.failure(const ServerFailure('not ready', statusCode: 409));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Receiver implements P2PFileSession {
  final files = StreamController<ReceivedFile>.broadcast();
  final done = Completer<void>();
  bool disposed = false;
  final receipts = <(int, int)>[];
  @override
  Future<void> confirmDelivery({required int files, required int bytes}) async {
    receipts.add((files, bytes));
  }

  @override
  bool get isOpen => false;
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

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}
