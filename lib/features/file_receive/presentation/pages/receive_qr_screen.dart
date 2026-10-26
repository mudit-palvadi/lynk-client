import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/providers/receiver_notifier.dart';
import '../../../../core/routing/transfer_route_args.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_links.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import '../../../../core/widgets/scrollable_fill.dart';
import '../../../../core/widgets/transfer_role_heading.dart';
import '../helpers/receive_qr_helper.dart';

class ReceiveQrScreen extends ConsumerStatefulWidget {
  const ReceiveQrScreen({super.key});

  @override
  ConsumerState<ReceiveQrScreen> createState() => _ReceiveQrScreenState();
}

class _ReceiveQrScreenState extends ConsumerState<ReceiveQrScreen> {
  final ValueNotifier<int> _secondsRemainingNotifier = ValueNotifier<int>(600);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(receiverProvider.notifier).createSession());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemainingNotifier.value = 600;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemainingNotifier.value > 0) {
        _secondsRemainingNotifier.value--;
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsRemainingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiverProvider);

    ref.listen<ReceiverState>(receiverProvider, (previous, next) {
      if (next.attachedTransferId != null) {
        final key = next.attachedAesKey ?? '';
        final token = next.attachedAccessToken ?? '';
        // The pairing flag tells the download screen that the sender put this
        // transfer on the server, so there is no direct connection to wait
        // for.
        final args = DownloadArguments(
          transferId: next.attachedTransferId!,
          aesKey: key,
          accessToken: token,
          viaPairing: true,
        );
        context.go(args.location, extra: args);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Receive Files')),
      body: SafeArea(
        // A short screen or large text pushed the Cancel Session button below
        // the body, with nothing to scroll.
        child: ScrollableFill(
          children: [
            const Spacer(),
            const TransferRoleHeading(
              role: 'You’re receiving',
              title: 'Your receiving QR',
              instruction: 'Ask the sender to scan this',
              icon: Icons.download_outlined,
            ),
            const SizedBox(height: 24),
            if (state.session != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                // A fixed box keeps the QR out of the intrinsic measurement:
                // qr_flutter builds a LayoutBuilder, which cannot report
                // intrinsics, and ScrollableFill asks for them.
                child: SizedBox.square(
                  dimension: 220,
                  child: QrImageView(
                    data:
                        '${AppLinks.deepLinkBase}/receive/${state.session!.id}#pk=${state.receiverPublicKeyB64 ?? ''}',
                    version: QrVersions.auto,
                    size: 220.0,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sender: scan this QR in LynkShare.'),
                    SizedBox(height: 8),
                    Text('Sender: choose files and send.'),
                    SizedBox(height: 8),
                    Text(
                      'You: keep this screen open. Receiving starts automatically.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: _secondsRemainingNotifier,
                builder: (context, seconds, child) {
                  return Text(
                    'Session expires in ${ReceiveQrHelper.formatTime(seconds)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Waiting for sender to connect...',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ] else if (state.errorMessage != null) ...[
              const Icon(Icons.error_outline, size: 60, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref.read(receiverProvider.notifier).createSession();
                  _startTimer();
                },
                child: const Text('Retry Session'),
              ),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Creating your receiving QR…',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
            const Spacer(),
            OutlinedButton(
              onPressed: () =>
                  ReceiveQrHelper.cancelSessionAndPop(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
              ),
              child: const Text('Cancel Session'),
            ),
            const SizedBox(height: 16),
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }
}
