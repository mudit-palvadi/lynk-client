/// WebRTC P2P transfer core contracts.
///
/// Pure-Dart state machines and wire-format models so the signaling,
/// timeout-fallback and backpressure logic is unit-testable without the
/// native `flutter_webrtc` plugin. The platform binding layer (real
/// `RTCPeerConnection` / `RTCDataChannel` wiring) wraps these classes.
library;

import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode;

/// Message types on the signaling WebSocket (`/ws/signaling/{session_id}`).
enum SignalingMessageType {
  idle,
  offer,
  answer,
  candidate,
  error,
  connecting,
  connected,
  failed,
}

/// Wire-format model shared by Flutter clients and browser receivers.
///
/// Exact JSON key sets (cross-language contract, see POTENTIAL_ISSUES #1):
/// - offer:   `{type, sdp}`
/// - answer:  `{type, sdp}`
/// - candidate: `{type, candidate:{candidate, sdpMid?, sdpMLineIndex?}}`
class SignalingMessage {
  final SignalingMessageType type;
  final String? sdp;
  final Map<String, dynamic>? candidate;

  const SignalingMessage({required this.type, this.sdp, this.candidate});

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'offer':
        return SignalingMessage(
          type: SignalingMessageType.offer,
          sdp: json['sdp'] as String?,
        );
      case 'answer':
        return SignalingMessage(
          type: SignalingMessageType.answer,
          sdp: json['sdp'] as String?,
        );
      case 'candidate':
        final raw = json['candidate'];
        return SignalingMessage(
          type: SignalingMessageType.candidate,
          candidate: raw is Map<String, dynamic> ? raw : null,
        );
      default:
        // Unknown or missing type must never throw (receiver-side safety).
        return const SignalingMessage(type: SignalingMessageType.error);
    }
  }

  /// Lenient parse of a raw WebSocket text frame.
  factory SignalingMessage.fromRaw(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? SignalingMessage.fromJson(value)
          : const SignalingMessage(type: SignalingMessageType.error);
    } catch (_) {
      return const SignalingMessage(type: SignalingMessageType.error);
    }
  }

  Map<String, dynamic> toJson() => switch (type) {
    SignalingMessageType.offer ||
    SignalingMessageType.answer => {'type': type.name, 'sdp': sdp},
    SignalingMessageType.candidate => {
      'type': type.name,
      'candidate': candidate,
    },
    _ => {'type': type.name},
  };
}

/// Connection lifecycle controller with the 8-second P2P timeout contract.
///
/// If the DataChannel has not connected within [connectTimeout], the state
/// transitions to [SignalingMessageType.failed] and [onP2PFailed] fires once
/// so the caller can fall back to the R2 cloud pipeline.
class P2PConnectionController {
  /// Per Phases.md: 8 seconds from connection initiation.
  static const Duration defaultTimeout = Duration(seconds: 8);

  final Duration connectTimeout;
  void Function()? onP2PFailed;

  SignalingMessageType _state = SignalingMessageType.idle;
  Timer? _timer;
  bool _disposed = false;

  P2PConnectionController({this.connectTimeout = defaultTimeout});

  SignalingMessageType get state => _state;

  void beginConnecting() {
    if (_disposed || _state == SignalingMessageType.connected) return;
    _state = SignalingMessageType.connecting;
    _timer?.cancel();
    _timer = Timer(connectTimeout, _onTimeout);
  }

  void markConnected() {
    _timer?.cancel();
    _timer = null;
    if (!_disposed && _state != SignalingMessageType.failed) {
      _state = SignalingMessageType.connected;
    }
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    if (!_disposed) _state = SignalingMessageType.idle;
  }

  void _onTimeout() {
    _timer = null;
    if (_disposed || _state == SignalingMessageType.connected) return;
    _state = SignalingMessageType.failed;
    onP2PFailed?.call();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// `bufferedAmount` flow control for the file-transfer DataChannel.
///
/// Pause sending above [highWaterMark] (1 MB per Phases.md) and only resume
/// once the buffer drains below [resumeWaterMark] — prevents receiver-side
/// chunk drops on congested links (see POTENTIAL_ISSUES #5).
class BackpressureController {
  final int highWaterMark;
  final int resumeWaterMark;

  bool _paused = false;

  BackpressureController({
    this.highWaterMark = 1 * 1024 * 1024,
    this.resumeWaterMark = 256 * 1024,
  }) : assert(
         resumeWaterMark > 0 && resumeWaterMark < highWaterMark,
         'resume mark must be in (0, highWaterMark)',
       ),
       assert(highWaterMark > 0, 'high water mark must be positive');

  bool get isPaused => _paused;

  /// Whether a send is permitted given the current `bufferedAmount`.
  ///
  /// Exactly at [highWaterMark] is still allowed; only strictly greater
  /// values trigger the pause.
  bool canSend(int bufferedAmount) {
    if (_paused) {
      if (bufferedAmount <= resumeWaterMark) {
        _paused = false;
        return true;
      }
      return false;
    }
    if (bufferedAmount > highWaterMark) {
      _paused = true;
      return false;
    }
    return true;
  }
}

/// A half-open byte range `[start, end)` of one encrypted sub-chunk.
class ChunkOffset {
  final int start;
  final int end;

  const ChunkOffset(this.start, this.end);
}

/// Splits [totalLength] bytes into consecutive ranges of [chunkSize].
///
/// An exact multiple produces no empty tail chunk.
List<ChunkOffset> chunkOffsets(int totalLength, int chunkSize) {
  assert(chunkSize > 0, 'chunkSize must be positive');
  final offsets = <ChunkOffset>[];
  var start = 0;
  while (start < totalLength) {
    final end = (start + chunkSize) > totalLength
        ? totalLength
        : start + chunkSize;
    offsets.add(ChunkOffset(start, end));
    start = end;
  }
  return offsets;
}

/// Platform-binding surface. The native `flutter_webrtc` wiring lands here;
/// all policy decisions stay in the pure classes above.
abstract class WebrtcService {
  /// Encrypted sub-chunk size over the DataChannel (per Phases.md).
  static const int chunkSize = 64 * 1024;

  /// DataChannel label agreed by sender and receiver.
  static const String dataChannelLabel = 'fileTransfer';
}
