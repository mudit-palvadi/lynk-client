import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/file_receive/domain/entities/receiver_session.dart';
import '../services/key_wrap_service.dart';
import 'receiver_providers.dart';

part 'receiver_notifier.g.dart';

class ReceiverState {
  final ReceiverSession? session;
  final bool isPolling;
  final String? attachedTransferId;

  /// Plaintext AES key recovered in memory after unwrapping the delivered
  /// `wrapped_key`. Never persisted, never sent over the network.
  final String? attachedAesKey;

  /// Access token recovered from a v2 wrap. Memory only.
  final String? attachedAccessToken;
  final String? errorMessage;
  final bool isPausedForBackground;

  /// Ephemeral X25519 key material for this session (memory-only).
  final String? receiverPublicKeyB64;
  final Uint8List? receiverPrivateKeySeed;

  const ReceiverState({
    this.session,
    this.isPolling = false,
    this.attachedTransferId,
    this.attachedAesKey,
    this.attachedAccessToken,
    this.errorMessage,
    this.isPausedForBackground = false,
    this.receiverPublicKeyB64,
    this.receiverPrivateKeySeed,
  });

  ReceiverState copyWith({
    ReceiverSession? session,
    bool? isPolling,
    String? attachedTransferId,
    String? attachedAesKey,
    String? attachedAccessToken,
    String? errorMessage,
    bool? isPausedForBackground,
    String? receiverPublicKeyB64,
    Uint8List? receiverPrivateKeySeed,
  }) {
    return ReceiverState(
      session: session ?? this.session,
      isPolling: isPolling ?? this.isPolling,
      attachedTransferId: attachedTransferId ?? this.attachedTransferId,
      attachedAesKey: attachedAesKey ?? this.attachedAesKey,
      attachedAccessToken: attachedAccessToken ?? this.attachedAccessToken,
      errorMessage: errorMessage ?? this.errorMessage,
      isPausedForBackground:
          isPausedForBackground ?? this.isPausedForBackground,
      receiverPublicKeyB64: receiverPublicKeyB64 ?? this.receiverPublicKeyB64,
      receiverPrivateKeySeed:
          receiverPrivateKeySeed ?? this.receiverPrivateKeySeed,
    );
  }
}

@riverpod
class ReceiverNotifier extends _$ReceiverNotifier with WidgetsBindingObserver {
  Timer? _pollingTimer;
  int _pollCount = 0;
  String? _activeSessionId;

  /// Tests poll immediately. Production keeps the backoff below.
  @visibleForTesting
  Duration? pollDelayOverride;

  @override
  ReceiverState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _pollingTimer?.cancel();
    });
    return const ReceiverState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_activeSessionId == null || this.state.attachedTransferId != null) {
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pollingTimer?.cancel();
      this.state = this.state.copyWith(
        isPolling: false,
        isPausedForBackground: true,
      );
    } else if (state == AppLifecycleState.resumed) {
      this.state = this.state.copyWith(
        isPolling: true,
        isPausedForBackground: false,
      );
      _pollCount = 0;
      _scheduleNextPoll(_activeSessionId!);
    }
  }

  Future<void> createSession() async {
    _pollingTimer?.cancel();
    _activeSessionId = null;
    state = const ReceiverState(isPolling: true);
    _pollCount = 0;

    String? publicKeyB64;
    Uint8List? privateKeySeed;
    try {
      final pair = await ref
          .read(keyWrapServiceProvider)
          .generateReceiverKeyPair();
      publicKeyB64 = pair.publicKeyB64;
      privateKeySeed = pair.privateKeySeed;
    } catch (_) {
      publicKeyB64 = null;
      privateKeySeed = null;
    }

    final repo = ref.read(receiverRepositoryProvider);
    final result = await repo.createReceiverSession();

    result.fold(
      (session) {
        _activeSessionId = session.id;
        state = state.copyWith(
          session: session,
          isPolling: true,
          receiverPublicKeyB64: publicKeyB64,
          receiverPrivateKeySeed: privateKeySeed,
        );
        _scheduleNextPoll(session.id);
      },
      (failure) {
        state = state.copyWith(isPolling: false, errorMessage: failure.message);
      },
    );
  }

  void _scheduleNextPoll(String sessionId) {
    _pollingTimer?.cancel();
    if (_activeSessionId != sessionId || state.attachedTransferId != null) {
      return;
    }

    final Duration delay =
        pollDelayOverride ??
        (_pollCount < 10
            ? const Duration(seconds: 2)
            : (_pollCount < 30
                  ? const Duration(seconds: 4)
                  : const Duration(seconds: 6)));

    _pollingTimer = Timer(delay, () async {
      if (_activeSessionId != sessionId || state.attachedTransferId != null) {
        return;
      }

      _pollCount++;
      final repo = ref.read(receiverRepositoryProvider);
      final result = await repo.getReceiverSession(sessionId);

      result.fold(
        (session) async {
          if (_activeSessionId != sessionId) return;
          if (session.status == ReceiverSessionStatus.attached &&
              session.transferId != null) {
            _pollingTimer?.cancel();

            String? unwrappedKey;
            String? unwrappedToken;
            if (session.wrappedKey != null &&
                session.wrappedKey!.isNotEmpty &&
                state.receiverPrivateKeySeed != null) {
              try {
                final delivery = await ref
                    .read(keyWrapServiceProvider)
                    .unwrapDelivery(
                      wrappedBase64: session.wrappedKey!,
                      privateKeySeed: state.receiverPrivateKeySeed!,
                      sessionId: sessionId,
                    );
                unwrappedKey = delivery.aesKey;
                unwrappedToken = delivery.accessToken;
              } catch (_) {
                unwrappedKey = null;
              }
            }
            if (_activeSessionId != sessionId) return;

            state = state.copyWith(
              isPolling: false,
              attachedTransferId: session.transferId,
              attachedAesKey: unwrappedKey,
              attachedAccessToken: unwrappedToken,
            );
          } else {
            _scheduleNextPoll(sessionId);
          }
        },
        (_) {
          _scheduleNextPoll(sessionId);
        },
      );
    });
  }

  void cancelSession() {
    _pollingTimer?.cancel();
    final currentSession = state.session;
    _activeSessionId = null;
    if (currentSession != null) {
      ref
          .read(receiverRepositoryProvider)
          .cancelReceiverSession(currentSession.id);
    }
    state = const ReceiverState();
  }
}
