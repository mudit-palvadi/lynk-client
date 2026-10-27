import 'package:client/core/providers/ad_consent_provider.dart';
import '../../../../support/fake_ad_consent.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/providers/receiver_notifier.dart';
import 'package:client/core/routing/app_router.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/features/file_receive/presentation/pages/enter_code_screen.dart';
import 'package:client/features/file_receive/presentation/pages/receive_qr_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/home/presentation/pages/home_screen.dart';
import 'package:client/features/home/presentation/pages/home_settings_screen.dart';
import 'package:client/features/home/presentation/providers/home_navigation_provider.dart';
import 'package:client/features/onboarding/presentation/providers/home_tutorial_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/features/recent_transfers/domain/entities/recent_transfer_record.dart';
import 'package:client/features/recent_transfers/presentation/providers/recent_transfers_notifier.dart';
import 'package:client/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ads_enabled': false,
      HomeTutorialNotifier.key: true,
    });
    PendingDeepLink.clear();
  });
  tearDown(PendingDeepLink.clear);

  Future<ProviderContainer> pumpHome(WidgetTester tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/home';
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
          homeVersionProvider.overrideWith((ref) async => 'v0.1.0+122'),
        ],
        child: const LynkApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  }

  Future<void> selectRole(WidgetTester tester, String label) async {
    final navigation = find.byType(NavigationBar);
    expect(navigation, findsOneWidget);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  group('role-first home experience', () {
    testWidgets('starts on Send with stable role navigation', (tester) async {
      await pumpHome(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      for (final role in ['Send', 'Receive', 'Activity']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(role),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Send Files'), findsOneWidget);
      expect(find.text('Show receiving QR'), findsNothing);
    });

    testWidgets('Receive explains all three paths without starting a session', (
      tester,
    ) async {
      final container = await pumpHome(tester);
      await selectRole(tester, 'Receive');

      expect(find.text('Scan sender’s QR'), findsOneWidget);
      expect(find.text('Enter code'), findsOneWidget);
      expect(find.text('Show receiving QR'), findsOneWidget);
      expect(
        find.text('The sender scans the QR, then chooses files.'),
        findsOneWidget,
      );
      expect(
        (container.read(receiverProvider.notifier) as _Receiver).creates,
        0,
      );
      expect(find.byType(ReceiveQrScreen), findsNothing);
    });

    testWidgets('Enter code opens the existing code receiver', (tester) async {
      final container = await pumpHome(tester);
      await selectRole(tester, 'Receive');
      await tester.tap(find.text('Enter code'));
      await tester.pumpAndSettle();

      expect(find.byType(EnterCodeScreen), findsOneWidget);
      expect(
        (container.read(receiverProvider.notifier) as _Receiver).creates,
        0,
      );
      container.read(appRouterProvider).pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.text('Show receiving QR'), findsOneWidget);
    });

    testWidgets('showing a receiving QR is an explicit user action', (
      tester,
    ) async {
      final container = await pumpHome(tester);
      // Keep the auto-dispose fake alive while navigating away from the hub.
      final receiver = container.listen(receiverProvider, (_, _) {});
      addTearDown(receiver.close);
      await selectRole(tester, 'Receive');
      await tester.tap(find.text('Show receiving QR'));
      await tester.pumpAndSettle();

      expect(find.byType(ReceiveQrScreen), findsOneWidget);
      expect(
        (container.read(receiverProvider.notifier) as _Receiver).creates,
        1,
      );
    });

    testWidgets('Activity has an empty state instead of a blank screen', (
      tester,
    ) async {
      await pumpHome(tester);
      await selectRole(tester, 'Activity');

      expect(find.text('Transfers appear here.'), findsOneWidget);
      expect(find.text('Send Files'), findsNothing);
      expect(find.text('Show receiving QR'), findsNothing);
    });

    testWidgets('Activity retains existing history and its file actions', (
      tester,
    ) async {
      final container = await pumpHome(tester);
      await selectRole(tester, 'Activity');
      for (final type in RecentTransferType.values) {
        await container
            .read(recentTransfersProvider.notifier)
            .addRecord(
              RecentTransferRecord(
                id: type.name,
                type: type,
                fileNames: ['${type.name}.txt'],
                totalSize: 12,
                timestamp: DateTime(2026, 10, 27),
                status: 'completed',
                filePaths: ['/mock/${type.name}.txt'],
              ),
            );
        await tester.pumpAndSettle();
      }

      expect(find.text('Transfers appear here.'), findsNothing);
      expect(find.text('received.txt'), findsOneWidget);
      expect(find.text('sent.txt'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Re-send'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets(
      'Settings keeps the download folder accessible and returns to Receive',
      (tester) async {
        final container = await pumpHome(tester);
        await selectRole(tester, 'Receive');
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();

        expect(find.byType(HomeSettingsScreen), findsOneWidget);
        expect(find.text('Download folder'), findsOneWidget);
        expect(find.text('v0.1.0+122'), findsOneWidget);
        container.read(appRouterProvider).pop();
        await tester.pumpAndSettle();
        expect(find.text('Show receiving QR'), findsOneWidget);
        expect(
          (container.read(receiverProvider.notifier) as _Receiver).creates,
          0,
        );
      },
    );

    testWidgets('receiving help can be replayed without changing onboarding', (
      tester,
    ) async {
      final container = await pumpHome(tester);
      await selectRole(tester, 'Receive');
      await tester.ensureVisible(find.text('How receiving works'));
      await tester.tap(find.text('How receiving works'));
      await tester.pumpAndSettle();

      expect(find.text('Sender QR'), findsOneWidget);
      expect(find.text('Receiving QR'), findsOneWidget);
      expect(container.read(homeTutorialProvider), isTrue);
      expect(
        (container.read(receiverProvider.notifier) as _Receiver).creates,
        0,
      );
    });

    testWidgets('changing roles preserves selected files', (tester) async {
      final container = await pumpHome(tester);
      final files = [PlatformFile(name: 'example.txt', size: 12)];
      (container.read(uploadProvider.notifier) as _Upload).select(files);
      await tester.pumpAndSettle();

      await selectRole(tester, 'Receive');
      await selectRole(tester, 'Activity');
      await selectRole(tester, 'Send');

      expect(container.read(uploadProvider).phase, UploadPhase.selecting);
      expect(container.read(uploadProvider).selectedFiles, files);
      expect(find.text('Send Files'), findsOneWidget);
    });

    testWidgets('Receive remains usable on a small screen with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester);
      await selectRole(tester, 'Receive');

      await tester.ensureVisible(find.text('Show receiving QR'));
      expect(find.text('Show receiving QR').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
    });

    for (final size in [const Size(320, 568), const Size(640, 360)]) {
      testWidgets('all roles scroll without overflow at $size and 2x text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpHome(tester);
        for (final role in ['Send', 'Receive', 'Activity']) {
          await selectRole(tester, role);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}

class _Onboarded extends OnboardingNotifier {
  @override
  bool build() => true;
}

class _Upload extends UploadNotifier {
  @override
  UploadState build() => const UploadState();
  void select(List<PlatformFile> files) =>
      state = UploadState(phase: UploadPhase.selecting, selectedFiles: files);
}

class _Download extends DownloadNotifier {
  @override
  DownloadState build() => const DownloadState();
}

class _Receiver extends ReceiverNotifier {
  int creates = 0;
  @override
  ReceiverState build() => const ReceiverState();
  @override
  Future<void> createSession() async {
    creates++;
    state = const ReceiverState(errorMessage: 'Mock session; no network.');
  }
}
