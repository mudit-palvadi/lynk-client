import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/providers/transfer_providers.dart'
    show senderSessionRemoteDataSourceProvider;
import '../../../../core/services/key_fingerprint.dart';
import '../../../../core/services/key_wrap_service.dart';
import '../providers/upload_state.dart' show TransferMode;
import 'sender_pairing.dart';

part 'sender_code_notifier.g.dart';

/// Where the sender's six-digit code stands.
enum SenderCodePhase { idle, creating, waiting, attached, expired, failed }

class SenderCodeState {
  final SenderCodePhase phase;

  /// The digits to show on the share screen, once the server minted them.
  final String? code;

  /// The transfer this code hands over, so a second visit does not start a
  /// new session for the same files.
  final String? transferId;

  /// Eight-digit check of the receiver public key, once one has joined.
  final String? keyCheck;

  final String? errorMessage;

  const SenderCodeState({
    this.phase = SenderCodePhase.idle,
    this.code,
    this.transferId,
    this.keyCheck,
    this.errorMessage,
  });

  /// The code is still waiting for someone to type it.
  bool get isActive =>
      phase == SenderCodePhase.creating || phase == SenderCodePhase.waiting;

  bool get isAttached => phase == SenderCodePhase.attached;
}

/// Keeps the sender's code session alive while the app moves on.
///
/// A cloud sender may leave the share screen right after uploading: the code
/// is still good, and the receiver must be able to collect the wrapped key.
/// That is why this provider is kept alive instead of tied to the screen.
@Riverpod(keepAlive: true)
class SenderCodeNotifier extends _$SenderCodeNotifier {
  /// How often the sender asks whether a receiver has joined.
  @visibleForTesting
  Duration pollInterval = const Duration(seconds: 2);

  SenderPairing? _pairing;
  Timer? _timer;
  DateTime? _expiresAt;
  bool _polling = false;

  @override
  SenderCodeState build() {
    ref.onDispose(_cancelTimer);
    return const SenderCodeState();
  }

  /// Starts the pairing for [transferId], or resumes the one already waiting.
  Future<void> ensureStarted({
    required String transferId,
    required String aesKey,
    String? accessToken,
    required TransferMode mode,
  }) async {
    if (state.transferId == transferId && state.isActive && !_isExpired) {
      _schedulePoll();
      return;
    }

    _reset();
    state = SenderCodeState(
      phase: SenderCodePhase.creating,
      transferId: transferId,
    );

    final pairing = SenderPairing(
      dataSource: ref.read(senderSessionRemoteDataSourceProvider),
      transferId: transferId,
      aesKey: aesKey,
      accessToken: accessToken,
      mode: mode.name,
      wrapKey:
          ({
            required aesKey,
            required receiverPublicKeyB64,
            required sessionId,
            accessToken,
          }) => ref
              .read(keyWrapServiceProvider)
              .wrapKey(
                aesKey: aesKey,
                receiverPublicKeyB64: receiverPublicKeyB64,
                sessionId: sessionId,
                accessToken: accessToken,
              ),
    );
    _pairing = pairing;

    final started = await pairing.start();
    if (!ref.mounted) return;

    if (!started) {
      state = SenderCodeState(
        phase: SenderCodePhase.failed,
        transferId: transferId,
        errorMessage: 'Could not create a code. Pull up the QR to try again.',
      );
      return;
    }

    // The receiver has ten minutes from the moment the code was minted.
    _expiresAt = DateTime.now().add(const Duration(minutes: 10));
    state = SenderCodeState(
      phase: SenderCodePhase.waiting,
      code: pairing.code,
      transferId: transferId,
    );
    _schedulePoll();
  }

  /// Stops waiting, for a direct send whose screen was closed.
  void stop() {
    _reset();
    state = const SenderCodeState();
  }

  bool get _isExpired {
    final expiresAt = _expiresAt;
    return expiresAt != null && !DateTime.now().isBefore(expiresAt);
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (_pairing == null || !state.isActive) return;
    _timer = Timer.periodic(pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_polling) return;
    final pairing = _pairing;
    if (pairing == null) {
      _cancelTimer();
      return;
    }

    if (_isExpired) {
      _cancelTimer();
      if (ref.mounted) {
        state = SenderCodeState(
          phase: SenderCodePhase.expired,
          transferId: state.transferId,
          errorMessage:
              'That code has expired. Open the share screen for a new one.',
        );
      }
      return;
    }

    _polling = true;
    try {
      final keepGoing = await pairing.poll();
      if (!ref.mounted) return;

      if (keepGoing) return;

      _cancelTimer();
      if (pairing.isAttached) {
        state = SenderCodeState(
          phase: SenderCodePhase.attached,
          code: state.code,
          transferId: state.transferId,
          keyCheck: _keyCheck(pairing),
        );
      } else {
        state = SenderCodeState(
          phase: SenderCodePhase.failed,
          code: state.code,
          transferId: state.transferId,
          keyCheck: _keyCheck(pairing),
          errorMessage: 'Could not hand the file key to the receiver.',
        );
      }
    } finally {
      _polling = false;
    }
  }

  String? _keyCheck(SenderPairing pairing) {
    final publicKey = pairing.receiverPublicKey;
    if (publicKey == null || publicKey.isEmpty) return null;
    return keyFingerprint(publicKey);
  }

  void _reset() {
    _cancelTimer();
    _pairing = null;
    _expiresAt = null;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
