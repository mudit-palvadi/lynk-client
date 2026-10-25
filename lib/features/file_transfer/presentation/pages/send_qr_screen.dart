import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/file_size_formatter.dart';
import '../../../../core/utils/qr_share_helper.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import '../../../../core/widgets/scrollable_fill.dart';
import '../../domain/entities/transfer.dart';
import '../helpers/send_qr_helper.dart';
import '../providers/sender_code_notifier.dart';
import '../providers/upload_notifier.dart';
import '../providers/upload_state.dart';

class SendQrScreen extends ConsumerStatefulWidget {
  final Transfer transfer;
  final String aesKey;
  const SendQrScreen({super.key, required this.transfer, this.aesKey = ''});

  @override
  ConsumerState<SendQrScreen> createState() => _SendQrScreenState();
}

class _SendQrScreenState extends ConsumerState<SendQrScreen> {
  late final ValueNotifier<int> _secondsRemainingNotifier;
  Timer? _timer;
  final GlobalKey _qrKey = GlobalKey();
  SenderCodeNotifier? _codeNotifier;
  TransferMode _mode = TransferMode.cloud;

  @override
  void initState() {
    super.initState();
    final initialRemaining = SendQrHelper.calculateRemainingSeconds(
      widget.transfer.createdAt,
    );
    _secondsRemainingNotifier = ValueNotifier<int>(initialRemaining);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemainingNotifier.value > 0) {
        _secondsRemainingNotifier.value--;
      } else {
        _timer?.cancel();
      }
    });

    // Minting the code touches a provider, which must not happen during the
    // widget build itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCode());
  }

  void _startCode() {
    if (!mounted) return;
    _mode = ref.read(uploadProvider).transferMode;
    _codeNotifier = ref.read(senderCodeProvider.notifier);
    _codeNotifier!.ensureStarted(
      transferId: widget.transfer.id,
      aesKey: widget.aesKey.isNotEmpty
          ? widget.aesKey
          : (ref.read(uploadProvider).aesKey ?? ''),
      accessToken: widget.transfer.accessToken,
      mode: _mode,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsRemainingNotifier.dispose();
    // A direct send only works while its screen is open, so its code dies
    // with the screen. A cloud send keeps waiting in the background.
    if (_mode == TransferMode.p2p) _codeNotifier?.stop();
    super.dispose();
  }

  Widget _buildP2pStatus(UploadState state) {
    final p2pActive =
        state.phase == UploadPhase.uploading ||
        state.p2pStage != P2PSendStage.none;

    if (state.p2pStage == P2PSendStage.waitingForReceiver) {
      return const Column(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 10),
          Text(
            'Waiting for receiver to scan...',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Keep this screen open',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      );
    }

    if (state.p2pStage == P2PSendStage.transferring) {
      return Column(
        children: [
          Text(
            'Sending directly... ${(state.overallProgress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: AppTheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.overallProgress),
        ],
      );
    }

    if (state.p2pStage == P2PSendStage.none &&
        state.phase == UploadPhase.uploading) {
      return const Column(
        children: [
          Text(
            'Establishing secure connection...',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          SizedBox(height: 8),
          LinearProgressIndicator(),
        ],
      );
    }

    if (state.phase == UploadPhase.completed && p2pActive) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: AppTheme.secondary),
          SizedBox(width: 6),
          Text('Delivered directly'),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCodeSection(SenderCodeState codeState) {
    if (codeState.phase == SenderCodePhase.failed ||
        codeState.phase == SenderCodePhase.expired) {
      return Text(
        codeState.errorMessage ?? 'The code is unavailable.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      );
    }

    final code = codeState.code;
    if (code == null || code.isEmpty) {
      return const Text(
        'Creating a 6-digit code…',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      );
    }

    return Column(
      children: [
        const Text(
          'Or type this code in the app',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          code.split('').join(' '),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          codeState.isAttached
              ? 'Receiver joined — the files are unlocked.'
              : 'Waiting for the receiver…',
          style: TextStyle(
            color: codeState.isAttached
                ? AppTheme.secondary
                : AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadProvider);
    final codeState = ref.watch(senderCodeProvider);
    final qrData = SendQrHelper.buildQrData(
      ref: ref,
      transferId: widget.transfer.id,
      aesKey: widget.aesKey,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Share Transfer'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/home'),
          ),
        ),
        body: SafeArea(
          // The QR, code, expiry and three actions are taller than a short
          // phone's body, which used to clip the Cancel Session button.
          child: ScrollableFill(
            children: [
              const Spacer(),
              RepaintBoundary(
                key: _qrKey,
                child: Container(
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
                      data: qrData,
                      version: QrVersions.auto,
                      size: 220.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Scan with Lynk App to Download',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildCodeSection(codeState),
              const SizedBox(height: 12),
              ValueListenableBuilder<int>(
                valueListenable: _secondsRemainingNotifier,
                builder: (context, seconds, child) {
                  return Column(
                    children: [
                      Text(
                        'Expires in ${SendQrHelper.formatRemainingTime(seconds)}',
                        style: const TextStyle(
                          color: AppTheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (seconds > 0 &&
                          seconds < 1500 &&
                          !(uploadState.transferMode == TransferMode.p2p &&
                              uploadState.p2pStage ==
                                  P2PSendStage.transferring)) ...[
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: () => SendQrHelper.extendSessionTimeWithAd(
                            context: context,
                            ref: ref,
                            transferId: widget.transfer.id,
                            secondsNotifier: _secondsRemainingNotifier,
                          ),
                          icon: const Icon(
                            Icons.timer_outlined,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                          label: const Text(
                            'Extend Session to 30 Mins (Watch Ad)',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.transfer.totalFiles} files · ${FileSizeFormatter.format(widget.transfer.totalSize)}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              if (uploadState.transferMode == TransferMode.p2p) ...[
                const SizedBox(height: 16),
                _buildP2pStatus(uploadState),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  context.push(
                    '/scan-qr?attachTransferId=${widget.transfer.id}',
                  );
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text("Scan Receiver's Code"),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => QrShareHelper.captureAndShareQr(
                  qrKey: _qrKey,
                  transferId: widget.transfer.id,
                ),
                icon: const Icon(Icons.share),
                label: const Text('Share QR Image'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  if (uploadState.p2pStage != P2PSendStage.none ||
                      uploadState.phase == UploadPhase.uploading) {
                    ref.read(uploadProvider.notifier).cancelUpload();
                  }
                  ref.read(senderCodeProvider.notifier).stop();
                  SendQrHelper.cancelSessionAndGoHome(
                    context: context,
                    ref: ref,
                    transferId: widget.transfer.id,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                ),
                child: const Text('Cancel Session'),
              ),
              const SizedBox(height: 16),
              const AdBannerWidget(),
            ],
          ),
        ),
      ),
    );
  }
}
