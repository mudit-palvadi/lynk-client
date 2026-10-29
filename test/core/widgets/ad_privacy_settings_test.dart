import 'dart:async';

import 'package:client/core/providers/ad_consent_provider.dart';
import 'package:client/core/services/ad_consent_service.dart';
import 'package:client/core/services/ad_service.dart';
import 'package:client/features/home/presentation/pages/home_settings_screen.dart';
import 'package:client/features/home/presentation/providers/home_navigation_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Consent extends AdConsentService {
  int requests = 0;
  final closed = Completer<AdConsentResult>();

  @override
  Future<AdConsentResult> showPrivacyOptions() {
    requests++;
    return closed.future;
  }
}

class _Required extends AdConsentNotifier {
  @override
  AdConsentState build() => const AdConsentState(privacyOptionsRequired: true);
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => AdService.updateConsent(false));

  testWidgets('privacy control is absent when UMP does not require it', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeVersionProvider.overrideWith((ref) async => 'test'),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: HomeSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ad privacy options'), findsNothing);
  });

  testWidgets(
    'required privacy control opens once and stays disabled during the form',
    (tester) async {
      final service = _Consent();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            homeVersionProvider.overrideWith((ref) async => 'test'),
            adConsentProvider.overrideWith(_Required.new),
            adConsentServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: HomeSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.widgetWithText(OutlinedButton, 'Ad privacy options');
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(service.requests, 1);
      expect(tester.widget<OutlinedButton>(control).onPressed, isNull);
      expect(await AdService.shouldShowAds(), isFalse);
      service.closed.complete(
        const AdConsentResult(
          canRequestAds: false,
          privacyOptionsRequired: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(control).onPressed, isNotNull);
      expect(await AdService.shouldShowAds(), isFalse);
    },
  );
}
