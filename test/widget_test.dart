import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/main.dart';
import 'package:client/features/home/presentation/pages/home_screen.dart';
import 'package:client/features/onboarding/presentation/providers/home_tutorial_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> pumpApp(
    WidgetTester tester, {
    bool tutorialSeen = true,
  }) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(
      tutorialSeen ? {HomeTutorialNotifier.key: true} : <String, Object>{},
    );
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Receive Files'), findsOneWidget);
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
