import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsentResult {
  const AdConsentResult({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
  });

  final bool canRequestAds;
  final bool privacyOptionsRequired;
}

/// UMP owns the consent decision. A form error is not permission to request ads.
class AdConsentService {
  Future<AdConsentResult> refresh() async {
    try {
      final updated = Completer<FormError?>();
      // UMP's callback API returns void, including when its platform channel
      // fails asynchronously. Keep that failure inside this eligibility check.
      runZonedGuarded(
        () => ConsentInformation.instance.requestConsentInfoUpdate(
          ConsentRequestParameters(),
          () {
            if (!updated.isCompleted) updated.complete(null);
          },
          (error) {
            if (!updated.isCompleted) updated.complete(error);
          },
        ),
        (_, _) {
          if (!updated.isCompleted) {
            updated.complete(
              FormError(
                errorCode: -1,
                message: 'Consent information unavailable.',
              ),
            );
          }
        },
      );
      final error = await updated.future.timeout(const Duration(seconds: 15));
      if (error != null) throw error;
      await _form(ConsentForm.loadAndShowConsentFormIfRequired);
    } catch (_) {
      // UMP may still permit requests based on a previously valid decision.
    }
    return _eligibility();
  }

  Future<AdConsentResult> showPrivacyOptions() async {
    try {
      await _form(ConsentForm.showPrivacyOptionsForm);
    } catch (_) {
      // Re-read UMP even when a form fails or is dismissed.
    }
    return _eligibility();
  }

  Future<void> _form(
    Future<void> Function(void Function(FormError?)) show,
  ) async {
    final dismissed = Completer<FormError?>();
    await show((error) {
      if (!dismissed.isCompleted) dismissed.complete(error);
    });
    final error = await dismissed.future;
    if (error != null) throw error;
  }

  Future<AdConsentResult> _eligibility() async {
    bool eligible = false;
    bool privacyRequired = false;
    try {
      eligible = await ConsentInformation.instance.canRequestAds().timeout(
        const Duration(seconds: 15),
      );
      privacyRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus()
              .timeout(const Duration(seconds: 15)) ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      // Keep the last eligibility result, never infer approval from an error.
    }
    return AdConsentResult(
      canRequestAds: eligible,
      privacyOptionsRequired: privacyRequired,
    );
  }
}
