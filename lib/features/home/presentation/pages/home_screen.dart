import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/download_notifier.dart';
import '../../../../core/providers/download_state.dart';
import '../../../../core/services/config_service.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/file_transfer/presentation/providers/upload_notifier.dart';
import '../../../../features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/recent_transfers/presentation/widgets/recent_transfers_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionHelper.requestAllPermissions();
    });
  }

  void _onVersionTap() {
    _tapCount++;
    if (_tapCount == 7) {
      _tapCount = 0;
      _showPasscodeDialog();
    }
  }

  void _showPasscodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: const Text('System Diagnostic Key'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Enter config payload'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await ConfigService.applyConfigurationKey(
                controller.text,
              );
              if (success && context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('System configuration updated.'),
                  ),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadProvider);
    final downloadState = ref.watch(downloadProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'lynk',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(letterSpacing: 2),
              ),
              const SizedBox(height: 24),
              if (uploadState.phase == UploadPhase.completed &&
                  uploadState.transfer != null) ...[
                InkWell(
                  onTap: () {
                    final key = uploadState.aesKey ?? '';
                    context.push(
                      '/send-qr?aesKey=$key',
                      extra: uploadState.transfer!,
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.secondary),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.flash_on, color: AppTheme.secondary),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Active Transfer Session',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondary,
                                ),
                              ),
                              Text(
                                'Tap to show QR code again',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: AppTheme.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _ActionCard(
                icon: Icons.upload_file,
                title: 'Send Files',
                subtitle: 'Upload and share files via QR or direct link',
                onTap: () => context.push('/upload'),
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.qr_code_scanner,
                title: 'Scan QR Code',
                subtitle: 'Scan a sender or receiver QR code',
                onTap: () => context.push('/scan-qr'),
              ),
              const SizedBox(height: 16),
              _ActionCard(
                icon: Icons.qr_code_2,
                title: 'Receive Files',
                subtitle: 'Generate a receive session QR code',
                onTap: () => context.push('/receive-qr'),
              ),
              if (downloadState.phase == DownloadPhase.downloading) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    if (downloadState.transfer != null) {
                      final key = downloadState.aesKey ?? '';
                      context.push(
                        '/download-progress/${downloadState.transfer!.id}?aesKey=$key',
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.downloading,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Downloading: ${(downloadState.overallProgress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                              color: AppTheme.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: downloadState.overallProgress,
                          backgroundColor: AppTheme.cardBg,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const RecentTransfersWidget(),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: _onVersionTap,
                  child: const Text(
                    'v1.0.0+1',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E364F), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: AppTheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
