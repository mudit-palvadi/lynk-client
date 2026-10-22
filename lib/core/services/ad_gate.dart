import 'package:shared_preferences/shared_preferences.dart';

/// Decides when an ad may be skipped.
///
/// Two independent rules live here:
///
/// * An automatic ad (the interstitial shown after a send, or the gate on the
///   two transfer buttons) opens a [window] during which automatic ads are not
///   shown again.
/// * The user-initiated unlocks ("Unlock larger files", "Extend session") are
///   never skipped by that window. Watching one of those earns
///   [creditsPerView] free uses of that specific unlock instead, so the user is
///   not asked to watch the same ad again a moment after watching it.
///
/// The state is local and survives a restart, because the user earned it.
class AdGate {
  AdGate({
    DateTime Function()? now,
    this.window = const Duration(minutes: 15),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// How long automatic ads stay off after one has been shown.
  final Duration window;

  /// Free uses granted by watching one unlock ad.
  static const int creditsPerView = 2;

  static const String _freeUntilKey = 'ads_free_until_ms';
  static const String _sizeCreditsKey = 'ads_size_credits';
  static const String _extendCreditsKey = 'ads_extend_credits';

  /// Whether an automatic ad would be skipped right now.
  Future<bool> isFreeWindowOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_freeUntilKey);
    if (until == null) return false;
    return _now().millisecondsSinceEpoch < until;
  }

  /// Starts (or restarts) the ad-free window.
  Future<void> openFreeWindow() async {
    final prefs = await SharedPreferences.getInstance();
    final until = _now().add(window).millisecondsSinceEpoch;
    await prefs.setInt(_freeUntilKey, until);
  }

  /// How many free "Unlock larger files" uses are left.
  Future<int> sizeCredits() => _credits(_sizeCreditsKey);

  /// Spends one free "Unlock larger files" use.
  ///
  /// Returns false when there was nothing to spend, so the caller must show the
  /// ad.
  Future<bool> consumeSizeCredit() => _consume(_sizeCreditsKey);

  /// Grants [creditsPerView] free "Unlock larger files" uses.
  Future<void> grantSizeCredits() => _grant(_sizeCreditsKey);

  /// How many free "Extend session" uses are left.
  Future<int> extendCredits() => _credits(_extendCreditsKey);

  /// Spends one free "Extend session" use.
  Future<bool> consumeExtendCredit() => _consume(_extendCreditsKey);

  /// Grants [creditsPerView] free "Extend session" uses.
  Future<void> grantExtendCredits() => _grant(_extendCreditsKey);

  Future<int> _credits(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? 0;
  }

  Future<bool> _consume(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final credits = prefs.getInt(key) ?? 0;
    if (credits <= 0) return false;
    await prefs.setInt(key, credits - 1);
    return true;
  }

  Future<void> _grant(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, creditsPerView);
  }
}
