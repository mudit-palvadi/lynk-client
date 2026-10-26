import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/main.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/home/presentation/pages/home_screen.dart';
import 'package:client/features/onboarding/presentation/providers/home_tutorial_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> pumpApp(
    WidgetTester tester, {
    bool tutorialSeen = true,
    UploadNotifier Function()? uploadNotifier,
    Map<String, Object> extraPrefs = const {},
  }) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({
      if (tutorialSeen) HomeTutorialNotifier.key: true,
      ...extraPrefs,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (uploadNotifier != null)
            uploadProvider.overrideWith(uploadNotifier),
          onboardingProvider.overrideWith(() => MockOnboardingNotifier()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const LynkApp(),
      ),
    );

    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('Smoke test for GoRouter navigation rendering HomeScreen', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Send Files'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('Send Files starts clean after a completed transfer', (
    WidgetTester tester,
  ) async {
    await pumpApp(
      tester,
      uploadNotifier: _CompletedUploadNotifier.new,
      extraPrefs: const {'ads_enabled': false},
    );

    expect(find.text('Active Transfer Session'), findsOneWidget);

    await tester.tap(find.text('Send Files'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Files & Media'), findsOneWidget);
    expect(find.text('Active Transfer Session'), findsNothing);
  });

  testWidgets('a first launch walks through the home screen once', (
    WidgetTester tester,
  ) async {
    final prefs = await pumpApp(tester, tutorialSeen: false);

    expect(find.text('1 of 4'), findsOneWidget);
    expect(find.text('Send a file'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Send a file'), findsNothing);
    expect(prefs.getBool(HomeTutorialNotifier.key), isTrue);
  });
}

class MockOnboardingNotifier extends OnboardingNotifier {
  @override
  bool build() => true;
}

class _CompletedUploadNotifier extends UploadNotifier {
  @override
  UploadState build() => UploadState(
    phase: UploadPhase.completed,
    transfer: const Transfer(
      id: 'transfer-1',
      status: TransferStatus.ready,
      totalFiles: 1,
      totalSize: 48,
      files: [],
    ),
    aesKey: 'k' * 32,
  );
}
