import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Native operations only; the required-update policy lives in the notifier.
class PlayUpdateService {
  Future<AppUpdateInfo>? _pendingCheck;

  Future<int> installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    final version = int.tryParse(info.buildNumber);
    if (version == null || version <= 0) {
      throw StateError('Installed version is unavailable');
    }
    return version;
  }

  Future<AppUpdateInfo> check() => _pendingCheck ??= _check();

  Future<AppUpdateInfo> _check() async {
    try {
      return await InAppUpdate.checkForUpdate();
    } finally {
      _pendingCheck = null;
    }
  }

  Future<AppUpdateResult> updateImmediately() =>
      InAppUpdate.performImmediateUpdate();

  Future<bool> openStore() async {
    for (final uri in [
      Uri.parse('market://details?id=app.xynix.lynk'),
      Uri.parse('https://play.google.com/store/apps/details?id=app.xynix.lynk'),
    ]) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Some devices do not have a market handler; try the HTTPS listing.
      }
    }
    return false;
  }
}
