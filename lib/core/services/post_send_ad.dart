import 'ad_gate.dart';
import 'ad_service.dart';

/// The interstitial shown once a send finishes.
///
/// Watching it opens the free window, so the next automatic ad waits at least
/// fifteen minutes. While the window is already open nothing is shown.
class PostSendAd {
  PostSendAd({
    AdGate? gate,
    Future<void> Function()? showInterstitial,
  })  : _gate = gate ?? AdGate(),
        _showInterstitial = showInterstitial ?? AdService.showInterstitialAd;

  final AdGate _gate;
  final Future<void> Function() _showInterstitial;

  /// Shows the interstitial and opens the window when it was closed.
  ///
  /// Returns true when the ad was shown, false when the window was already
  /// open and the send finished quietly.
  Future<bool> run() async {
    if (await _gate.isFreeWindowOpen()) return false;
    await _showInterstitial();
    await _gate.openFreeWindow();
    return true;
  }
}
