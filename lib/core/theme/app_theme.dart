import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFFF7F8FA);
  // Light-palette constants retained for callers and palette contract tests.
  static const Color darkBg = background;
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF3455DB);
  static const Color secondary = Color(0xFF087F72);
  static const Color error = Color(0xFFB42318);
  static const Color textPrimary = Color(0xFF172033);
  static const Color textSecondary = Color(0xFF526079);
  static const Color border = Color(0xFFDCE1EB);
  static const Color accentSurface = Color(0xFFEBEFFE);

  static AppColors of(BuildContext context) => AppColors(Theme.of(context));

  static ThemeData get darkTheme => _build(
    Brightness.dark,
    const Color(0xFF101521),
    const ColorScheme.dark(
      primary: Color(0xFFB5C4FF),
      onPrimary: Color(0xFF14245F),
      secondary: Color(0xFF72D9C7),
      onSecondary: Color(0xFF00382F),
      secondaryContainer: Color(0xFF253357),
      onSecondaryContainer: Color(0xFFB5C4FF),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF1A2232),
      onSurface: Color(0xFFF0F2FA),
      onSurfaceVariant: Color(0xFFB7C1D5),
      outline: Color(0xFF46526A),
    ),
  );

  static ThemeData get lightTheme {
    return _build(
      Brightness.light,
      background,
      const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: accentSurface,
        onSecondaryContainer: primary,
        error: error,
        onError: Colors.white,
        surface: cardBg,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: border,
      ),
    );
  }

  static ThemeData _build(
    Brightness brightness,
    Color background,
    ColorScheme colors,
  ) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      primaryColor: colors.primary,
      colorScheme: colors,
      dividerColor: colors.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: colors.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.outline),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: colors.onSurface,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.7,
        ),
        titleLarge: TextStyle(
          color: colors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(
          color: colors.onSurface,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Contextual colors keep custom widgets on the same palette as Material.
class AppColors {
  const AppColors(this.theme);
  final ThemeData theme;
  Color get darkBg => theme.scaffoldBackgroundColor;
  Color get cardBg => theme.colorScheme.surface;
  Color get primary => theme.colorScheme.primary;
  Color get secondary => theme.colorScheme.secondary;
  Color get error => theme.colorScheme.error;
  Color get textPrimary => theme.colorScheme.onSurface;
  Color get textSecondary => theme.colorScheme.onSurfaceVariant;
  Color get border => theme.colorScheme.outline;
  Color get accentSurface => theme.colorScheme.secondaryContainer;
}
