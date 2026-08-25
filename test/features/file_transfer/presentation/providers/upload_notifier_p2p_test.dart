import 'dart:async';
import 'dart:io';

import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeOnboardingNotifier extends OnboardingNotifier {
  @override
  bool build() => true;
}

/// Scriptable fake of the sender-side WebRTC session.
class FakeSenderSession implements P2PSenderSession {
  FakeSenderSession({this.opensAfter = const Duration(milliseconds: 20)})
    : failWaitInstead = false;

  FakeSenderSession.neverOpens()
    : opensAfter = const Duration(hours: 1),
      failWaitInstead = true;

  final Duration opensAfter;
  final bool failWaitInstead;

  bool disposed = false;
  int sendCalls = 0;
  List<File>? lastFiles;
  bool waitCancelled = false;
  bool failSend = false;

  final _cancelled = Completer<void>();

  @override
  bool get isOpen => false;

  @override
  Future<void> waitUntilOpen({required Duration timeout}) async {
    final opened = Future<void>.delayed(opensAfter);
    await Future.any<void>([
      opened,
      Future<void>.delayed(timeout),
      _cancelled.future,
    ]);
    if (_cancelled.isCompleted) {
      throw const SocketException('wait cancelled');
    }
    if (failWaitInstead || opensAfter > timeout) {
      throw TimeoutException('DataChannel did not open in time');
    }
  }

  @override
  Future<void> sendFiles(
    List<File> files, {
    void Function(int totalBytesSent)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    sendCalls++;
    lastFiles = files;
    if (failSend) {
      throw const SocketException('channel died mid-transfer');
    }
    var sent = 0;
    for (final f in files) {
      sent += f.lengthSync();
      onProgress?.call(sent);
      if (shouldAbort != null && shouldAbort()) {
        throw const SocketException('aborted');
      }
    }
  }

  @override
  void cancelWait() {
    waitCancelled = true;
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late FakeSenderSession fakeSession;
  const tinyWindow = Duration(milliseconds: 150);

  late SharedPreferences mockPrefs;

  Future<ProviderContainer> makeContainer() async {
    mockPrefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        onboardingProvider.overrideWith(() => FakeOnboardingNotifier()),
        sharedPreferencesProvider.overrideWithValue(mockPrefs),
        p2pSessionFactoryProvider.overrideWithValue(({
          required signalingUrl,
          required sessionId,
          required onFallbackToCloud,
        }) async {
          return fakeSession;
        }),
        p2pAutoFallbackDurationProvider.overrideWithValue(tinyWindow),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  File tempFileOf(String name, int size) {
    final file = File(
      '${Directory.systemTemp.path}/'
      'p2p_stage_${DateTime.now().microsecondsSinceEpoch}_$name',
    );
    file.writeAsBytesSync(List.filled(size, 9));
    return file;
  }

  group('P2P send stages (QR-first redesign)', () {
    setUp(() => fakeSession = FakeSenderSession());

    test('stage order preparing -> waiting -> transferring', () async {
      final container = await makeContainer();
      final notifier = container.read(uploadProvider.notifier);
      notifier.setTransferMode(TransferMode.p2p);

      final stages = <P2PSendStage>[];
      final sub = container.listen<UploadState>(uploadProvider, (_, next) {
        if (stages.isEmpty || stages.last != next.p2pStage) {
          stages.add(next.p2pStage);
        }
      });

      final srcA = tempFileOf('a.bin', 70 * 1024);
      final srcB = tempFileOf('b.bin', 10 * 1024);
      addTearDown(() {
        srcA.deleteSync();
        srcB.deleteSync();
      });
      notifier.setFilesForTesting([
        PlatformFile(name: 'a.bin', size: srcA.lengthSync(), path: srcA.path),
        PlatformFile(name: 'b.bin', size: srcB.lengthSync(), path: srcB.path),
      ]);

      final ok = await notifier.runP2PSession(
        sessionId: 'room-1',
        aesKey: 'k' * 32,
      );
      sub.close();

      expect(ok, isTrue);
      expect(stages, [
        P2PSendStage.none,
        P2PSendStage.preparing,
        P2PSendStage.waitingForReceiver,
        P2PSendStage.transferring,
        P2PSendStage.none,
      ]);
      expect(fakeSession.sendCalls, 1);
      expect(fakeSession.disposed, isTrue);
    });

    test('reports monotonic streamed percentage', () async {
      final container = await makeContainer();
      final notifier = container.read(uploadProvider.notifier);
      notifier.setTransferMode(TransferMode.p2p);

      final src = tempFileOf('one.bin', 80 * 1024);
      addTearDown(src.deleteSync);
      notifier.setFilesForTesting([
        PlatformFile(name: 'one.bin', size: src.lengthSync(), path: src.path),
      ]);

      final percents = <double>[];
      final sub = container.listen<UploadState>(uploadProvider, (_, next) {
        if (next.p2pStage == P2PSendStage.transferring &&
            next.overallProgress > 0) {
          percents.add(next.overallProgress);
        }
      });

      await notifier.runP2PSession(sessionId: 'room-2', aesKey: 'k' * 32);
      sub.close();

      expect(percents, isNotEmpty);
      expect(percents.last, 1.0);
      for (var i = 1; i < percents.length; i++) {
        expect(percents[i], greaterThanOrEqualTo(percents[i - 1]));
      }
    });

    test('auto-fallback when nobody connects within window', () async {
      fakeSession = FakeSenderSession.neverOpens();
      final container = await makeContainer();
      final notifier = container.read(uploadProvider.notifier);
      notifier.setTransferMode(TransferMode.p2p);

      final src = tempFileOf('never.bin', 1024);
      addTearDown(src.deleteSync);
      notifier.setFilesForTesting([
        PlatformFile(name: 'never.bin', size: 1024, path: src.path),
      ]);

      final ok = await notifier.runP2PSession(
        sessionId: 'room-3',
        aesKey: 'k' * 32,
      );

      expect(ok, isFalse);
      expect(fakeSession.disposed, isTrue);
      expect(container.read(uploadProvider).p2pStage, P2PSendStage.none);
    });

    test('cancelWait forces immediate fallthrough to cloud', () async {
      final container = await makeContainer();
      final notifier = container.read(uploadProvider.notifier);
      notifier.setTransferMode(TransferMode.p2p);

      final src = tempFileOf('slow.bin', 2048);
      addTearDown(src.deleteSync);
      notifier.setFilesForTesting([
        PlatformFile(name: 'slow.bin', size: 2048, path: src.path),
      ]);

      final run = notifier.runP2PSession(sessionId: 'room-4', aesKey: 'k' * 32);
      while (container.read(uploadProvider).p2pStage !=
          P2PSendStage.waitingForReceiver) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      notifier.forceCloudFallback();
      final ok = await run;

      expect(ok, isFalse);
      expect(fakeSession.waitCancelled, isTrue);
      expect(fakeSession.disposed, isTrue);
    });

    test('mid-transfer failure surfaces failed phase', () async {
      fakeSession = FakeSenderSession()
        ..failSend = true; // custom flag handled below via subclass
      final container = await makeContainer();
      final notifier = container.read(uploadProvider.notifier);
      notifier.setTransferMode(TransferMode.p2p);

      final src = tempFileOf('die.bin', 4096);
      addTearDown(src.deleteSync);
      notifier.setFilesForTesting([
        PlatformFile(name: 'die.bin', size: 4096, path: src.path),
      ]);

      final ok = await notifier.runP2PSession(
        sessionId: 'room-5',
        aesKey: 'k' * 32,
      );

      expect(ok, isFalse);
      expect(container.read(uploadProvider).phase, UploadPhase.failed);
    });
  });
}
