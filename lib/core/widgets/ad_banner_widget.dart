import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../providers/ad_consent_provider.dart';
import '../services/ad_gate.dart';
import '../services/ad_service.dart';

final adBannerProvider = FutureProvider.autoDispose<BannerAd?>((ref) async {
  if (!ref.watch(adConsentProvider).canRequestAds) return null;
  if (!await AdService.shouldShowAds() || await AdGate().isFreeWindowOpen()) {
    return null;
  }
  if (!ref.mounted || !AdService.isConsentEligible) return null;

  final loaded = Completer<BannerAd?>();
  bool disposed = false;
  late final BannerAd banner;
  ref.onDispose(() {
    disposed = true;
    banner.dispose();
    if (!loaded.isCompleted) loaded.complete(null);
  });
  banner = BannerAd(
    adUnitId: AdService.bannerAdUnitId,
    request: const AdRequest(),
    size: AdSize.banner,
    listener: BannerAdListener(
      onAdLoaded: (_) {
        if (!disposed && !loaded.isCompleted) loaded.complete(banner);
      },
      onAdFailedToLoad: (_, _) {
        if (!disposed) banner.dispose();
        if (!loaded.isCompleted) loaded.complete(null);
      },
    ),
  );
  try {
    await banner.load();
  } catch (_) {
    if (!disposed) banner.dispose();
    if (!loaded.isCompleted) loaded.complete(null);
  }
  return loaded.future;
});

class AdBannerWidget extends ConsumerWidget {
  const AdBannerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(adBannerProvider).asData?.value;
    if (banner == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: banner.size.width.toDouble(),
      height: banner.size.height.toDouble(),
      child: AdWidget(ad: banner),
    );
  }
}
