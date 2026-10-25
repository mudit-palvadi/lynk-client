import 'dart:async';

import 'ad_gate.dart';
import 'ad_service.dart';
import 'transfer_ad_gate.dart';

/// Turns one rewarded view into two unlocks.
///
/// The first use spends a credit, the second one does not need an ad either,
/// and the third asks for a view again. Credits are kept per purpose, so the
/// larger-file unlock never eats the session-extension unlock.
///
/// While the ad-free window is open an unlock is free and spends no credit.
/// Watching an unlock ad opens that same window, so an extension is not
/// followed by a second ad on the transfer button.
class UnlockCredits {
  UnlockCredits({
    AdGate? gate,
    AutomaticAdShower? showRewardedAd,
  })  : _gate = gate ?? AdGate(),
        _showRewardedAd = showRewardedAd ?? AdService.showRewardedAd;

  final AdGate _gate;
  final AutomaticAdShower _showRewardedAd;

  /// Runs [onUnlocked] now when a size credit is left, otherwise after the ad.
  ///
  /// Returns true when an ad was shown.
  Future<bool> spendSize(void Function() onUnlocked) => _spend(
        _gate.consumeSizeCredit,
        _gate.grantSizeCredits,
        onUnlocked,
      );

  /// Runs [onUnlocked] now when an extension credit is left, otherwise after
  /// the ad. Returns true when an ad was shown.
  Future<bool> spendExtend(void Function() onUnlocked) => _spend(
        _gate.consumeExtendCredit,
        _gate.grantExtendCredits,
        onUnlocked,
      );

  Future<bool> _spend(
    Future<bool> Function() consume,
    Future<void> Function() grant,
    void Function() onUnlocked,
  ) async {
    // The window covers unlocks too: a user who already watched an ad does not
    // spend a credit (or watch another ad) just because this unlock is next.
    if (await _gate.isFreeWindowOpen()) {
      onUnlocked();
      return false;
    }

    if (await consume()) {
      onUnlocked();
      return false;
    }

    await _showRewardedAd(
      onRewardGranted: () {
        // The view buys two uses: this one spends one of them straight away.
        grant();
        consume();
        unawaited(_gate.openFreeWindow());
        onUnlocked();
      },
    );
    return true;
  }
}
