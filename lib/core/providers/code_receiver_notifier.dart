import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/key_fingerprint.dart';
import '../services/key_wrap_service.dart';
import 'receiver_providers.dart';

part 'code_receiver_notifier.g.dart';

/// Where a receiver is in the code-pairing flow.
class CodeReceiveState {
  /// The join request is in flight.
  final bool isJoining;

  /// The code was accepted and the sender has not wrapped the key yet.
  final bool isWaiting;

  final String? sessionId;
  final String? transferId;
  final String? aesKey;
  final String? accessToken;

  /// Eight-digit check of this device's public key, once the code is accepted.
  final String? keyCheck;

  /// True when the sender uploaded first, so a direct connection is pointless.
  final bool viaPairing;

  final String? errorMessage;

  const CodeReceiveState({
    this.isJoining = false,
    this.isWaiting = false,
    this.sessionId,
    this.transferId,
    this.aesKey,
    this.accessToken,
    this.keyCheck,
    this.viaPairing = true,
    this.errorMessage,
  });

  bool get isReady => transferId != null;

  bool get isBusy => isJoining || isWaiting;

  CodeReceiveState copyWith({
    bool? isJoining,
    bool? isWaiting,
    String? sessionId,
    String? transferId,
    String? aesKey,
    String? accessToken,
    String? keyCheck,
    bool? viaPairing,
    String? errorMessage,
  }) {
    return CodeReceiveState(
      isJoining: isJoining ?? this.isJoining,
      isWaiting: isWaiting ?? this.isWaiting,
      sessionId: sessionId ?? this.sessionId,
      transferId: transferId ?? this.transferId,
      aesKey: aesKey ?? this.aesKey,
      accessToken: accessToken ?? this.accessToken,
      keyCheck: keyCheck ?? this.keyCheck,
      viaPairing: viaPairing ?? this.viaPairing,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Types the sender's six-digit code into a paired transfer.
///
/// The code names the session. The receiver publishes an ephemeral public key,
/// then asks again and again until the sender has wrapped the AES key for it.
/// Nothing secret is ever recoverable from the code itself.
@riverpod
class CodeReceiverNotifier extends _$CodeReceiverNotifier {
  /// How often the receiver asks whether the sender wrapped the key.
  @visibleForTesting
  Duration pollInterval = const Duration(seconds: 2);

  Timer? _pollTimer;
  String? _activeSessionId;
  Uint8List? _privateKeySeed;

  /// When the code the sender minted stops naming anything.
  DateTime? _deadline;

  @override
  CodeReceiveState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const CodeReceiveState();
  }

  /// Joins the session [code] names and starts waiting for the wrapped key.
  Future<void> joinWithCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    _reset();
    state = const CodeReceiveState(isJoining: true);

    try {
      final pair = await ref
          .read(keyWrapServiceProvider)
          .generateReceiverKeyPair();
      final joined = await ref
          .read(codeSessionRemoteDataSourceProvider)
          .join(code: trimmed, receiverPk: pair.publicKeyB64);
      if (!ref.mounted) return;

      _activeSessionId = joined.sessionId;
      _privateKeySeed = pair.privateKeySeed;
      _deadline = DateTime.now().add(Duration(seconds: joined.expiresIn));

      state = CodeReceiveState(
        isWaiting: true,
        sessionId: joined.sessionId,
        keyCheck: keyFingerprint(pair.publicKeyB64),
      );
      _schedulePoll();
    } catch (e) {
      if (!ref.mounted) return;
      _fail(_messageFor(e));
    }
  }

  /// Stops waiting and forgets everything, so a new code can be tried.
  void cancel() {
    _reset();
    state = const CodeReceiveState();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final sessionId = _activeSessionId;
    if (sessionId == null || state.isReady) return;

    final deadline = _deadline;
    if (deadline != null && !DateTime.now().isBefore(deadline)) {
      _fail('The code expired before the sender shared the files.');
      return;
    }

    _pollTimer = Timer(pollInterval, () => _pollOnce(sessionId));
  }

  Future<void> _pollOnce(String sessionId) async {
    try {
      final key = await ref
          .read(codeSessionRemoteDataSourceProvider)
          .collectKey(sessionId);
      if (!ref.mounted || _activeSessionId != sessionId) return;

      if (key == null) {
        // Not ready yet: the sender has not wrapped the key.
        _schedulePoll();
        return;
      }

      final delivery = await ref
          .read(keyWrapServiceProvider)
          .unwrapDelivery(
            wrappedBase64: key.wrappedKey,
            privateKeySeed: _privateKeySeed!,
            sessionId: sessionId,
          );
      if (!ref.mounted || _activeSessionId != sessionId) return;

      _pollTimer?.cancel();
      state = state.copyWith(
        isWaiting: false,
        transferId: key.transferId,
        aesKey: delivery.aesKey,
        accessToken: delivery.accessToken,
        viaPairing: !key.isP2p,
      );
    } catch (e) {
      if (!ref.mounted) return;
      _fail(_messageFor(e));
    }
  }

  void _reset() {
    _pollTimer?.cancel();
    _activeSessionId = null;
    _privateKeySeed = null;
    _deadline = null;
  }

  void _fail(String message) {
    _pollTimer?.cancel();
    state = state.copyWith(
      isJoining: false,
      isWaiting: false,
      errorMessage: message,
    );
  }

  String _messageFor(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404) return 'That code is not valid or has expired.';
      if (status == 409)
        return 'That code is already paired with another device.';
    }
    return 'Could not pair with that code. Check it and try again.';
  }
}
