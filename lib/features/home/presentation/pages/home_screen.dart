import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/download_notifier.dart';
import '../../../../core/providers/download_state.dart';
import '../../../../core/routing/transfer_route_args.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../file_transfer/presentation/providers/upload_notifier.dart';
import '../../../file_transfer/presentation/providers/upload_state.dart';
import '../../../onboarding/presentation/providers/home_tutorial_provider.dart';
import '../../../onboarding/presentation/widgets/home_coach_marks.dart';
import '../../../recent_transfers/presentation/providers/recent_transfers_notifier.dart';
import '../../../recent_transfers/presentation/widgets/recent_transfers_widget.dart';
import '../providers/home_navigation_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _sendKey = GlobalKey();
  final _receiveKey = GlobalKey();
  final _activityKey = GlobalKey();
  final _settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PermissionHelper.requestAllPermissions();
      }
    });
  }

  void _openUpload() {
    final phase = ref.read(uploadProvider).phase;
    if (phase == UploadPhase.completed || phase == UploadPhase.cancelled) {
      ref.read(uploadProvider.notifier).reset();
    }
    context.push('/upload');
  }

  List<HomeCoachMarkStep> _tutorialSteps() => [
    HomeCoachMarkStep(
      targetKey: _sendKey,
      title: 'Send a file',
      description:
          'Choose files, then share a QR or six-digit code with the receiver.',
    ),
    HomeCoachMarkStep(
      targetKey: _receiveKey,
      title: 'Three ways to receive',
      description:
          'Scan the sender’s QR, enter their code, or show your own receiving QR for them to scan.',
    ),
    HomeCoachMarkStep(
      targetKey: _activityKey,
      title: 'Find your transfers',
      description: 'Open received files or send something again from Activity.',
    ),
    HomeCoachMarkStep(
      targetKey: _settingsKey,
      title: 'Choose where files land',
      description:
          'Your download folder is in Settings. Receiving help is always available on the Receive tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(homeNavigationProvider);
    final upload = ref.watch(uploadProvider);
    final download = ref.watch(downloadProvider);
    final showTutorial = !ref.watch(homeTutorialProvider);

    return Stack(
      children: [
        Scaffold(
          bottomNavigationBar: NavigationBar(
            selectedIndex: destination.index,
            onDestinationSelected: (index) => ref
                .read(homeNavigationProvider.notifier)
                .select(HomeDestination.values[index]),
            backgroundColor: AppTheme.darkBg,
            indicatorColor: AppTheme.primary.withValues(alpha: 0.22),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.arrow_upward_rounded),
                label: 'Send',
              ),
              NavigationDestination(
                key: _receiveKey,
                icon: const Icon(Icons.arrow_downward_rounded),
                label: 'Receive',
              ),
              NavigationDestination(
                key: _activityKey,
                icon: const Icon(Icons.history_rounded),
                label: 'Activity',
              ),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  key: ValueKey(destination),
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: AppTheme.primary,
                            size: 30,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'lynk',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          IconButton(
                            key: _settingsKey,
                            tooltip: 'Settings',
                            onPressed: () => context.push('/settings'),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (upload.phase == UploadPhase.completed &&
                          upload.transfer != null) ...[
                        _ActionCard(
                          icon: Icons.qr_code_rounded,
                          title: 'Active Transfer Session',
                          subtitle: 'Tap to show QR code again',
                          onTap: () => context.push(
                            '/send-qr',
                            extra: SendQrArguments(
                              transfer: upload.transfer!,
                              aesKey: upload.aesKey ?? '',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (download.phase == DownloadPhase.downloading &&
                          download.transfer != null) ...[
                        _ActionCard(
                          icon: Icons.downloading_rounded,
                          title:
                              'Downloading: ${(download.overallProgress * 100).toStringAsFixed(0)}%',
                          subtitle: 'Tap to return to your transfer',
                          onTap: () {
                            final args = DownloadArguments(
                              transferId: download.transfer!.id,
                              aesKey: download.aesKey ?? '',
                              accessToken: download.accessToken ?? '',
                            );
                            context.push(args.location, extra: args);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      ...switch (destination) {
                        HomeDestination.send => _sendContent(context),
                        HomeDestination.receive => _receiveContent(context),
                        HomeDestination.activity => [const _ActivityContent()],
                      },
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showTutorial)
          Positioned.fill(
            child: HomeCoachMarks(
              steps: _tutorialSteps(),
              onFinished: () =>
                  ref.read(homeTutorialProvider.notifier).complete(),
            ),
          ),
      ],
    );
  }

  List<Widget> _sendContent(BuildContext context) => [
    Text(
      'A little closer.\nWith every share.',
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    const SizedBox(height: 12),
    const Text(
      'Choose files, then share a QR or six-digit code. No account needed.',
    ),
    const SizedBox(height: 28),
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DeviceBadge(icon: Icons.phone_android_rounded, label: 'You'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppTheme.primary,
                ),
              ),
              _DeviceBadge(icon: Icons.devices_rounded, label: 'Receiver'),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            key: _sendKey,
            onPressed: _openUpload,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Send Files'),
          ),
          const SizedBox(height: 12),
          const Text('Pick • Review • Share', textAlign: TextAlign.center),
        ],
      ),
    ),
    const SizedBox(height: 24),
    _ActionCard(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Receiver has a QR?',
      subtitle: 'Scan their receiving QR, then choose your files.',
      onTap: () => context.push('/scan-qr'),
    ),
  ];

  List<Widget> _receiveContent(BuildContext context) => [
    Text(
      'Ready to receive?',
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    const SizedBox(height: 8),
    const Text('Start with what the sender has shared with you.'),
    const SizedBox(height: 24),
    _ActionCard(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Scan sender’s QR',
      subtitle: 'They show the QR. You scan it.',
      onTap: () => context.push('/scan-qr'),
    ),
    const SizedBox(height: 12),
    _ActionCard(
      icon: Icons.dialpad_rounded,
      title: 'Enter code',
      subtitle: 'Type the six digits shown on the sender’s screen.',
      onTap: () => context.push('/receive-code'),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Text('Or let the sender connect to you'),
    ),
    _ActionCard(
      icon: Icons.qr_code_2_rounded,
      title: 'Show my receiving QR',
      subtitle: 'The sender scans your QR, then chooses files to send to you.',
      onTap: () => context.push('/receive-qr'),
    ),
    const SizedBox(height: 16),
    TextButton.icon(
      onPressed: () => _showReceivingHelp(context),
      icon: const Icon(Icons.help_outline_rounded),
      label: const Text('How receiving works'),
    ),
  ];

  void _showReceivingHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Two screens. One connection.'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Their QR, your camera',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'If the sender has chosen files, scan their sharing QR or enter their six-digit code.',
              ),
              SizedBox(height: 24),
              Text(
                'Your QR, their camera',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Show your receiving QR. The sender scans it in LynkShare, chooses files and sends. Your download starts automatically when the files are ready. Keep this screen open, and only share the QR with someone you trust.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _ActivityContent extends ConsumerWidget {
  const _ActivityContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransfersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your activity',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text('Find received files and things you’ve shared.'),
        const SizedBox(height: 24),
        if (recent.asData?.value.isEmpty ?? false)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: AppTheme.textSecondary,
                ),
                SizedBox(height: 16),
                Text('Your transfers will appear here.'),
              ],
            ),
          )
        else
          const RecentTransfersWidget(),
      ],
    );
  }
}

class _DeviceBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DeviceBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Flexible(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 32),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Material(
    color: AppTheme.cardBg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppTheme.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
