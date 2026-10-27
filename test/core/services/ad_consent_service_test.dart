import 'dart:async';

import 'package:client/core/services/ad_consent_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ump/user_messaging_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel(
    'plugins.flutter.io/google_mobile_ads/ump',
    StandardMethodCodec(UserMessagingCodec()),
  );
  final calls = <String>[];
  bool eligible = false;
  int privacyRequired = 0;
  String? failingMethod;
  Completer<void>? form;

  setUp(() {
    calls.clear();
    eligible = false;
    privacyRequired = 0;
    failingMethod = null;
    form = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == failingMethod) {
            throw PlatformException(
              code: '1',
              message: 'Fixture native failure',
            );
          }
          if (call.method == 'ConsentInformation#canRequestAds') {
            return eligible;
          }
          if (call.method ==
              'ConsentInformation#getPrivacyOptionsRequirementStatus') {
            return privacyRequired;
          }
          if (call.method ==
              'UserMessagingPlatform#loadAndShowConsentFormIfRequired') {
            await form?.future;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'refresh requests current consent before a form and eligibility',
    () async {
      eligible = true;
      privacyRequired = 1;
      final result = await AdConsentService().refresh();
      expect(result.canRequestAds, isTrue);
      expect(result.privacyOptionsRequired, isTrue);
      expect(calls, [
        'ConsentInformation#requestConsentInfoUpdate',
        'UserMessagingPlatform#loadAndShowConsentFormIfRequired',
        'ConsentInformation#canRequestAds',
        'ConsentInformation#getPrivacyOptionsRequirementStatus',
      ]);
    },
  );
  test('eligibility is not read while the consent form is open', () async {
    form = Completer<void>();
    final pending = AdConsentService().refresh();
    await pumpEventQueue();
    expect(calls, isNot(contains('ConsentInformation#canRequestAds')));
    form!.complete();
    expect((await pending).canRequestAds, isFalse);
  });
  for (final previousConsent in [false, true]) {
    test('a failed refresh uses UMP eligibility ($previousConsent)', () async {
      eligible = previousConsent;
      failingMethod = 'ConsentInformation#requestConsentInfoUpdate';
      final result = await AdConsentService().refresh();
      expect(result.canRequestAds, previousConsent);
      expect(
        calls,
        isNot(
          contains('UserMessagingPlatform#loadAndShowConsentFormIfRequired'),
        ),
      );
    });
  }
  test('a form failure is not permission to request ads', () async {
    failingMethod = 'UserMessagingPlatform#loadAndShowConsentFormIfRequired';
    expect((await AdConsentService().refresh()).canRequestAds, isFalse);
  });
  test('an eligibility failure denies ads', () async {
    failingMethod = 'ConsentInformation#canRequestAds';
    expect((await AdConsentService().refresh()).canRequestAds, isFalse);
  });
  test('privacy choices are followed by a fresh eligibility check', () async {
    privacyRequired = 1;
    final result = await AdConsentService().showPrivacyOptions();
    expect(result.canRequestAds, isFalse);
    expect(result.privacyOptionsRequired, isTrue);
    expect(calls.first, 'UserMessagingPlatform#showPrivacyOptionsForm');
    expect(calls, contains('ConsentInformation#canRequestAds'));
  });
  test(
    'missing platform support fails closed without an uncaught SDK error',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect((await AdConsentService().refresh()).canRequestAds, isFalse);
    },
  );
}
