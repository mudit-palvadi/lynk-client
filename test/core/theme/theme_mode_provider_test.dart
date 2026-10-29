import 'package:client/core/theme/theme_mode_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final mode in ThemeMode.values) {
    test('loads the saved ${mode.name} preference synchronously', () async {
      SharedPreferences.setMockInitialValues({ThemePreference.key: mode.name});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), mode);
    });
  }

  for (final value in [null, 'invalid', 123, false]) {
    test(
      'falls back to System for missing or invalid preference $value',
      () async {
        SharedPreferences.setMockInitialValues(
          value == null ? {} : {ThemePreference.key: value},
        );
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);
        expect(container.read(themeModeProvider), ThemeMode.system);
      },
    );
  }

  test(
    'every choice updates immediately and survives provider recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
        final saved = container.read(themeModeProvider.notifier).select(mode);
        expect(container.read(themeModeProvider), mode);
        await saved;
        expect(prefs.getString(ThemePreference.key), mode.name);
        final restarted = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expect(restarted.read(themeModeProvider), mode);
        restarted.dispose();
      }
    },
  );
}
