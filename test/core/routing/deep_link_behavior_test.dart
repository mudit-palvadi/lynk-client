import 'package:client/core/errors/failures.dart';
import 'package:client/core/errors/result.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/providers/ad_consent_provider.dart';
import '../../support/fake_ad_consent.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/domain/repositories/transfer_repository.dart';
import 'package:client/features/file_transfer/presentation/pages/download_progress_screen.dart';
import 'package:client/features/file_transfer/presentation/pages/file_upload_screen.dart';
import 'package:client/features/onboarding/presentation/pages/onboarding_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end deep-link behaviour: the real [LynkApp] with the real router,
/// driven through the same entry points Android uses.
///
/// These tests answer the question the parser tests cannot: *does scanning a
/// QR actually open the right screen with the right key material?* Cold start
/// is simulated with `defaultRouteNameTestValue` (what the engine reports for
/// the launching intent) and warm start with `handlePushRoute` (what the
/// engine reports for `onNewIntent`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Ads off: AdBannerWidget then never touches the AdMob plugin, which has
    // no test implementation.
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
    PendingDeepLink.clear();
  });

  tearDown(() {
    PendingDeepLink.clear();
  });

  group('cold start (launching intent)', () {
    testWidgets('https /send/{id}#{key} opens the download screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: 'https://lynkshare.app/send/abc123#secret-key',
        hasOnboarded: true,
      );

      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'abc123');
      expect(screen.aesKey, 'secret-key');
      expect(find.byType(FileUploadScreen), findsNothing);
    });

    testWidgets('https /receive/{id}#pk={key} opens the upload screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: 'https://lynkshare.app/receive/sess-1#pk=AbC-_x9=',
        hasOnboarded: true,
      );

      final screen = tester.widget<FileUploadScreen>(
        find.byType(FileUploadScreen),
      );
      expect(screen.attachToSessionId, 'sess-1');
      expect(screen.receiverPk, 'AbC-_x9=');
      expect(find.byType(DownloadProgressScreen), findsNothing);
    });

    testWidgets('lynk://send/{id}#{key} opens the download screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: 'lynk://send/offline-1#offline-key',
        hasOnboarded: true,
      );

      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'offline-1');
      expect(screen.aesKey, 'offline-key');
    });

    testWidgets('lynk://receive/{id}#pk={key} opens the upload screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: 'lynk://receive/offline-2#pk=offline-pk',
        hasOnboarded: true,
      );

      final screen = tester.widget<FileUploadScreen>(
        find.byType(FileUploadScreen),
      );
      expect(screen.attachToSessionId, 'offline-2');
      expect(screen.receiverPk, 'offline-pk');
    });

    testWidgets('a deep link never lands on the not-found screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: 'https://lynkshare.app/receive/sess-404#pk=k',
        hasOnboarded: true,
      );

      expect(find.textContaining('not found'), findsNothing);
      expect(find.byType(FileUploadScreen), findsOneWidget);
    });
  });

  group('warm start (onNewIntent push)', () {
    testWidgets('pushing /send/{id}#{key} while running opens the download '
        'screen', (tester) async {
      await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);
      expect(find.byType(FileUploadScreen), findsOneWidget);

      await pushLink(tester, 'https://lynkshare.app/send/warm-1#warm-key');

      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'warm-1');
      expect(screen.aesKey, 'warm-key');
    });

    testWidgets('pushing /receive/{id}#pk={key} while running opens the upload '
        'screen', (tester) async {
      await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);

      await pushLink(tester, 'https://lynkshare.app/receive/warm-2#pk=warm-pk');

      final screen = tester.widget<FileUploadScreen>(
        find.byType(FileUploadScreen),
      );
      expect(screen.attachToSessionId, 'warm-2');
      expect(screen.receiverPk, 'warm-pk');
    });

    testWidgets('pushing a lynk:// link while running opens the right screen', (
      tester,
    ) async {
      await pumpApp(tester, initialRoute: '/upload', hasOnboarded: true);

      await pushLink(tester, 'lynk://receive/warm-3#pk=warm-3-pk');

      final screen = tester.widget<FileUploadScreen>(
        find.byType(FileUploadScreen),
      );
      expect(screen.attachToSessionId, 'warm-3');
      expect(screen.receiverPk, 'warm-3-pk');
    });
  });

  group('onboarding gate', () {
    testWidgets('a cold-start link survives onboarding completion', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialRoute: 'https://lynkshare.app/receive/first-run#pk=pk-1',
        hasOnboarded: false,
      );

      // The gate owns the screen first — the link must not be dropped.
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      final screen = tester.widget<FileUploadScreen>(
        find.byType(FileUploadScreen),
      );
      expect(screen.attachToSessionId, 'first-run');
      expect(screen.receiverPk, 'pk-1');
    });

    testWidgets('a link that arrives while onboarding is showing is replayed '
        'after the gate lifts', (tester) async {
      await pumpApp(tester, initialRoute: '/onboarding', hasOnboarded: false);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await pushLink(tester, 'https://lynkshare.app/send/during-onboarding#k1');

      // Still gated: the link must not bypass onboarding.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(DownloadProgressScreen), findsNothing);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'during-onboarding');
      expect(screen.aesKey, 'k1');
    });

    testWidgets('an ordinary location is not replayed after onboarding', (
      tester,
    ) async {
      await pumpApp(tester, initialRoute: '/onboarding', hasOnboarded: false);

      await pushLink(tester, '/upload');

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(FileUploadScreen), findsNothing);
      expect(PendingDeepLink.take(), isNull);
    });
  });
}

/// Pumps the real app with the platform reporting [initialRoute] as the route
/// that launched it.
Future<void> pumpApp(
  WidgetTester tester, {
  required String initialRoute,
  required bool hasOnboarded,
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = initialRoute;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);

  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adConsentServiceProvider.overrideWithValue(FakeAdConsent()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        onboardingProvider.overrideWith(
          () => _FixedOnboardingNotifier(hasOnboarded),
        ),
        transferRepositoryProvider.overrideWithValue(
          _OfflineTransferRepository(),
        ),
      ],
      child: const LynkApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Delivers a link the way Android does for an already-running app.
Future<void> pushLink(WidgetTester tester, String location) async {
  await tester.binding.handlePushRoute(location);
  await tester.pumpAndSettle();
}

class _FixedOnboardingNotifier extends OnboardingNotifier {
  _FixedOnboardingNotifier(this._value);

  final bool _value;

  @override
  bool build() => _value;
}

/// Fails every call immediately so screens settle into their error state
/// without touching the network or the file system.
class _OfflineTransferRepository implements TransferRepository {
  @override
  Future<Result<Transfer>> createTransfer(List<FileItem> files) async =>
      Result.failure(const NetworkFailure('offline'));

  @override
  Future<Result<void>> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  }) async => Result.failure(const NetworkFailure('offline'));

  @override
  Future<Result<Transfer>> getTransferMetadata(
    String transferId, {
    String? accessToken,
  }) async => Result.failure(const NetworkFailure('offline'));

  @override
  Future<Result<List<FileItem>>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  }) async => Result.failure(const NetworkFailure('offline'));

  @override
  Future<Result<void>> cancelTransfer(
    String transferId, {
    String? senderSecret,
  }) async => Result.failure(const NetworkFailure('offline'));

  @override
  Future<Result<void>> extendTransfer(
    String transferId, {
    String? senderSecret,
  }) async => Result.failure(const NetworkFailure('offline'));
}
