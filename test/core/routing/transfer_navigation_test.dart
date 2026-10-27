import 'package:client/core/providers/ad_consent_provider.dart';
import '../../support/fake_ad_consent.dart';
import 'package:client/core/providers/code_receiver_notifier.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/providers/receiver_notifier.dart';
import 'package:client/core/routing/app_router.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/presentation/helpers/qr_scan_helper.dart';
import 'package:client/features/file_transfer/presentation/pages/download_progress_screen.dart';
import 'package:client/features/file_transfer/presentation/pages/file_upload_screen.dart';
import 'package:client/features/file_transfer/presentation/pages/send_qr_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/sender_code_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/home_tutorial_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _transfer = Transfer(
  id: 'transfer-1',
  status: TransferStatus.ready,
  totalFiles: 1,
  totalSize: 48,
  files: [],
  accessToken: 'private-token',
);
const _key = '0123456789abcdef0123456789abcdef';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ads_enabled': false,
      HomeTutorialNotifier.key: true,
    });
    PendingDeepLink.clear();
  });
  tearDown(PendingDeepLink.clear);

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/upload';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adConsentServiceProvider.overrideWithValue(FakeAdConsent()),
          sharedPreferencesProvider.overrideWithValue(prefs),
          onboardingProvider.overrideWith(_Onboarded.new),
          uploadProvider.overrideWith(_Upload.new),
          downloadProvider.overrideWith(_Download.new),
          receiverProvider.overrideWith(_Receiver.new),
          codeReceiverProvider.overrideWith(_CodeReceiver.new),
          senderCodeProvider.overrideWith(_SenderCode.new),
        ],
        child: const LynkApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(FileUploadScreen)),
    );
  }

  void expectDownload(
    ProviderContainer container,
    WidgetTester tester, {
    required bool viaPairing,
  }) {
    final screen = tester.widget<DownloadProgressScreen>(
      find.byType(DownloadProgressScreen),
    );
    expect(screen.transferId, _transfer.id);
    expect(screen.aesKey, _key);
    expect(screen.accessToken, 'private-token');
    expect(screen.viaPairing, viaPairing);
    expect(
      GoRouterState.of(
        tester.element(find.byType(DownloadProgressScreen)),
      ).uri.toString(),
      '/download-progress/transfer-1',
    );
  }

  void expectSend(ProviderContainer container, WidgetTester tester) {
    final screen = tester.widget<SendQrScreen>(find.byType(SendQrScreen));
    expect(screen.transfer, _transfer);
    expect(screen.aesKey, _key);
    expect(
      GoRouterState.of(
        tester.element(find.byType(SendQrScreen)),
      ).uri.toString(),
      '/send-qr',
    );
  }

  group('real internal navigation emitters', () {
    for (final direct in [false, true]) {
      testWidgets(
        '${direct ? 'direct' : 'cloud'} upload opens a clean send route',
        (tester) async {
          final container = await pump(tester);
          (container.read(uploadProvider.notifier) as _Upload).emit(
            UploadState(
              phase: direct ? UploadPhase.uploading : UploadPhase.completed,
              transfer: _transfer,
              aesKey: _key,
              transferMode: direct ? TransferMode.p2p : TransferMode.cloud,
              p2pStage: direct
                  ? P2PSendStage.waitingForReceiver
                  : P2PSendStage.none,
            ),
          );
          // Direct waiting deliberately animates indefinitely; settle the route,
          // not the spinner.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expectSend(container, tester);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets('home reopens the sender using memory arguments', (
      tester,
    ) async {
      final container = await pump(tester);
      container.read(appRouterProvider).go('/home');
      await tester.pumpAndSettle();
      (container.read(uploadProvider.notifier) as _Upload).emit(
        const UploadState(
          phase: UploadPhase.completed,
          transfer: _transfer,
          aesKey: _key,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active Transfer Session'));
      await tester.pumpAndSettle();
      expectSend(container, tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('home resumes the receiver using memory arguments', (
      tester,
    ) async {
      final container = await pump(tester);
      container.read(appRouterProvider).go('/home');
      await tester.pumpAndSettle();
      (container.read(downloadProvider.notifier) as _Download).emit(
        const DownloadState(
          phase: DownloadPhase.downloading,
          transfer: _transfer,
          aesKey: _key,
          accessToken: 'private-token',
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Downloading: 0%'));
      await tester.tap(find.text('Downloading: 0%'));
      await tester.pumpAndSettle();
      expectDownload(container, tester, viaPairing: false);
    });

    for (final viaPairing in [false, true]) {
      testWidgets('entered code retains pairing=$viaPairing without a query', (
        tester,
      ) async {
        final container = await pump(tester);
        container.read(appRouterProvider).go('/receive-code');
        await tester.pumpAndSettle();
        (container.read(codeReceiverProvider.notifier) as _CodeReceiver).emit(
          CodeReceiveState(
            transferId: _transfer.id,
            aesKey: _key,
            accessToken: 'private-token',
            viaPairing: viaPairing,
          ),
        );
        await tester.pumpAndSettle();
        expectDownload(container, tester, viaPairing: viaPairing);
      });
    }

    testWidgets('receiver QR retains its cloud pairing hint in memory', (
      tester,
    ) async {
      final container = await pump(tester);
      container.read(appRouterProvider).go('/receive-qr');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      (container.read(receiverProvider.notifier) as _Receiver).emit(
        const ReceiverState(
          attachedTransferId: 'transfer-1',
          attachedAesKey: _key,
          attachedAccessToken: 'private-token',
        ),
      );
      await tester.pumpAndSettle();
      expectDownload(container, tester, viaPairing: true);
    });

    testWidgets('scanned fragment credentials become memory arguments', (
      tester,
    ) async {
      final container = await pump(tester);
      final screen = tester.state<ConsumerState<FileUploadScreen>>(
        find.byType(FileUploadScreen),
      );
      final handled = await QrScanHelper.processBarcodeDetection(
        context: screen.context,
        ref: screen.ref,
        attachTransferId: null,
        capture: BarcodeCapture(
          barcodes: [
            const Barcode(
              rawValue:
                  'https://lynkshare.app/send/transfer-1#$_key&a=private-token',
            ),
          ],
        ),
      );
      expect(handled, isTrue);
      await tester.pumpAndSettle();
      expectDownload(container, tester, viaPairing: false);
    });
  });
}

class _Onboarded extends OnboardingNotifier {
  @override
  bool build() => true;
}

class _Upload extends UploadNotifier {
  @override
  UploadState build() => const UploadState();
  void emit(UploadState next) => state = next;
}

class _Download extends DownloadNotifier {
  @override
  DownloadState build() => const DownloadState();
  void emit(DownloadState next) => state = next;
  @override
  Future<void> loadTransferPreview(
    String transferId, {
    String? accessToken,
  }) async {
    state = const DownloadState(
      phase: DownloadPhase.failed,
      errorMessage: 'offline',
    );
  }
}

class _Receiver extends ReceiverNotifier {
  @override
  ReceiverState build() => const ReceiverState();
  @override
  Future<void> createSession() async {}
  void emit(ReceiverState next) => state = next;
}

class _CodeReceiver extends CodeReceiverNotifier {
  @override
  CodeReceiveState build() => const CodeReceiveState();
  void emit(CodeReceiveState next) => state = next;
}

class _SenderCode extends SenderCodeNotifier {
  @override
  SenderCodeState build() =>
      const SenderCodeState(phase: SenderCodePhase.failed);
  @override
  Future<void> ensureStarted({
    required String transferId,
    required String aesKey,
    String? accessToken,
    required TransferMode mode,
  }) async {}
  @override
  void stop() {}
}
