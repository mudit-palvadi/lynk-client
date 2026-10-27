import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ad_consent_service.dart';
import '../services/ad_service.dart';

final adConsentServiceProvider = Provider<AdConsentService>(
  (ref) => AdConsentService(),
);

class AdConsentState {
  const AdConsentState({
    this.canRequestAds = false,
    this.privacyOptionsRequired = false,
    this.busy = false,
  });

  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final bool busy;
}

final adConsentProvider = NotifierProvider<AdConsentNotifier, AdConsentState>(
  AdConsentNotifier.new,
);

class AdConsentNotifier extends Notifier<AdConsentState> {
  bool _started = false;

  @override
  AdConsentState build() => const AdConsentState();

  /// Called after the admitted app has a mounted activity, once per launch.
  Future<void> start() async {
    if (_started ||
        state.busy ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _started = true;
    await _update(privacy: false);
  }

  Future<void> showPrivacyOptions() async {
    if (state.busy || !state.privacyOptionsRequired) return;
    await _update(privacy: true);
  }

  Future<void> _update({required bool privacy}) async {
    state = AdConsentState(
      privacyOptionsRequired: state.privacyOptionsRequired,
      busy: true,
    );
    await AdService.updateConsent(false);
    if (!ref.mounted) return;
    final privacyRequired = state.privacyOptionsRequired;
    AdConsentResult result;
    try {
      final service = ref.read(adConsentServiceProvider);
      result = await (privacy
          ? service.showPrivacyOptions()
          : service.refresh());
    } catch (_) {
      result = AdConsentResult(
        canRequestAds: false,
        privacyOptionsRequired: privacyRequired,
      );
    }
    if (!ref.mounted) return;
    await AdService.updateConsent(result.canRequestAds);
    if (!ref.mounted) return;
    state = AdConsentState(
      canRequestAds: result.canRequestAds,
      privacyOptionsRequired: result.privacyOptionsRequired,
    );
    if (result.canRequestAds) await AdService.init();
  }
}
