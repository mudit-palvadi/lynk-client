import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  static InterstitialAd? _interstitialAd;
  static RewardedAd? _rewardedAd;
  static RewardedInterstitialAd? _rewardedInterstitialAd;

  static bool _isInterstitialLoading = false;
  static bool _isRewardedLoading = false;
  static bool _isRewardedInterstitialLoading = false;

  /// Default Google Test Ad Unit IDs
  static const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewardedId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedInterstitialId =
      'ca-app-pub-3940256099942544/5354046379';

  static String get bannerAdUnitId {
    if (kDebugMode) return _testBannerId;
    return dotenv.env['ADMOB_BANNER_ID'] ?? _testBannerId;
  }

  static String get interstitialAdUnitId {
    if (kDebugMode) return _testInterstitialId;
    return dotenv.env['ADMOB_INTERSTITIAL_ID'] ?? _testInterstitialId;
  }

  static String get rewardedAdUnitId {
    if (kDebugMode) return _testRewardedId;
    return dotenv.env['ADMOB_REWARDED_ID'] ?? _testRewardedId;
  }

  static String get rewardedInterstitialAdUnitId {
    if (kDebugMode) return _testRewardedInterstitialId;
    return dotenv.env['ADMOB_REWARDED_INTERSTITIAL_ID'] ??
        _testRewardedInterstitialId;
  }

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await MobileAds.instance.initialize();
      preloadInterstitialAd();
      loadRewardedAd();
      loadRewardedInterstitialAd();
    } catch (e) {
      debugPrint('AdService initialization warning: $e');
    }
  }

  static Future<bool> shouldShowAds() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('ads_enabled') ?? true;
  }

  static Future<void> preloadInterstitialAd() async {
    if (kIsWeb || !await shouldShowAds() || _interstitialAd != null) return;
    if (_isInterstitialLoading) return;

    _isInterstitialLoading = true;
    try {
      await InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _isInterstitialLoading = false;
          },
          onAdFailedToLoad: (error) {
            _interstitialAd = null;
            _isInterstitialLoading = false;
          },
        ),
      );
    } catch (e) {
      _isInterstitialLoading = false;
    }
  }

  static Future<void> showInterstitialAd() async {
    if (kIsWeb || !await shouldShowAds()) return;
    if (_interstitialAd == null) await preloadInterstitialAd();

    if (_interstitialAd != null) {
      final adToShow = _interstitialAd!;
      _interstitialAd = null;
      adToShow.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          preloadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          preloadInterstitialAd();
        },
      );
      await adToShow.show();
    }
  }

  /// Loads a Rewarded Video Ad.
  static Future<void> loadRewardedAd() async {
    if (kIsWeb || !await shouldShowAds() || _rewardedAd != null) return;
    if (_isRewardedLoading) return;

    _isRewardedLoading = true;
    try {
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _isRewardedLoading = false;
          },
          onAdFailedToLoad: (error) {
            _rewardedAd = null;
            _isRewardedLoading = false;
          },
        ),
      );
    } catch (e) {
      _isRewardedLoading = false;
    }
  }

  /// Shows a Rewarded Video Ad and triggers onRewardGranted callback if user completes viewing.
  static Future<bool> showRewardedAd({
    required Function() onRewardGranted,
  }) async {
    if (kIsWeb) {
      onRewardGranted();
      return true;
    }

    if (!await shouldShowAds()) {
      onRewardGranted();
      return true;
    }

    if (_rewardedAd == null) {
      await loadRewardedAd();
    }

    if (_rewardedAd != null) {
      final adToShow = _rewardedAd!;
      _rewardedAd = null;
      bool userRewarded = false;

      adToShow.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadRewardedAd();
          if (userRewarded) onRewardGranted();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          loadRewardedAd();
          onRewardGranted();
        },
      );

      await adToShow.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          userRewarded = true;
        },
      );
      return true;
    } else {
      onRewardGranted();
      return false;
    }
  }

  /// Loads a Rewarded Interstitial Ad.
  static Future<void> loadRewardedInterstitialAd() async {
    if (kIsWeb || !await shouldShowAds() || _rewardedInterstitialAd != null) {
      return;
    }
    if (_isRewardedInterstitialLoading) return;

    _isRewardedInterstitialLoading = true;
    try {
      await RewardedInterstitialAd.load(
        adUnitId: rewardedInterstitialAdUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInterstitialAd = ad;
            _isRewardedInterstitialLoading = false;
          },
          onAdFailedToLoad: (error) {
            _rewardedInterstitialAd = null;
            _isRewardedInterstitialLoading = false;
          },
        ),
      );
    } catch (e) {
      _isRewardedInterstitialLoading = false;
    }
  }

  /// Shows a Rewarded Interstitial Ad for high-value actions (e.g. P2P Direct Transfer).
  static Future<bool> showRewardedInterstitialAd({
    required Function() onRewardGranted,
  }) async {
    if (kIsWeb) {
      onRewardGranted();
      return true;
    }

    if (!await shouldShowAds()) {
      onRewardGranted();
      return true;
    }

    if (_rewardedInterstitialAd == null) {
      await loadRewardedInterstitialAd();
    }

    if (_rewardedInterstitialAd != null) {
      final adToShow = _rewardedInterstitialAd!;
      _rewardedInterstitialAd = null;
      bool userRewarded = false;

      adToShow.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadRewardedInterstitialAd();
          if (userRewarded) onRewardGranted();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          loadRewardedInterstitialAd();
          onRewardGranted();
        },
      );

      await adToShow.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          userRewarded = true;
        },
      );
      return true;
    } else {
      onRewardGranted();
      return false;
    }
  }
}
