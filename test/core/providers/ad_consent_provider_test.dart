import 'dart:async';

import 'package:client/core/providers/ad_consent_provider.dart';
import 'package:client/core/services/ad_consent_service.dart';
import 'package:client/core/services/ad_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Consent extends AdConsentService {
  int refreshes = 0;
  int privacyForms = 0;
  Completer<AdConsentResult>? pending;
  AdConsentResult result = const AdConsentResult(
    canRequestAds: false,
    privacyOptionsRequired: true,
  );
  bool fail = false;

  @override
  Future<AdConsentResult> refresh() async {
    refreshes++;
    if (fail) throw StateError('Fixture failure');
    return pending?.future ?? result;
  }

  @override
  Future<AdConsentResult> showPrivacyOptions() async {
    privacyForms++;
    return pending?.future ?? result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'ads_enabled': true});
    await AdService.updateConsent(false);
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await AdService.updateConsent(false);
  });

  ProviderContainer container(_Consent service) {
    final result = ProviderContainer(
      overrides: [adConsentServiceProvider.overrideWithValue(service)],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('initial state denies ads', () {
    expect(
      container(_Consent()).read(adConsentProvider).canRequestAds,
      isFalse,
    );
  });
  test(
    'native eligibility initializes the SDK once and enables ad requests',
    () async {
      instanceManager = AdInstanceManager(
        'plugins.flutter.io/google_mobile_ads',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(instanceManager.channel, (call) async {
            calls.add(call);
            return call.method == 'MobileAds#initialize'
                ? InitializationStatus({})
                : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(instanceManager.channel, null),
      );
      final service = _Consent()
        ..result = const AdConsentResult(
          canRequestAds: true,
          privacyOptionsRequired: true,
        );
      final c = container(service);
      final notifier = c.read(adConsentProvider.notifier);
      await Future.wait([notifier.start(), notifier.start()]);
      await pumpEventQueue();
      expect(service.refreshes, 1);
      expect(c.read(adConsentProvider).canRequestAds, isTrue);
      expect(await AdService.shouldShowAds(), isTrue);
      expect(
        calls.where((call) => call.method == 'MobileAds#initialize'),
        hasLength(1),
      );
      expect(
        calls.where((call) => call.method == 'loadRewardedAd'),
        hasLength(1),
      );
    },
  );
  test('concurrent startup requests show only one consent flow', () async {
    final service = _Consent()..pending = Completer<AdConsentResult>();
    final c = container(service);
    final notifier = c.read(adConsentProvider.notifier);
    final pending = notifier.start();
    await pumpEventQueue();
    await notifier.start();
    expect(service.refreshes, 1);
    expect(c.read(adConsentProvider).busy, isTrue);
    expect(await AdService.shouldShowAds(), isFalse);
    service.pending!.complete(service.result);
    await pending;
    await notifier.start();
    expect(service.refreshes, 1);
    expect(c.read(adConsentProvider).privacyOptionsRequired, isTrue);
  });
  test(
    'withdrawing eligibility disables ads while privacy options are open',
    () async {
      final service = _Consent();
      final c = container(service);
      final notifier = c.read(adConsentProvider.notifier);
      await notifier.start();
      await AdService.updateConsent(true);
      expect(await AdService.shouldShowAds(), isTrue);
      service.pending = Completer<AdConsentResult>();
      final pending = notifier.showPrivacyOptions();
      await pumpEventQueue();
      expect(await AdService.shouldShowAds(), isFalse);
      expect(c.read(adConsentProvider).busy, isTrue);
      await notifier.showPrivacyOptions();
      expect(service.privacyForms, 1);
      service.pending!.complete(service.result);
      await pending;
      expect(await AdService.shouldShowAds(), isFalse);
    },
  );
  test('a service error never authorizes ads', () async {
    final service = _Consent()..fail = true;
    final c = container(service);
    await c.read(adConsentProvider.notifier).start();
    expect(c.read(adConsentProvider).busy, isFalse);
    expect(await AdService.shouldShowAds(), isFalse);
  });
  test('non-Android platforms do not request Android consent', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = _Consent();
    await container(service).read(adConsentProvider.notifier).start();
    expect(service.refreshes, 0);
  });
  test('a disposed startup ignores late consent completion', () async {
    final service = _Consent()..pending = Completer<AdConsentResult>();
    final c = ProviderContainer(
      overrides: [adConsentServiceProvider.overrideWithValue(service)],
    );
    final pending = c.read(adConsentProvider.notifier).start();
    await pumpEventQueue();
    c.dispose();
    service.pending!.complete(
      const AdConsentResult(canRequestAds: true, privacyOptionsRequired: true),
    );
    await pending;
    expect(await AdService.shouldShowAds(), isFalse);
  });
}
