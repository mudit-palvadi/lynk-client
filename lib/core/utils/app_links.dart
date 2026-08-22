import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central registry of external links used across the app.
class AppLinks {
  AppLinks._();

  /// Default falls back to the published Google Sites page. Override via
  /// PRIVACY_POLICY_URL in the bundled .env asset if the location changes.
  static const String defaultPrivacyPolicyUrl =
      'https://sites.google.com/view/xynix-lynk-privacy/home';

  static String get privacyPolicyUrl {
    try {
      if (dotenv.isInitialized) {
        final value = dotenv.env['PRIVACY_POLICY_URL'];
        if (value != null && value.isNotEmpty) return value;
      }
    } catch (_) {
      // dotenv not loaded (e.g. widget tests); fall back to the default.
    }
    return defaultPrivacyPolicyUrl;
  }
}
