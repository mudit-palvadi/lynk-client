import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/code_receiver_notifier.dart';
import '../../../../core/routing/transfer_route_args.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ad_banner_widget.dart';
import '../../../../core/widgets/scrollable_fill.dart';

/// Receives a transfer by typing the six-digit code the sender shows.
class EnterCodeScreen extends ConsumerStatefulWidget {
  const EnterCodeScreen({super.key});

  @override
  ConsumerState<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends ConsumerState<EnterCodeScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isComplete => _controller.text.length == 6;

  void _submit() {
    if (!_isComplete) return;
    FocusScope.of(context).unfocus();
    ref.read(codeReceiverProvider.notifier).joinWithCode(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codeReceiverProvider);

    ref.listen<CodeReceiveState>(codeReceiverProvider, (previous, next) {
      final transferId = next.transferId;
      if (transferId == null || next.isReady == (previous?.isReady ?? false)) {
        return;
      }
      final args = DownloadArguments(
        transferId: transferId,
        aesKey: next.aesKey ?? '',
        accessToken: next.accessToken ?? '',
        // A cloud sender uploaded before the code was used, so the direct
        // channel is not worth waiting for. A direct sender is still holding
        // the files and the share screen open.
        viaPairing: next.viaPairing,
      );
      context.go(args.location, extra: args);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Enter a Code')),
      body: SafeArea(
        // The field autofocuses, so the keyboard is open on the first frame
        // and the body is shorter than the screen.
        child: ScrollableFill(
          children: [
            const Spacer(),
            const Icon(Icons.dialpad, size: 64, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Type the 6-digit code',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The sender shows it next to the QR code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !state.isBusy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 36,
                letterSpacing: 14,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(
                  fontSize: 36,
                  letterSpacing: 14,
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                ),
                filled: true,
                fillColor: AppTheme.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            if (state.errorMessage != null) ...[
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.error),
              ),
              const SizedBox(height: 16),
            ],
            if (state.isBusy) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                state.isJoining
                    ? 'Checking the code...'
                    : 'Waiting for the sender to share the key...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    ref.read(codeReceiverProvider.notifier).cancel(),
                child: const Text('Use a Different Code'),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isComplete ? _submit : null,
                  icon: const Icon(Icons.download),
                  label: const Text('Receive Files'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            const Spacer(),
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }
}
