import 'package:client/core/theme/app_theme.dart';
import 'package:client/core/theme/theme_mode_provider.dart';
import 'package:client/core/routing/app_router.dart';
import 'package:client/core/providers/ad_consent_provider.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/file_transfer/presentation/pages/file_upload_screen.dart';
import 'package:client/features/home/presentation/pages/home_settings_screen.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routing/deep_link_behavior_test.dart' show pumpApp;
import '../../support/fake_ad_consent.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
  });

  test('dark palette is genuinely dark and readable', () {
    final theme = AppTheme.darkTheme;
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.1));
    final colors = theme.colorScheme;
    for (final pair in [
      (colors.onSurface, colors.surface),
      (colors.onSurfaceVariant, colors.surface),
      (colors.onPrimary, colors.primary),
    ]) {
      final a = pair.$1.computeLuminance();
      final b = pair.$2.computeLuminance();
      expect(
        ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('Settings offers all three appearance choices', (tester) async {
    await pumpApp(tester, initialRoute: '/settings', hasOnboarded: true);
    expect(find.byType(HomeSettingsScreen), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    for (final label in ['Light', 'Dark', 'System']) {
      expect(find.widgetWithText(SimpleDialogOption, label), findsOneWidget);
    }
  });

  testWidgets('a saved dark preference applies on the first app frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ads_enabled': false,
      'theme_mode': 'dark',
    });
    await pumpApp(tester, initialRoute: '/settings', hasOnboarded: true);
    expect(
      Theme.of(tester.element(find.byType(HomeSettingsScreen))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('Settings changes the theme immediately and saves each choice', (
    tester,
  ) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await pumpApp(tester, initialRoute: '/settings', hasOnboarded: true);
    for (final (label, mode, brightness) in [
      ('Dark', ThemeMode.dark, Brightness.dark),
      ('Light', ThemeMode.light, Brightness.light),
      ('System', ThemeMode.system, Brightness.light),
    ]) {
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, label));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(HomeSettingsScreen))).brightness,
        brightness,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(ThemePreference.key),
        mode.name,
      );
    }
  });

  testWidgets(
    'System follows platform changes while explicit choices ignore them',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await pumpApp(tester, initialRoute: '/settings', hasOnboarded: true);
      final element = tester.element(find.byType(HomeSettingsScreen));
      final container = ProviderScope.containerOf(element);
      expect(Theme.of(element).brightness, Brightness.dark);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await tester.pumpAndSettle();
      expect(Theme.of(element).brightness, Brightness.light);
      for (final (mode, platform, expected) in [
        (ThemeMode.dark, Brightness.light, Brightness.dark),
        (ThemeMode.light, Brightness.dark, Brightness.light),
      ]) {
        await container.read(themeModeProvider.notifier).select(mode);
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            platform;
        await tester.pumpAndSettle();
        expect(Theme.of(element).brightness, expected);
      }
    },
  );

  testWidgets(
    'theme changes preserve the router and an active transfer state',
    (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/upload';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      SharedPreferences.setMockInitialValues({
        'has_onboarded': true,
        'ads_enabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            adConsentServiceProvider.overrideWithValue(FakeAdConsent()),
            uploadProvider.overrideWith(_ActiveUpload.new),
          ],
          child: const LynkApp(),
        ),
      );
      await tester.pumpAndSettle();
      final screen = tester.element(find.byType(FileUploadScreen));
      final container = ProviderScope.containerOf(screen);
      final router = container.read(appRouterProvider);
      final active = container.read(uploadProvider);
      for (final mode in ThemeMode.values) {
        await container.read(themeModeProvider.notifier).select(mode);
        await tester.pumpAndSettle();
        expect(container.read(appRouterProvider), same(router));
        expect(container.read(uploadProvider), same(active));
        expect(tester.element(find.byType(FileUploadScreen)), same(screen));
      }
    },
  );

  testWidgets(
    'appearance choices remain reachable at large text in a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, initialRoute: '/settings', hasOnboarded: true);
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(SimpleDialogOption, 'Dark'),
      );
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Dark'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(HomeSettingsScreen))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _ActiveUpload extends UploadNotifier {
  @override
  UploadState build() =>
      const UploadState(phase: UploadPhase.uploading, overallProgress: .4);
}
