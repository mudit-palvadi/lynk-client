import 'package:client/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final values = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (values.last + 0.05) / (values.first + 0.05);
}

void main() {
  test('light paper palette has accessible text and primary actions', () {
    final theme = AppTheme.lightTheme;
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
    expect(theme.colorScheme.primary, const Color(0xFF3455DB));
    expect(theme.colorScheme.onSurface, const Color(0xFF172033));
    expect(
      contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
      greaterThan(4.5),
    );
    for (final background in [
      theme.scaffoldBackgroundColor,
      theme.colorScheme.surface,
    ]) {
      for (final text in [
        theme.colorScheme.onSurface,
        theme.textTheme.bodyMedium!.color!,
      ]) {
        expect(contrast(text, background), greaterThan(4.5));
      }
    }
  });

  test(
    'dark palette is distinct while legacy light tokens stay compatible',
    () {
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(
        AppTheme.darkTheme.colorScheme,
        isNot(AppTheme.lightTheme.colorScheme),
      );
      expect(AppTheme.darkBg, AppTheme.background);
      final colors = AppTheme.darkTheme.colorScheme;
      for (final background in [
        colors.surface,
        AppTheme.darkTheme.scaffoldBackgroundColor,
      ]) {
        for (final text in [colors.onSurface, colors.onSurfaceVariant]) {
          expect(contrast(text, background), greaterThan(4.5));
        }
      }
      expect(contrast(colors.onPrimary, colors.primary), greaterThan(4.5));
      expect(contrast(colors.onError, colors.error), greaterThan(4.5));
      final indicator = Color.alphaBlend(
        colors.primary.withValues(alpha: .22),
        AppTheme.darkTheme.scaffoldBackgroundColor,
      );
      expect(contrast(colors.onSecondaryContainer, indicator), greaterThan(3));
    },
  );

  test('selected navigation icons contrast with their light indicator', () {
    final colors = AppTheme.lightTheme.colorScheme;
    final indicator = Color.alphaBlend(
      AppTheme.primary.withValues(alpha: 0.22),
      AppTheme.background,
    );
    expect(contrast(colors.onSecondaryContainer, indicator), greaterThan(3));
    expect(
      contrast(colors.onSecondaryContainer, colors.secondaryContainer),
      greaterThan(3),
    );
  });
}
