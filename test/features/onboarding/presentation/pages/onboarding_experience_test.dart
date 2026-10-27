import 'package:client/features/onboarding/presentation/pages/onboarding_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_page_provider.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/file_transfer/presentation/pages/download_progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/routing/deep_link_behavior_test.dart' as deep_links;

void main() {
  group('task-first onboarding', () {
    Future<SharedPreferences> pump(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      SharedPreferences.setMockInitialValues({'ads_enabled': false});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: Consumer(
            builder: (context, ref, _) {
              // The real router observes completion for the whole intro.
              ref.watch(onboardingProvider);
              return MaterialApp(
                theme: AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: const OnboardingScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return prefs;
    }

    Future<void> next(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts with choosing files rather than infrastructure', (
      tester,
    ) async {
      final prefs = await pump(tester);
      expect(find.text('Send without an account.'), findsOneWidget);
      expect(
        find.text('Choose files. Share a QR or code. No account needed.'),
        findsOneWidget,
      );
      expect(find.text('Internet required.'), findsOneWidget);
      expect(find.textContaining('R2'), findsNothing);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(prefs.getBool('has_onboarded'), isNull);
    });

    testWidgets('explains scanning or entering a sender’s code in Receive', (
      tester,
    ) async {
      await pump(tester);
      await next(tester);
      expect(find.text('Have a QR or code?'), findsOneWidget);
      // These are alternatives, not three steps that must all be completed.
      expect(find.text('1'), findsNothing);
      expect(find.byIcon(Icons.pin_outlined), findsOneWidget);
      expect(
        find.text('Open Receive to scan the sender QR or enter the code.'),
        findsOneWidget,
      );
      expect(find.text('Privacy Policy'), findsOneWidget);
    });

    testWidgets('teaches receiver-first QR without promising direct delivery', (
      tester,
    ) async {
      final prefs = await pump(tester);
      await next(tester);
      await next(tester);
      expect(find.text('Let the sender start.'), findsOneWidget);
      expect(
        find.text(
          'Show the receiving QR. The sender scans it and chooses files. Keep this screen open.',
        ),
        findsOneWidget,
      );
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.textContaining('P2P'), findsNothing);
      expect(prefs.getBool('has_onboarded'), isNull);
      await tester.ensureVisible(find.text('Get Started'));
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      expect(prefs.getBool('has_onboarded'), isTrue);
    });

    for (final page in [0, 1]) {
      testWidgets('Skip on page ${page + 1} preserves completion behavior', (
        tester,
      ) async {
        final prefs = await pump(tester);
        if (page == 1) await next(tester);
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
        expect(prefs.getBool('has_onboarded'), isTrue);
        expect(prefs.getKeys(), {'ads_enabled', 'has_onboarded'});
      });
    }

    testWidgets('swiping updates Riverpod progress and can return to Send', (
      tester,
    ) async {
      await pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingScreen)),
      );
      for (var page = 1; page < 3; page++) {
        await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
        await tester.pumpAndSettle();
        expect(container.read(onboardingPageProvider), page);
      }
      expect(find.text('Get Started'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(500, 0), 1000);
      await tester.pumpAndSettle();
      expect(container.read(onboardingPageProvider), 1);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('full onboarding replays a pending link with its credentials', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'ads_enabled': false});
      PendingDeepLink.clear();
      addTearDown(PendingDeepLink.clear);
      await deep_links.pumpApp(
        tester,
        initialRoute:
            'https://lynkshare.app/send/intro-link#test-key&a=test-token',
        hasOnboarded: false,
      );
      await next(tester);
      await next(tester);
      await tester.ensureVisible(find.text('Get Started'));
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();
      final screen = tester.widget<DownloadProgressScreen>(
        find.byType(DownloadProgressScreen),
      );
      expect(screen.transferId, 'intro-link');
      expect(screen.aesKey, 'test-key');
      expect(screen.accessToken, 'test-token');
      expect(PendingDeepLink.take(), isNull);
    });

    for (final size in [const Size(320, 568), const Size(640, 320)]) {
      testWidgets('all pages at $size support 2x text and reachable controls', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pump(tester, textScale: 2);
        expect(tester.takeException(), isNull);
        expect(find.text('Send without an account.'), findsOneWidget);
        for (var page = 0; page < 3; page++) {
          await tester.ensureVisible(find.text('Privacy Policy'));
          expect(tester.takeException(), isNull);
          final action = find.text(page == 2 ? 'Get Started' : 'Next');
          await tester.ensureVisible(action);
          expect(tester.takeException(), isNull);
          if (page < 2) {
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  });
}
