import 'dart:async';
import 'package:client/core/providers/ad_consent_provider.dart';
import 'package:client/core/services/ad_consent_service.dart';
import '../../support/fake_ad_consent.dart';

import 'package:client/features/home/presentation/pages/home_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/main.dart';
import 'package:client/core/providers/app_update_provider.dart';
import 'package:client/core/providers/download_notifier.dart';
import 'package:client/core/providers/download_state.dart';
import 'package:client/core/routing/app_router.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/core/routing/transfer_route_args.dart';
import 'package:client/core/widgets/app_update_gate.dart';
import 'package:client/features/file_transfer/presentation/pages/download_progress_screen.dart';
import 'package:client/features/file_transfer/presentation/pages/file_upload_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/pages/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _CountingConsent extends FakeAdConsent {
  int refreshes = 0;

  @override
  Future<AdConsentResult> refresh() {
    refreshes++;
    return super.refresh();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.ffuf.in_app_update/methods');
  late List<String> calls;
  late Future<Object?> Function(MethodCall) respond;

  Map<String, Object?> updateInfo(int availability) => {
    'updateAvailability': availability,
    'immediateAllowed': true,
    'flexibleAllowed': true,
    'availableVersionCode': 999,
    'installStatus': 0,
    'packageName': 'app.xynix.lynk',
    'updatePriority': 0,
  };

  Future<void> launch(
    WidgetTester tester, {
    bool enabled = true,
    bool onboarded = true,
    FakeAdConsent? consent,
    String theme = 'system',
  }) async {
    SharedPreferences.setMockInitialValues({
      'has_onboarded': onboarded,
      'has_seen_home_tutorial': true,
      'ads_enabled': false,
      'theme_mode': theme,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adConsentServiceProvider.overrideWithValue(
            consent ?? FakeAdConsent(),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
          appUpdateEnabledProvider.overrideWithValue(enabled),
          downloadProvider.overrideWith(_OfflineDownload.new),
          uploadProvider.overrideWith(_Upload.new),
        ],
        child: const LynkApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  setUp(() {
    PendingDeepLink.clear();
    PackageInfo.setMockInitialValues(
      appName: 'Lynk',
      packageName: 'app.xynix.lynk',
      version: '0.1.0',
      buildNumber: '4',
      buildSignature: '',
    );
    calls = [];
    respond = (_) async => updateInfo(1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call.method);
          return respond(call);
        });
  });

  tearDown(() {
    PendingDeepLink.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('required Google Play update gate', () {
    testWidgets('the blocked update screen honors the saved dark theme', (
      tester,
    ) async {
      respond = (_) async => updateInfo(0);
      await launch(tester, theme: 'dark');
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Update required'))).brightness,
        Brightness.dark,
      );
      expect(find.byType(HomeScreen), findsNothing);
    });
    testWidgets('checks Play before mounting the transfer app', (tester) async {
      final check = Completer<Object?>();
      final consent = _CountingConsent();
      respond = (_) => check.future;
      await launch(tester, consent: consent);

      expect(calls, ['checkForUpdate']);
      expect(find.byType(HomeScreen), findsNothing);
      expect(consent.refreshes, 0);
      check.complete(updateInfo(1));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(consent.refreshes, 1);
    });

    testWidgets('cancelling an immediate update never unlocks the app', (
      tester,
    ) async {
      respond = (call) async {
        if (call.method == 'checkForUpdate') return updateInfo(2);
        throw PlatformException(code: 'USER_DENIED_UPDATE');
      };
      await launch(tester);
      await tester.pumpAndSettle();

      expect(calls, contains('performImmediateUpdate'));
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('a failed check blocks with Retry instead of failing open', (
      tester,
    ) async {
      respond = (_) async => throw PlatformException(code: 'CHECK_FAILED');
      await launch(tester);
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      respond = (_) async => updateInfo(1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('unknown availability cannot be treated as up to date', (
      tester,
    ) async {
      respond = (_) async => updateInfo(0);
      await launch(tester);
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('disabled gate mounts normally without a native call', (
      tester,
    ) async {
      await launch(tester, enabled: false);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    for (final activePhase in ['uploading', 'waiting', 'downloading']) {
      testWidgets('resume does not interrupt an active $activePhase transfer', (
        tester,
      ) async {
        await launch(tester);
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppUpdateGate)),
        );
        final upload = container.read(uploadProvider.notifier) as _Upload;
        final download =
            container.read(downloadProvider.notifier) as _OfflineDownload;
        if (activePhase == 'uploading') {
          upload.emit(const UploadState(phase: UploadPhase.uploading));
        } else {
          download.emit(
            DownloadState(
              phase: activePhase == 'waiting'
                  ? DownloadPhase.waiting
                  : DownloadPhase.downloading,
            ),
          );
        }
        respond = (call) async {
          if (call.method == 'checkForUpdate') return updateInfo(2);
          throw PlatformException(code: 'USER_DENIED_UPDATE');
        };
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(calls, ['checkForUpdate']);
        expect(find.byType(HomeScreen), findsOneWidget);
        upload.emit(const UploadState());
        download.emit(const DownloadState());
        await tester.pumpAndSettle();
        expect(calls.where((call) => call == 'checkForUpdate').length, 2);
        expect(find.text('Update required'), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
      });
    }

    testWidgets('a gated cold link survives the onboarding replay', (
      tester,
    ) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          'https://lynkshare.app/send/onboarded#secret&a=token';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final check = Completer<Object?>();
      respond = (_) => check.future;
      await launch(tester, onboarded: false);
      expect(find.byType(OnboardingScreen), findsNothing);
      check.complete(updateInfo(1));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'onboarded');
      expect(screen.aesKey, 'secret');
      expect(screen.accessToken, 'token');
    });

    testWidgets('a hung check times out into blocking Retry', (tester) async {
      final check = Completer<Object?>();
      respond = (_) => check.future;
      await launch(tester);
      await tester.pump(AppUpdateNotifier.checkTimeout);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      // Completing a timed-out request must not admit the app or open a flow.
      check.complete(updateInfo(2));
      await tester.pumpAndSettle();
      expect(calls, ['checkForUpdate']);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('system Back cannot bypass a cancelled update', (tester) async {
      respond = (call) async {
        if (call.method == 'checkForUpdate') return updateInfo(2);
        throw PlatformException(code: 'USER_DENIED_UPDATE');
      };
      await launch(tester);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets(
      'cold shared links wait for admission with credentials intact',
      (tester) async {
        tester.binding.platformDispatcher.defaultRouteNameTestValue =
            'https://lynkshare.app/send/cold#secret&a=token';
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );
        final check = Completer<Object?>();
        respond = (_) => check.future;
        await launch(tester);
        expect(find.byType(DownloadProgressScreen), findsNothing);
        check.complete(updateInfo(1));
        await tester.pumpAndSettle();
        final screen = tester.widget<DownloadProgressScreen>(
          find.byType(DownloadProgressScreen),
        );
        expect(screen.transferId, 'cold');
        expect(screen.aesKey, 'secret');
        expect(screen.accessToken, 'token');
      },
    );

    testWidgets('warm links received before admission stay in memory', (
      tester,
    ) async {
      final check = Completer<Object?>();
      respond = (_) => check.future;
      await launch(tester);
      await tester.binding.handlePushRoute('lynk://send/warm#secret&a=token');
      await tester.pump();
      expect(find.byType(DownloadProgressScreen), findsNothing);
      check.complete(updateInfo(1));
      await tester.pumpAndSettle();
      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'warm');
      expect(screen.aesKey, 'secret');
      expect(screen.accessToken, 'token');
    });

    testWidgets('resume gate preserves existing memory-only route arguments', (
      tester,
    ) async {
      await launch(tester);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppUpdateGate)),
      );
      const arguments = DownloadArguments(
        transferId: 'internal',
        aesKey: 'key',
        accessToken: 'token',
      );
      container
          .read(appRouterProvider)
          .go(arguments.location, extra: arguments);
      await tester.pumpAndSettle();
      final original = tester.element(find.byType(DownloadProgressScreen));
      final check = Completer<Object?>();
      respond = (_) => check.future;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(DownloadProgressScreen), findsNothing);
      expect(
        find.byType(DownloadProgressScreen, skipOffstage: false),
        findsOneWidget,
      );
      check.complete(updateInfo(1));
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(DownloadProgressScreen)),
        same(original),
      );
      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.aesKey, 'key');
      expect(screen.accessToken, 'token');
    });

    testWidgets('blocked warm links replay once after a resume check', (
      tester,
    ) async {
      await launch(tester);
      await tester.pumpAndSettle();
      final check = Completer<Object?>();
      respond = (_) => check.future;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.binding.handlePushRoute(
        'lynk://receive/new-session#pk=public-key',
      );
      await tester.pump();
      expect(find.byType(FileUploadScreen), findsNothing);
      check.complete(updateInfo(1));
      await tester.pumpAndSettle();
      final screen = tester.widget<FileUploadScreen>(
        find.byType(FileUploadScreen),
      );
      expect(screen.attachToSessionId, 'new-session');
      expect(screen.receiverPk, 'public-key');
      expect(PendingDeepLink.take(), isNull);
    });
  });
}

class _OfflineDownload extends DownloadNotifier {
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

class _Upload extends UploadNotifier {
  @override
  UploadState build() => const UploadState();

  void emit(UploadState next) => state = next;
}
