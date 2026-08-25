import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _fallbackApiBase = 'http://140.245.220.117:8000/api/v1/';

  /// REST base URL from env, always ending with a trailing slash.
  /// Falls back to the production default when .env is unavailable.
  static String get apiBase {
    String url;
    try {
      url = dotenv.env['API_BASE_URL'] ?? _fallbackApiBase;
    } catch (_) {
      url = _fallbackApiBase; // DotEnv not initialized (e.g. unit tests)
    }
    return url.endsWith('/') ? url : '$url/';
  }

  /// WebSocket signaling URI for a session, derived from the API base.
  static Uri signalingUri(String sessionId) {
    final parsed = Uri.parse(apiBase);
    final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: parsed.host,
      port: parsed.port,
      path: '/ws/signaling/$sessionId',
    );
  }

  /// Verifies generic system configuration key loaded from environment
  static Future<bool> applyConfigurationKey(String inputKey) async {
    final secret = dotenv.env['DEV_CONFIG_KEY'];
    if (secret != null && secret.isNotEmpty && inputKey == secret) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ads_enabled', false);
      return true;
    }
    return false;
  }
}
