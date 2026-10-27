import 'dart:async';

import 'package:client/core/services/ad_gate.dart';
import 'package:client/core/services/ad_service.dart';

/// Shows an automatic ad and tells us when the reward was granted.
typedef AutomaticAdShower =
    Future<bool> Function({required void Function() onRewardGranted});

/// Decides whether a transfer button needs an ad.
///
/// While the free window is open the action runs straight away. A fresh
/// install's first transfer is also free and opens that window; after that the
/// matching ad is shown and the action waits for the reward. A rewarded view
/// opens the window, so the next transfer inside it is free. A selection that
/// already paid the size unlock does not pay the transfer gate again. An early
/// dismiss neither starts the transfer nor opens the window; an SDK failure
/// does both, because a broken ad must not block a send.
class TransferAdGate {
  TransferAdGate({
    AdGate? gate,
    AutomaticAdShower? showCloudAd,
    AutomaticAdShower? showP2pAd,
  }) : _gate = gate ?? AdGate(),
       _showCloudAd =
           showCloudAd ??
           (({required void Function() onRewardGranted}) =>
               AdService.showRewardedAd(onRewardGranted: onRewardGranted)),
       _showP2pAd =
           showP2pAd ??
           (({required void Function() onRewardGranted}) =>
               AdService.showRewardedInterstitialAd(
                 onRewardGranted: onRewardGranted,
               ));

  final AdGate _gate;
  final AutomaticAdShower _showCloudAd;
  final AutomaticAdShower _showP2pAd;

  /// Runs [onAllowed] now when the free window is open, otherwise after the
  /// cloud (rewarded video) or P2P (rewarded interstitial) ad.
  Future<void> start({
    required bool p2p,
    bool sizeUnlockAlreadyPaid = false,
    required void Function() onAllowed,
  }) async {
    if (await _gate.isFreeWindowOpen()) {
      onAllowed();
      return;
    }
    // A selection that already paid the size unlock must not pay again here.
    // This is a credit-paid unlock (an ad-paid one already opened the window
    // above), so it does not grant the 15 minutes itself.
    if (sizeUnlockAlreadyPaid) {
      onAllowed();
      return;
    }
    if (await _gate.consumeFirstTransfer()) {
      onAllowed();
      unawaited(_gate.openFreeWindow());
      return;
    }

    var allowed = false;
    void allow() {
      if (allowed) return;
      allowed = true;
      onAllowed();
    }

    final show = p2p ? _showP2pAd : _showCloudAd;
    try {
      await show(
        onRewardGranted: () {
          allow();
          unawaited(_gate.openFreeWindow());
        },
      );
    } catch (_) {
      // A missing or broken ad must not stop the transfer, and the next send
      // must not be asked to pay for the same failure.
      allow();
      await _gate.openFreeWindow();
    }
  }
}
