import 'package:client/core/widgets/ad_banner_widget.dart';
import 'package:client/core/providers/ad_consent_provider.dart';
import 'package:client/core/services/ad_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
          return null;
        });
    calls.clear();
    await AdService.updateConsent(true);
  });
  tearDown(() async {
    await AdService.updateConsent(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, null);
  });
  testWidgets('hides while the ad-free window is open', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ads_free_until_ms': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [adConsentProvider.overrideWith(_Allowed.new)],
        child: const MaterialApp(home: Scaffold(body: AdBannerWidget())),
      ),
    );
    await tester.pump();

    expect(find.byType(AdWidget), findsNothing);
    expect(calls.where((call) => call.method == 'loadBannerAd'), isEmpty);
  });
  testWidgets('consent revocation disposes a banner still loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'ads_enabled': true});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adConsentProvider.overrideWith(_Allowed.new)],
        child: const MaterialApp(home: Scaffold(body: AdBannerWidget())),
      ),
    );
    await tester.pumpAndSettle();
    final load = calls.singleWhere((call) => call.method == 'loadBannerAd');
    final id = (load.arguments as Map)['adId'] as int;
    final banner = instanceManager.adFor(id) as BannerAd;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdBannerWidget)),
    );
    await AdService.updateConsent(false);
    (container.read(adConsentProvider.notifier) as _Allowed).deny();
    await tester.pumpAndSettle();
    banner.listener.onAdLoaded!(banner);
    await tester.pumpAndSettle();
    expect(find.byType(AdWidget), findsNothing);
    expect(instanceManager.adFor(id), isNull);
    expect(calls.where((call) => call.method == 'disposeAd'), hasLength(1));
  });
}

class _Allowed extends AdConsentNotifier {
  @override
  AdConsentState build() => const AdConsentState(canRequestAds: true);

  void deny() => state = const AdConsentState();
}
