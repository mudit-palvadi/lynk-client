import 'package:client/core/services/ad_gate.dart';
import 'package:client/core/services/ad_service.dart';

/// Shows an automatic ad and tells us when the reward was granted.
typedef AutomaticAdShower =
    Future<bool> Function({required void Function() onRewardGranted});

/// Decides whether a transfer button needs an ad.
///
/// While the free window is open the action runs straight away; otherwise the
/// matching ad is shown and the action waits for the reward. Reading the
/// window is all that happens here - the post-send ad is what opens it.
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
           (({required void Function() onRewardGranted}) => AdService
               .showRewardedInterstitialAd(onRewardGranted: onRewardGranted));

  final AdGate _gate;
  final AutomaticAdShower _showCloudAd;
  final AutomaticAdShower _showP2pAd;

  /// Runs [onAllowed] now when the free window is open, otherwise after the
  /// cloud (rewarded video) or P2P (rewarded interstitial) ad.
  Future<void> start({
    required bool p2p,
    required void Function() onAllowed,
  }) async {
    if (await _gate.isFreeWindowOpen()) {
      onAllowed();
      return;
    }
    final show = p2p ? _showP2pAd : _showCloudAd;
    await show(onRewardGranted: onAllowed);
  }
}
