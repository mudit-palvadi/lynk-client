import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/download_notifier.dart';
import '../../../../core/providers/download_state.dart';
import '../../../../core/providers/transfer_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ad_banner_widget.dart';

class DownloadProgressScreen extends ConsumerStatefulWidget {
  final String transferId;
  final String aesKey;
  const DownloadProgressScreen({
    super.key,
    required this.transferId,
    this.aesKey = '',
  });

  @override
  ConsumerState<DownloadProgressScreen> createState() =>
      _DownloadProgressScreenState();
}

class _DownloadProgressScreenState
    extends ConsumerState<DownloadProgressScreen> {
  bool _autoStartTriggered = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(downloadProvider.notifier)
          .loadTransferPreview(widget.transferId),
    );
  }

  void _autoStartDownload(DownloadState next) {
    if (_autoStartTriggered) return;
    _autoStartTriggered = true;

    // Ad-free receiver experience: start reception immediately and confirm
    // with a lightweight snackbar. P2P is attempted first; the notifier
    // falls back to R2 automatically when direct transfer isn't possible.
    ref.read(downloadProvider.notifier).startReception(aesKey: widget.aesKey);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download started'),
        backgroundColor: AppTheme.secondary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(downloadProvider);
    final notifier = ref.read(downloadProvider.notifier);

    ref.listen<DownloadState>(downloadProvider, (previous, next) {
      if (next.phase == DownloadPhase.preview && next.transfer != null) {
        _autoStartDownload(next);
      }
    });

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Safe back navigation: preserve active download in background
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Download Transfer'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/home'),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                if (state.phase == DownloadPhase.idle ||
                    state.phase == DownloadPhase.preview) ...[
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Fetching transfer details...'),
                        ],
                      ),
                    ),
                  ),
                ] else if (state.phase == DownloadPhase.downloading) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(state.overallProgress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: state.overallProgress,
                          backgroundColor: AppTheme.cardBg,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          state.downloadFiles.isNotEmpty
                              ? 'Downloading file ${state.currentFileIndex + 1} of ${state.downloadFiles.length}'
                              : 'Starting background download stream...',
                        ),
                        const SizedBox(height: 32),
                        OutlinedButton(
                          onPressed: () {
                            notifier.cancelDownload();
                            if (state.transfer != null) {
                              ref
                                  .read(transferRepositoryProvider)
                                  .cancelTransfer(state.transfer!.id);
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Download cancelled.'),
                              ),
                            );
                            context.go('/home');
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                          ),
                          child: const Text('Cancel Download'),
                        ),
                      ],
                    ),
                  ),
                ] else if (state.phase == DownloadPhase.completed) ...[
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 70,
                          color: AppTheme.secondary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Download Complete!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: state.downloadedPaths.length,
                            itemBuilder: (context, index) {
                              final path = state.downloadedPaths[index];
                              final fileName = path.split('/').last;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.insert_drive_file,
                                    color: AppTheme.primary,
                                  ),
                                  title: Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () => notifier.openFile(path),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => context.go('/home'),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ] else if (state.phase == DownloadPhase.failed) ...[
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
                            state.errorMessage ?? 'Download failed',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {
                              _autoStartTriggered = false;
                              notifier.startReception(aesKey: widget.aesKey);
                            },
                            child: const Text('Retry Download'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => context.go('/home'),
                            child: const Text('Back to Home'),
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
      ),
    );
  }
}
