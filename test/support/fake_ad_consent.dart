import 'package:client/core/services/ad_consent_service.dart';

/// Keeps routing and layout tests independent of the native UMP dialog.
class FakeAdConsent extends AdConsentService {
  @override
  Future<AdConsentResult> refresh() async => const AdConsentResult(
    canRequestAds: false,
    privacyOptionsRequired: false,
  );
}
