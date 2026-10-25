import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'webrtc_service.dart';

/// Minimal raw-WebSocket surface so [SignalingChannel] is unit-testable
/// without opening a real socket. Production wraps `WebSocketChannel`.
abstract class WebSocketLike {
  Stream<dynamic> get stream;
  void add(dynamic data);
  Future<void> close();
}

/// Signaling WebSocket wrapper for `/ws/signaling/{session_id}`.
///
/// - Outgoing: serializes [SignalingMessage] to the exact wire JSON contract.
/// - Incoming: parses frames leniently — malformed frames surface as
///   [SignalingMessageType.error] messages and never kill the stream
///   (POTENTIAL_ISSUES #1: cross-client message-format drift safety).
class SignalingChannel {
  final WebSocketLike _socket;
  final StreamController<SignalingMessage> _messages =
      StreamController<SignalingMessage>.broadcast();
  late final StreamSubscription<dynamic> _incoming;
  bool _closed = false;

  SignalingChannel(WebSocketLike socket) : _socket = socket {
    _incoming = _socket.stream.listen(
      (frame) {
        if (_messages.isClosed) return;
        final message = frame is String
            ? SignalingMessage.fromRaw(frame)
            : const SignalingMessage(type: SignalingMessageType.error);
        _messages.add(message);
      },
      onError: _messages.addError,
      onDone: () {
        if (!_messages.isClosed) _messages.close();
      },
    );
    // Room history can arrive while TURN lookup and peer init are awaiting.
    // A broadcast controller drops events without listeners, so hold the raw
    // subscription until the coordinator is ready instead of losing the offer.
    _incoming.pause();
    _messages.onListen = () {
      if (_incoming.isPaused) _incoming.resume();
    };
  }

  /// Parsed incoming signaling messages.
  Stream<SignalingMessage> get messages => _messages.stream;

  Future<void> send(SignalingMessage message) async {
    if (_closed) return;
    _socket.add(jsonEncode(message.toJson()));
  }

  /// Sends the room credential as the first frame (#32).
  ///
  /// The backend reads it before the socket joins a room, so it must go out
  /// ahead of any offer or candidate.
  Future<void> sendAuth(String token) async {
    if (_closed) return;
    _socket.add(jsonEncode({'type': 'auth', 'token': token}));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Cancel even if no consumer ever subscribed; closing a paused socket
    // must not wait for its buffered frames to be consumed.
    await _incoming.cancel();
    await _socket.close();
    if (!_messages.isClosed) await _messages.close();
  }
}
