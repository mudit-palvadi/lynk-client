import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const String _fallbackApiBase = 'https://api.lynkshare.app/api/v1/';

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

  /// Applies the debug-only "disable ads" bypass.
  ///
  /// The key is a compile-time define, so a release binary never carries it:
  /// the release pipeline does not pass
  /// `--dart-define=LYNK_DEBUG_BYPASS_KEY=...`, and the `kDebugMode` guard
  /// compiles the whole path out of a release build anyway.
  ///
  /// It used to be read from `DEV_CONFIG_KEY` in `.env`, which meant every
  /// distributed APK carried a working bypass. A client-side key shipped to
  /// every user is not a secret - it is a revenue bypass anyone can pull out
  /// of the APK with `unzip`.
  ///
  /// To use it locally: run with
  /// `flutter run --dart-define=LYNK_DEBUG_BYPASS_KEY=<key>`, then tap the
  /// version label seven times on the home screen and enter the same key.
  static Future<bool> applyConfigurationKey(String inputKey) async {
    if (!kDebugMode) {
      return false;
    }

    const debugBypassKey = String.fromEnvironment('LYNK_DEBUG_BYPASS_KEY');
    if (debugBypassKey.isEmpty || inputKey != debugBypassKey) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ads_enabled', false);
    return true;
  }
}
