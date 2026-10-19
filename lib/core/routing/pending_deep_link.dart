/// Carries a deep link across the router rebuild that happens when onboarding
/// completes.
///
/// The onboarding gate redirects every non-onboarding location back to
/// `/onboarding`, so a QR link that opens the app for the first time — or that
/// arrives while the onboarding pages are on screen — would otherwise be
/// silently dropped when the gate lifts.
///
/// This is intentionally *not* persisted and *not* placed in a URL: the link
/// carries the transfer key in its `#fragment` (Memory.md Rule 4), so it must
/// never reach disk, browser history, or a server. It lives in memory for the
/// few seconds between the redirect and the post-onboarding rebuild.
///
/// Deliberately a plain static rather than a provider: the top-level redirect
/// runs while go_router is parsing, which happens during a widget build, and
/// Riverpod forbids mutating a provider at that point.
class PendingDeepLink {
  PendingDeepLink._();

  static String? _location;

  /// Records the location that should be replayed once onboarding is done.
  static void remember(String location) => _location = location;

  /// Returns the recorded location and clears it, so it is replayed once.
  static String? take() {
    final location = _location;
    _location = null;
    return location;
  }

  /// Drops any recorded location. Used by tests to isolate cases.
  static void clear() => _location = null;
}
