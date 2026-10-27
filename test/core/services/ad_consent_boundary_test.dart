import 'package:client/core/services/ad_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() async {
    instanceManager = AdInstanceManager('plugins.flutter.io/google_mobile_ads');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
          calls.add(call);
          return call.method == 'MobileAds#initialize'
              ? <Object?, Object?>{}
              : null;
        });
    calls.clear();
    SharedPreferences.setMockInitialValues({'ads_enabled': true});
    await AdService.updateConsent(false);
  });
  tearDown(() async {
    await AdService.updateConsent(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, null);
  });

  group('ad consent boundary', () {
    test(
      'ads remain unavailable before consent eligibility is established',
      () async {
        SharedPreferences.setMockInitialValues({'ads_enabled': true});
        expect(await AdService.shouldShowAds(), isFalse);
        var granted = false;
        await AdService.showRewardedAd(onRewardGranted: () => granted = true);
        expect(
          granted,
          isTrue,
          reason: 'consent must not block file transfers',
        );
        expect(calls, isEmpty);
      },
    );
    test(
      'non-release ad requests use test units even with live environment IDs',
      () async {
        dotenv.loadFromString(
          envString: 'ADMOB_REWARDED_ID=ca-app-pub-9472143004063972/1768498260',
        );
        await AdService.updateConsent(true);
        await AdService.loadRewardedAd();
        final load = calls.singleWhere(
          (call) => call.method == 'loadRewardedAd',
        );
        expect(
          (load.arguments as Map)['adUnitId'],
          'ca-app-pub-3940256099942544/5224354917',
        );
      },
    );
    test(
      'revoking consent disposes cached ads and never displays them',
      () async {
        await AdService.updateConsent(true);
        await AdService.loadRewardedAd();
        final load = calls.singleWhere(
          (call) => call.method == 'loadRewardedAd',
        );
        final id = (load.arguments as Map)['adId'] as int;
        final ad = instanceManager.adFor(id) as RewardedAd;
        ad.rewardedAdLoadCallback.onAdLoaded(ad);
        await AdService.updateConsent(false);
        var granted = false;
        await AdService.showRewardedAd(onRewardGranted: () => granted = true);
        expect(granted, isTrue);
        expect(calls.where((call) => call.method == 'disposeAd'), hasLength(1));
        expect(
          calls.where((call) => call.method == 'showAdWithoutView'),
          isEmpty,
        );
      },
    );
    test(
      'an old load cannot authorize an ad after revoke and reallow',
      () async {
        await AdService.updateConsent(true);
        await AdService.loadRewardedAd();
        final load = calls.singleWhere(
          (call) => call.method == 'loadRewardedAd',
        );
        final id = (load.arguments as Map)['adId'] as int;
        final oldAd = instanceManager.adFor(id) as RewardedAd;
        await AdService.updateConsent(false);
        await AdService.updateConsent(true);
        oldAd.rewardedAdLoadCallback.onAdLoaded(oldAd);
        await pumpEventQueue();
        expect(instanceManager.adFor(id), isNull);
        var granted = false;
        await AdService.showRewardedAd(onRewardGranted: () => granted = true);
        expect(granted, isTrue);
        expect(
          calls.where((call) => call.method == 'showAdWithoutView'),
          isEmpty,
        );
        expect(
          calls.where((call) => call.method == 'loadRewardedAd'),
          hasLength(2),
        );
      },
    );
  });
}
