import 'dart:async';
import 'dart:typed_data';

import 'webrtc_service.dart';

/// Which end of the P2P session this device is.
enum PeerRole { sender, receiver }

/// Platform surface the coordinator drives — implemented by the thin
/// `flutter_webrtc` binding so all *decision* logic stays unit-testable.
abstract class PeerActions {
  /// Platform creates an SDP offer (and applies it locally), returning it as
  /// a wire-format [SignalingMessage].
  Future<SignalingMessage> createOffer();

  /// Platform applies a remote offer/answer via `setRemoteDescription`.
  ///
  /// When [msg] is an **offer**, the platform must also create + apply a
  /// local answer and return it — the coordinator forwards it over signaling.
  /// For answers, return `null`.
  Future<SignalingMessage?> handleRemoteDescription(SignalingMessage msg);

  /// Platform adds one remote ICE candidate.
  Future<void> addIceCandidate(Map<String, dynamic> candidate);

  /// Coordinator's outbound path onto the signaling WebSocket.
  Future<void> sendSignaling(SignalingMessage message);
}

/// Orchestrates the WebRTC signaling dance and the 8-second
/// connect-timeout  R2-fallback contract (Phases.md / POTENTIAL_ISSUES #6).
///
/// Pure orchestration only — no plugin types. The platform layer reports
/// lifecycle via [notifyConnected] and file bytes flow separately through
/// [ChunkSender]/[ChunkCollector].
class WebrtcPeerCoordinator {
  final PeerActions actions;
  final Duration connectTimeout;
  void Function()? onP2PFailed;

  PeerRole? role;
  SignalingMessageType get state => _controller.state;

  late final P2PConnectionController _controller;
  bool _disposed = false;
  bool armConnectionTimeoutDone = false;
  bool _armOnCandidateDone = false;

  WebrtcPeerCoordinator({
    required this.actions,
    this.connectTimeout = P2PConnectionController.defaultTimeout,
    this.onP2PFailed,
  }) {
    _controller = P2PConnectionController(connectTimeout: connectTimeout)
      ..onP2PFailed = () => onP2PFailed?.call();
  }

  /// Begins the session. The **sender** immediately creates and signals its
  /// offer; the receiver waits for the remote offer.
  ///
  /// [armConnectionTimeout]: when false (patient sender waiting for a QR
  /// scan), the 8-second fuse is NOT started here — call [armTimeout] once
  /// the remote answer arrives so the fuse only covers real negotiation.
  Future<void> start({
    required PeerRole role,
    bool armConnectionTimeout = true,
  }) async {
    if (_disposed) return;
    this.role = role;
    if (armConnectionTimeout) _controller.beginConnecting();

    if (role == PeerRole.sender) {
      await actions.sendSignaling(await actions.createOffer());
    }
  }

  /// Starts (or restarts) the connection timeout fuse.
  void armTimeout() => _controller.beginConnecting();

  /// Routes one inbound signaling message to the right platform action.
  ///
  /// Unknown/error messages are ignored safely (never throws).
  Future<void> handleMessage(SignalingMessage message) async {
    if (_disposed) return;

    switch (message.type) {
      case SignalingMessageType.offer:
      case SignalingMessageType.answer:
        final answer = await actions.handleRemoteDescription(message);
        if (!armConnectionTimeoutDone &&
            (message.type == SignalingMessageType.answer ||
                message.type == SignalingMessageType.offer)) {
          armConnectionTimeoutDone = true;
          _controller.beginConnecting();
        }
        if (answer != null && !_disposed) {
          await actions.sendSignaling(answer);
        }
      case SignalingMessageType.candidate:
        if (!_armOnCandidateDone) {
          _armOnCandidateDone = true;
          _controller.beginConnecting();
        }
        if (message.candidate != null) {
          await actions.addIceCandidate(message.candidate!);
        }
      case SignalingMessageType.error:
      case SignalingMessageType.idle:
      case SignalingMessageType.connecting:
      case SignalingMessageType.connected:
      case SignalingMessageType.failed:
        break;
    }
  }

  /// Platform calls once the DataChannel actually opens.
  void notifyConnected() => _controller.markConnected();

  /// True when the timeout already fired (caller should fall back to R2).
  bool get hasFailed => _controller.state == SignalingMessageType.failed;

  void dispose() {
    _disposed = true;
    _controller.dispose();
  }
}

/// Receiver-side reassembly of ordered DataChannel chunks.
class ChunkCollector {
  final BytesBuilder _builder = BytesBuilder(copy: true);
  int _receivedBytes = 0;
  int _chunkCount = 0;
  bool _closed = false;

  int get receivedBytes => _receivedBytes;
  int get chunkCount => _chunkCount;

  void add(Uint8List chunk) {
    if (_closed) {
      throw StateError('ChunkCollector already closed');
    }
    if (chunk.isEmpty) return;
    _builder.add(chunk);
    _receivedBytes += chunk.length;
    _chunkCount++;
  }

  /// Finalizes and returns the complete payload.
  Future<Uint8List> close() async {
    _closed = true;
    return _builder.toBytes();
  }
}
