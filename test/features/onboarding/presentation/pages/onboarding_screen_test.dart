import 'package:client/features/onboarding/presentation/pages/onboarding_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedUrl = 'https://sites.google.com/view/xynix-lynk-privacy/home';

  Future<void> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding shows Privacy Policy button on every page', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Privacy Policy'), findsOneWidget);

    // Swipe through all pages and confirm the link stays visible.
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);
    }
  });

  testWidgets('tapping Privacy Policy launches the policy URL externally', (
    tester,
  ) async {
    String? launchedUrl;
    bool launched = false;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch' || call.method == 'launchUrl') {
          launched = true;
          launchedUrl = call.arguments['url'] as String?;
          return true;
        }
        return null;
      },
    );

    await pumpScreen(tester);
    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();

    expect(launched, isTrue);
    expect(launchedUrl, equals(expectedUrl));
  });
}
