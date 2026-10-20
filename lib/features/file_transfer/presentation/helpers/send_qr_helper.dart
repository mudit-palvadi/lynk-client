import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/transfer_providers.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_links.dart';
import '../providers/upload_notifier.dart';

class SendQrHelper {
  /// Generates the QR data string with embedded transferId and AES key fragment.
  static String buildQrData({
    required WidgetRef ref,
    required String transferId,
    required String aesKey,
  }) {
    final key = aesKey.isNotEmpty
        ? aesKey
        : (ref.read(uploadProvider).aesKey ?? '');
    final accessToken = ref.read(uploadProvider).transfer?.accessToken ?? '';
    final capability = accessToken.isEmpty ? '' : '&a=$accessToken';
    return '${AppLinks.deepLinkBase}/send/$transferId#$key$capability';
  }

  /// Calculates the exact remaining seconds for an active transfer session (default 600s).
  static int calculateRemainingSeconds(
    DateTime? createdAt, {
    int totalLifetimeSeconds = 600,
  }) {
    if (createdAt == null) return totalLifetimeSeconds;
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    final remaining = totalLifetimeSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Formats seconds into MM:SS format.
  static String formatRemainingTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Extends the session time to 30 minutes (1800s) after watching a Rewarded Ad.
  static Future<void> extendSessionTimeWithAd({
    required BuildContext context,
    required ValueNotifier<int> secondsNotifier,
  }) async {
    await AdService.showRewardedAd(
      onRewardGranted: () {
        secondsNotifier.value = 1800;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session extended to 30 minutes!'),
              backgroundColor: AppTheme.secondary,
            ),
          );
        }
      },
    );
  }

  /// Cancels transfer session and navigates home.
  static void cancelSessionAndGoHome({
    required BuildContext context,
    required WidgetRef ref,
    required String transferId,
  }) {
    final secret = ref.read(uploadProvider).transfer?.senderSecret;
    ref.read(transferRepositoryProvider).cancelTransfer(
      transferId,
      senderSecret: secret,
    );
    ref.read(uploadProvider.notifier).reset();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transfer session cancelled.'),
        duration: Duration(seconds: 2),
      ),
    );
    context.go('/home');
  }
}
