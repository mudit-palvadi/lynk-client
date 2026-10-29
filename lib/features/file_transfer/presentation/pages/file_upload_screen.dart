import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/transfer_route_args.dart';
import '../../../../core/services/ad_gate.dart';
import '../../../../core/services/transfer_ad_gate.dart';
import '../../../../core/services/unlock_credits.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/file_size_formatter.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import '../providers/upload_notifier.dart';
import '../providers/upload_state.dart';

class FileUploadScreen extends ConsumerStatefulWidget {
  final String? attachToSessionId;

  /// Receiver's ephemeral public key (base64url) when pairing via a
  /// receiver-session QR. Used to wrap the AES key client-side.
  final String? receiverPk;

  const FileUploadScreen({super.key, this.attachToSessionId, this.receiverPk});

  @override
  ConsumerState<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends ConsumerState<FileUploadScreen> {
  bool _p2pScreenPushed = false;

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadProvider);
    final notifier = ref.read(uploadProvider.notifier);

    ref.listen<UploadState>(uploadProvider, (previous, next) async {
      // A refused pick never clears the staged files, so its message is a
      // transient snackbar over the selection view rather than the full-screen
      // error page.
      if (next.noticeSeq != previous?.noticeSeq && next.notice != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.notice!),
            backgroundColor: AppTheme.of(context).error,
          ),
        );
      }
      //  P2P: navigate to the QR screen the moment the session is live --
      // BEFORE any connection exists -- so the receiver has something to
      // scan. Live status (waiting / sending %) renders on SendQrScreen.
      // Skipped in reverse-pairing mode: the receiver's QR was already
      // scanned at entry, and completion routes home instead.
      if (next.transferMode == TransferMode.p2p &&
          widget.attachToSessionId == null &&
          next.phase == UploadPhase.uploading &&
          next.p2pStage != P2PSendStage.none &&
          next.p2pStage != P2PSendStage.preparing &&
          next.transfer != null &&
          !_p2pScreenPushed) {
        _p2pScreenPushed = true;
        final key = next.aesKey ?? '';
        context.go(
          '/send-qr',
          extra: SendQrArguments(transfer: next.transfer!, aesKey: key),
        );
        return;
      }
      if (next.phase == UploadPhase.completed && next.transfer != null) {
        final key = next.aesKey ?? '';
        if (widget.attachToSessionId != null &&
            widget.attachToSessionId!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transfer sent to receiver successfully!'),
              backgroundColor: AppTheme.of(context).secondary,
            ),
          );
          context.go('/home');
        } else {
          context.go(
            '/send-qr',
            extra: SendQrArguments(transfer: next.transfer!, aesKey: key),
          );
        }
      } else if (next.phase == UploadPhase.failed &&
          next.errorMessage != null) {
        final msg = next.errorMessage!;
        if (msg.contains('Watch an ad to unlock')) {
          final credits = await AdGate().sizeCredits();
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.of(context).cardBg,
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
                    UnlockCredits().spendSize(() {
                      notifier.unlockExtendedSizeLimit();
                      // The refused files are still remembered: re-run them
                      // instead of making the user pick them again.
                      if (!notifier.retryRejectedSelection()) {
                        notifier.pickFiles();
                      }
                    });
                  },
                  icon: Icon(
                    credits > 0 ? Icons.lock_open : Icons.card_giftcard,
                  ),
                  label: Text(credits > 0 ? 'Unlock' : 'Watch Ad & Unlock'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              backgroundColor: AppTheme.of(context).error,
            ),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Send Files')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.attachToSessionId?.isNotEmpty ?? false) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.of(
                          context,
                        ).secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.link,
                            color: AppTheme.of(context).secondary,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Receiver linked',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text('Receiving QR linked. Choose files to send.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (uploadState.phase == UploadPhase.idle) ...[
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppTheme.of(context).accentSurface,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.file_present_outlined,
                        size: 72,
                        color: AppTheme.of(context).primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Choose what to send',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose files, then choose a transfer method.',
                      style: TextStyle(
                        color: AppTheme.of(context).textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => notifier.pickFiles(),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Choose Files & Media'),
                    ),
                  ] else if (uploadState.phase == UploadPhase.selecting) ...[
                    Text(
                      'Review files',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check the selection, then choose a transfer method.',
                      style: TextStyle(
                        color: AppTheme.of(context).textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.of(context).cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.of(context).border),
                      ),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          Text(
                            '${uploadState.selectedFiles.length} of ${UploadState.maxFiles} files',
                          ),
                          Text(
                            '${FileSizeFormatter.format(uploadState.totalSize)} / ${uploadState.maxTotalSizeMb} MB',
                            style: TextStyle(
                              color: AppTheme.of(context).primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(uploadState.selectedFiles.length, (index) {
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
                            tooltip: 'Remove ${f.name}',
                            icon: Icon(
                              Icons.close,
                              color: AppTheme.of(context).error,
                            ),
                            onPressed: () => notifier.removeFile(index),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => notifier.pickFiles(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add More Files'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Transfer method',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _SendChoice(
                      title: 'Cloud',
                      description:
                          'Share files with multiple recipients simultaneously while the session is active. All files are encrypted.',
                      icon: Icons.cloud_upload_outlined,
                      color: AppTheme.of(context).secondary,
                      onPressed: () =>
                          _startTransfer(uploadState, TransferMode.cloud),
                    ),
                    const SizedBox(height: 12),
                    _SendChoice(
                      title: 'Direct',
                      description:
                          'Files transfer directly between devices without passing through a server, providing higher privacy. Both devices must remain online throughout the transfer.',
                      icon: Icons.swap_horiz,
                      color: AppTheme.of(context).primary,
                      onPressed: () =>
                          _startTransfer(uploadState, TransferMode.p2p),
                    ),
                  ] else if (uploadState.phase == UploadPhase.uploading) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(uploadState.overallProgress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.of(context).primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: uploadState.overallProgress,
                            backgroundColor: AppTheme.of(context).cardBg,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            uploadState.transferMode == TransferMode.p2p
                                ? (directTransferStatus(uploadState) ??
                                      'Connecting to receiver device...')
                                : 'Uploading files...',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          OutlinedButton(
                            onPressed: () => notifier.cancelUpload(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.of(context).error,
                              side: BorderSide(
                                color: AppTheme.of(context).error,
                              ),
                            ),
                            child: Text(
                              uploadState.transferMode == TransferMode.p2p
                                  ? 'Cancel Transfer'
                                  : 'Cancel Upload',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (uploadState.phase == UploadPhase.failed) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 70,
                              color: AppTheme.of(context).error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              uploadState.transferMode == TransferMode.p2p
                                  ? (directTransferStatus(uploadState) ??
                                        'Transfer failed')
                                  : (uploadState.errorMessage ??
                                        'Upload failed'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                // Start from a clean slate: this view is also
                                // reached after a failed upload, and appending a
                                // new pick to a half-sent list would be wrong.
                                notifier.reset();
                                notifier.pickFiles();
                              },
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (uploadState.phase == UploadPhase.idle ||
                      uploadState.phase == UploadPhase.selecting) ...[
                    const SizedBox(height: 16),
                    const AdBannerWidget(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startTransfer(UploadState state, TransferMode mode) {
    final notifier = ref.read(uploadProvider.notifier);
    TransferAdGate().start(
      p2p: mode == TransferMode.p2p,
      sizeUnlockAlreadyPaid:
          state.isSizeLimitUnlocked &&
          state.rawTotalSize > state.maxTotalSizeFree,
      onAllowed: () {
        notifier.setTransferMode(mode);
        notifier.startUpload(
          attachToSessionId: widget.attachToSessionId,
          receiverPk: widget.receiverPk,
        );
      },
    );
  }
}

class _SendChoice extends StatelessWidget {
  const _SendChoice({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.of(context).cardBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(color: AppTheme.of(context).textSecondary),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(title),
          style: ElevatedButton.styleFrom(backgroundColor: color),
        ),
      ],
    ),
  );
}
