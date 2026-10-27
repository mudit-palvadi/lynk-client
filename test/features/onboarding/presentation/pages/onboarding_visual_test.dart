import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/onboarding/presentation/pages/onboarding_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('calm onboarding presentation', () {
    Future<void> pump(WidgetTester tester, {bool reducedMotion = false}) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'ads_enabled': false});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(onboardingProvider);
              return MaterialApp(
                theme: AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reducedMotion),
                  child: child!,
                ),
                home: const OnboardingScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('uses light paper surfaces and accessible cobalt actions', (
      tester,
    ) async {
      await pump(tester);
      final theme = Theme.of(tester.element(find.byType(OnboardingScreen)));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
      expect(theme.colorScheme.primary, const Color(0xFF3455DB));
      expect(theme.colorScheme.onSurface, const Color(0xFF172033));
      double contrast(Color a, Color b) {
        final values = [a.computeLuminance(), b.computeLuminance()]..sort();
        return (values.last + 0.05) / (values.first + 0.05);
      }

      expect(
        contrast(theme.colorScheme.primary, Colors.white),
        greaterThan(4.5),
      );
      expect(
        contrast(
          theme.textTheme.bodyMedium!.color!,
          theme.scaffoldBackgroundColor,
        ),
        greaterThan(4.5),
      );
    });

    testWidgets('explains one idea per page without repeated step cards', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Send without an account.'), findsOneWidget);
      expect(
        find.text('Choose files. Share a QR or code. No account needed.'),
        findsOneWidget,
      );
      expect(find.text('Choose'), findsNothing);
      expect(find.text('Review'), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Have a QR or code?'), findsOneWidget);
      expect(
        find.text('Open Receive to scan the sender QR or enter the code.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Let the sender start.'), findsOneWidget);
      expect(
        find.text(
          'Show the receiving QR. The sender scans it and chooses files. Keep this screen open.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps navigation chrome outside the sliding pages', (
      tester,
    ) async {
      await pump(tester);
      for (final label in ['Skip', 'Next', 'Privacy Policy']) {
        expect(
          find.descendant(
            of: find.byType(PageView),
            matching: find.text(label),
          ),
          findsNothing,
          reason: '$label must not travel or be replaced during a swipe',
        );
      }
      expect(
        find.descendant(
          of: find.byType(PageView),
          matching: find.byType(IntrinsicHeight),
        ),
        findsNothing,
      );
    });

    testWidgets('primary action does not jump during or after a swipe', (
      tester,
    ) async {
      await pump(tester);
      final before = tester.getRect(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      await tester.timedDrag(
        find.byType(PageView),
        const Offset(-240, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Next'), findsOneWidget);
      expect(
        tester.getRect(find.widgetWithText(ElevatedButton, 'Next')),
        before,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.widgetWithText(ElevatedButton, 'Next')),
        before,
      );
    });

    testWidgets('reduced motion changes pages without a slide animation', (
      tester,
    ) async {
      await pump(tester, reducedMotion: true);
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Have a QR or code?').hitTestable(), findsOneWidget);
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, 1);
      expect(pager.controller!.position.isScrollingNotifier.value, isFalse);
    });

    testWidgets('finishing keeps the same primary action geometry', (
      tester,
    ) async {
      await pump(tester);
      final before = tester.getRect(find.byType(ElevatedButton));
      for (var page = 0; page < 2; page++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(ElevatedButton)), before);
      }
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Skip').hitTestable(), findsNothing);
    });
  });
}
