import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/download_notifier.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/file_size_formatter.dart';
import '../../../file_transfer/presentation/providers/upload_notifier.dart';
import '../../domain/entities/recent_transfer_record.dart';
import '../providers/recent_transfers_notifier.dart';

/// Builds the title shown on a recent-transfer card.
///
/// A transfer that was cancelled or interrupted can be recorded with no file
/// names at all, so the first name is never read without a check. Without that
/// check a single empty record takes the whole list down: the card is built
/// inside a `ListView`, and one failed item is drawn in place while its
/// neighbours keep rendering.
String recentTransferTitle(List<String> fileNames) {
  if (fileNames.isEmpty) return 'No files';
  if (fileNames.length == 1) return fileNames.first;
  return '${fileNames.first} + ${fileNames.length - 1} files';
}

class RecentTransfersWidget extends ConsumerWidget {
  const RecentTransfersWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentState = ref.watch(recentTransfersProvider);

    return recentState.when(
      data: (records) {
        if (records.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.of(context).textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _confirmClearHistory(context, ref),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppTheme.of(context).textSecondary,
                  ),
                  label: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.of(context).textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: records.length > 5 ? 5 : records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = records[index];
                return _buildRecentCard(context, ref, item);
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentCard(
    BuildContext context,
    WidgetRef ref,
    RecentTransferRecord item,
  ) {
    final isSent = item.type == RecentTransferType.sent;
    final title = recentTransferTitle(item.fileNames);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.of(context).cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSent
              ? AppTheme.of(context).primary.withValues(alpha: 0.3)
              : AppTheme.of(context).secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isSent
                ? AppTheme.of(context).primary.withValues(alpha: 0.15)
                : AppTheme.of(context).secondary.withValues(alpha: 0.15),
            child: Icon(
              isSent ? Icons.upload_file : Icons.download_for_offline,
              color: isSent
                  ? AppTheme.of(context).primary
                  : AppTheme.of(context).secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isSent ? 'Sent' : 'Received'} · ${FileSizeFormatter.format(item.totalSize)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isSent)
            ElevatedButton.icon(
              onPressed: () => _resendFiles(context, ref, item),
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Re-send', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
          else if (item.filePaths != null && item.filePaths!.isNotEmpty)
            OutlinedButton.icon(
              // A file written into the user's folder is a document URI, so
              // it opens through the grant rather than a path.
              onPressed: () => ref
                  .read(downloadProvider.notifier)
                  .openFile(item.filePaths!.first),
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text('Open', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _resendFiles(
    BuildContext context,
    WidgetRef ref,
    RecentTransferRecord item,
  ) async {
    if (item.filePaths == null || item.filePaths!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Original file locations unavailable for re-sending.'),
          backgroundColor: AppTheme.of(context).error,
        ),
      );
      return;
    }

    final validFiles = <PlatformFile>[];
    for (final path in item.filePaths!) {
      final file = File(path);
      if (await file.exists()) {
        final length = await file.length();
        final name = path.split(Platform.pathSeparator).last;
        validFiles.add(PlatformFile(name: name, path: path, size: length));
      }
    }

    if (validFiles.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Original files were moved or deleted from device.'),
            backgroundColor: AppTheme.of(context).error,
          ),
        );
      }
      return;
    }

    ref.read(uploadProvider.notifier).setFilesForTesting(validFiles);
    if (context.mounted) {
      context.push('/upload');
    }
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.of(context).cardBg,
        title: const Text('Clear History'),
        content: const Text(
          'Clear all recent transfer logs? Original files will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(recentTransfersProvider.notifier).clearHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.of(context).error,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
