import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/file_size_formatter.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import '../providers/upload_notifier.dart';
import '../providers/upload_state.dart';

class FileUploadScreen extends ConsumerWidget {
  final String? attachToSessionId;

  /// Receiver's ephemeral public key (base64url) when pairing via a
  /// receiver-session QR. Used to wrap the AES key client-side.
  final String? receiverPk;

  const FileUploadScreen({super.key, this.attachToSessionId, this.receiverPk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadState = ref.watch(uploadProvider);
    final notifier = ref.read(uploadProvider.notifier);

    ref.listen<UploadState>(uploadProvider, (previous, next) {
      if (next.phase == UploadPhase.completed && next.transfer != null) {
        final key = next.aesKey ?? '';
        if (attachToSessionId != null && attachToSessionId!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transfer sent to receiver successfully!'),
              backgroundColor: AppTheme.secondary,
            ),
          );
          context.go('/home');
        } else {
          context.go('/send-qr?aesKey=$key', extra: next.transfer!);
        }
      } else if (next.phase == UploadPhase.failed &&
          next.errorMessage != null) {
        final msg = next.errorMessage!;
        if (msg.contains('Watch an ad to unlock')) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.cardBg,
              title: const Text('Unlock Larger Transfers'),
              content: Text('$msg This applies for this session.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    AdService.showRewardedAd(
                      onRewardGranted: () {
                        notifier.unlockExtendedSizeLimit();
                        notifier.pickFiles();
                      },
                    );
                  },
                  icon: const Icon(Icons.card_giftcard),
                  label: const Text('Watch Ad & Unlock'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Send Files')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              if (uploadState.phase == UploadPhase.idle) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_upload_outlined,
                          size: 80,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Select files to transfer',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => notifier.pickFiles(),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Choose Files & Media'),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (uploadState.phase == UploadPhase.selecting) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E364F)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${uploadState.selectedFiles.length} files selected',
                      ),
                      Text(
                        '${FileSizeFormatter.format(uploadState.totalSize)} / ${uploadState.maxTotalSizeUnlockedMb} MB',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: uploadState.selectedFiles.length,
                    itemBuilder: (context, index) {
                      final f = uploadState.selectedFiles[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(FileSizeFormatter.format(f.size)),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: AppTheme.error,
                            ),
                            onPressed: () => notifier.removeFile(index),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => notifier.pickFiles(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add More Files'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          AdService.showRewardedInterstitialAd(
                            onRewardGranted: () {
                              notifier.setTransferMode(TransferMode.cloud);
                              notifier.startUpload(
                                attachToSessionId: attachToSessionId,
                                receiverPk: receiverPk,
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.cloud_upload, size: 18),
                        label: const Text('Cloud Session (10m)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          AdService.showRewardedAd(
                            onRewardGranted: () {
                              notifier.setTransferMode(TransferMode.p2p);
                              notifier.startUpload(
                                attachToSessionId: attachToSessionId,
                                receiverPk: receiverPk,
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.flash_on, size: 18),
                        label: const Text('Instant P2P Direct'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (uploadState.phase == UploadPhase.uploading) ...[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${(uploadState.overallProgress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: uploadState.overallProgress,
                        backgroundColor: AppTheme.cardBg,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Uploading file ${uploadState.currentFileIndex + 1} of ${uploadState.selectedFiles.length}',
                      ),
                      const SizedBox(height: 32),
                      OutlinedButton(
                        onPressed: () => notifier.cancelUpload(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                        ),
                        child: const Text('Cancel Transfer'),
                      ),
                    ],
                  ),
                ),
              ] else if (uploadState.phase == UploadPhase.failed) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 70,
                          color: AppTheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          uploadState.errorMessage ?? 'Upload failed',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => notifier.pickFiles(),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const AdBannerWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
