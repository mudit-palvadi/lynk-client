import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  static bool _canRequestAds = false;
  static int _consentGeneration = 0;
  static Future<void>? _initialization;

  static bool get isConsentEligible => _canRequestAds;

  /// Closing eligibility also invalidates ads still loading under an old choice.
  static Future<void> updateConsent(bool eligible) async {
    _canRequestAds = eligible;
    if (eligible) return;
    _consentGeneration++;
    final ads = [_interstitialAd, _rewardedAd, _rewardedInterstitialAd];
    _interstitialAd = null;
    _rewardedAd = null;
    _rewardedInterstitialAd = null;
    _isInterstitialLoading = false;
    _isRewardedLoading = false;
    _isRewardedInterstitialLoading = false;
    for (final ad in ads) {
      try {
        await ad?.dispose();
      } catch (_) {
        /* Already disposed by SDK. */
      }
    }
  }

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

  /// Reads an ad unit id from the environment.
  ///
  /// Returns `null` when the variable is missing or empty, which is how a
  /// release build detects that the ad configuration was not supplied.
  static String? _envAdUnit(String name) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[name];
    if (value == null ||
        !RegExp(r'^ca-app-pub-[0-9]{16}/[0-9]{10}$').hasMatch(value) ||
        value.startsWith('ca-app-pub-3940256099942544')) {
      return null;
    }
    return value;
  }

  /// Whether real (non-test) ad units are configured for this build.
  ///
  /// A release build without ad unit ids shows no ads at all. It must never
  /// fall back to Google's test ad units: this workflow requires live units
  /// for open testing. The release pipeline fails the build
  /// when the ids are missing, so this is the last line of defence.
  static bool get hasRealAdUnits {
    if (!kReleaseMode) return true;
    return _envAdUnit('ADMOB_BANNER_ID') != null &&
        _envAdUnit('ADMOB_INTERSTITIAL_ID') != null &&
        _envAdUnit('ADMOB_REWARDED_ID') != null &&
        _envAdUnit('ADMOB_REWARDED_INTERSTITIAL_ID') != null;
  }

  static String get bannerAdUnitId {
    if (!kReleaseMode) return _testBannerId;
    return _envAdUnit('ADMOB_BANNER_ID') ?? '';
  }

  static String get interstitialAdUnitId {
    if (!kReleaseMode) return _testInterstitialId;
    return _envAdUnit('ADMOB_INTERSTITIAL_ID') ?? '';
  }

  static String get rewardedAdUnitId {
    if (!kReleaseMode) return _testRewardedId;
    return _envAdUnit('ADMOB_REWARDED_ID') ?? '';
  }

  static String get rewardedInterstitialAdUnitId {
    if (!kReleaseMode) return _testRewardedInterstitialId;
    return _envAdUnit('ADMOB_REWARDED_INTERSTITIAL_ID') ?? '';
  }

  static Future<void> init() async {
    if (kIsWeb || !_canRequestAds) return;
    if (!hasRealAdUnits) {
      debugPrint(
        'AdService: no ad units configured, ads are disabled for this build.',
      );
      return;
    }
    try {
      await (_initialization ??= _initializeSdk());
      if (!_canRequestAds) return;
      loadRewardedAd();
      loadRewardedInterstitialAd();
    } catch (e) {
      debugPrint('AdService initialization warning: $e');
    }
  }

  static Future<void> _initializeSdk() async {
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  static Future<bool> shouldShowAds() async {
    if (kIsWeb || !_canRequestAds) return false;
    if (!hasRealAdUnits) return false;
    final prefs = await SharedPreferences.getInstance();
    return _canRequestAds && (prefs.getBool('ads_enabled') ?? true);
  }

  static Future<void> preloadInterstitialAd() async {
    final generation = _consentGeneration;
    if (kIsWeb || !await shouldShowAds() || _interstitialAd != null) return;
    if (!_canRequestAds || generation != _consentGeneration) return;
    if (_isInterstitialLoading) return;

    _isInterstitialLoading = true;
    try {
      await InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (!_canRequestAds || generation != _consentGeneration) {
              ad.dispose();
              return;
            }
            _interstitialAd = ad;
            _isInterstitialLoading = false;
          },
          onAdFailedToLoad: (error) {
            if (generation != _consentGeneration) return;
            _interstitialAd = null;
            _isInterstitialLoading = false;
          },
        ),
      );
    } catch (e) {
      if (generation == _consentGeneration) _isInterstitialLoading = false;
    }
  }

  static Future<void> showInterstitialAd() async {
    if (kIsWeb || !await shouldShowAds()) return;
    if (_interstitialAd == null) await preloadInterstitialAd();

    if (!await shouldShowAds()) return;
    final adToShow = _interstitialAd;
    if (adToShow != null && _canRequestAds) {
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
    final generation = _consentGeneration;
    if (kIsWeb || !await shouldShowAds() || _rewardedAd != null) return;
    if (!_canRequestAds || generation != _consentGeneration) return;
    if (_isRewardedLoading) return;

    _isRewardedLoading = true;
    try {
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (!_canRequestAds || generation != _consentGeneration) {
              ad.dispose();
              return;
            }
            _rewardedAd = ad;
            _isRewardedLoading = false;
          },
          onAdFailedToLoad: (error) {
            if (generation != _consentGeneration) return;
            _rewardedAd = null;
            _isRewardedLoading = false;
          },
        ),
      );
    } catch (e) {
      if (generation == _consentGeneration) _isRewardedLoading = false;
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

    final eligible = await shouldShowAds();
    final adToShow = _rewardedAd;
    if (eligible && _canRequestAds && adToShow != null) {
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
    final generation = _consentGeneration;
    if (kIsWeb || !await shouldShowAds() || _rewardedInterstitialAd != null) {
      return;
    }
    if (!_canRequestAds || generation != _consentGeneration) return;
    if (_isRewardedInterstitialLoading) return;

    _isRewardedInterstitialLoading = true;
    try {
      await RewardedInterstitialAd.load(
        adUnitId: rewardedInterstitialAdUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (!_canRequestAds || generation != _consentGeneration) {
              ad.dispose();
              return;
            }
            _rewardedInterstitialAd = ad;
            _isRewardedInterstitialLoading = false;
          },
          onAdFailedToLoad: (error) {
            if (generation != _consentGeneration) return;
            _rewardedInterstitialAd = null;
            _isRewardedInterstitialLoading = false;
          },
        ),
      );
    } catch (e) {
      if (generation == _consentGeneration) {
        _isRewardedInterstitialLoading = false;
      }
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

    final eligible = await shouldShowAds();
    final adToShow = _rewardedInterstitialAd;
    if (eligible && _canRequestAds && adToShow != null) {
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
