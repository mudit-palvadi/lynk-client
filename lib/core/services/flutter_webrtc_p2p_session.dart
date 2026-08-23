import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'chunk_sender.dart';
import 'ice_ladder.dart';
import 'signaling_channel.dart';
import 'transfer_framer.dart';
import 'webrtc_peer.dart';
import 'webrtc_service.dart';

/// Legacy alias kept for callers that only need STUN.
const List<Map<String, String>> kLynkIceServers = kStunServers;

/// Fetches short-lived TURN credentials from the backend. Returns null when
/// TURN is disabled, unreachable, or the response is malformed — the caller
/// then degrades to STUN-only (transfer still succeeds via R2 fallback).
Future<({List<String> urls, String username, String credential})?>
fetchTurnCredentials(String sessionId, {Dio? dio}) async {
  try {
    final base =
        dotenv.env['API_BASE_URL'] ?? 'http://140.245.220.117:8000/api/v1/';
    final client = dio ?? Dio();
    final resp = await client.getUri(
      Uri.parse(base).resolve('transfers/$sessionId/turn-credentials'),
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    final body = resp.data;
    if (body is! Map || body['enabled'] != true) return null;
    final urls = (body['urls'] as List?)?.cast<String>() ?? const [];
    final username = body['username'] as String? ?? '';
    final credential = body['credential'] as String? ?? '';
    if (urls.isEmpty || username.isEmpty || credential.isEmpty) return null;
    return (urls: urls, username: username, credential: credential);
  } catch (_) {
    return null;
  }
}

/// Adapts `web_socket_channel`'s channel to the testable [WebSocketLike].
class WebSocketChannelAdapter implements WebSocketLike {
  final WebSocketChannel _channel;

  WebSocketChannelAdapter(this._channel);

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void add(dynamic data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}

/// Thin `flutter_webrtc` glue implementing [PeerActions]. All decision logic
/// lives in [WebrtcPeerCoordinator]; this class only translates calls.
class FlutterWebrtcPeerActions implements PeerActions {
  final SignalingChannel signaling;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;

  FlutterWebrtcPeerActions({required this.signaling});

  /// Creates the peer connection and the `fileTransfer` DataChannel.
  ///
  /// The sender owns the channel; the receiver picks it up via
  /// `onDataChannel`. Returns the platform callbacks surface.
  Future<RTCPeerConnection> init({
    required List<Map<String, Object>> iceServers,
    required void Function(RTCDataChannel channel) onDataChannelOpen,
    required void Function(Uint8List bytes) onBinaryMessage,
    required void Function(String text) onTextMessage,
    required void Function(RTCIceCandidate candidate) onLocalCandidate,
  }) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        onLocalCandidate(candidate);
      }
    };

    pc.onDataChannel = (channel) {
      _bindDataChannel(
        channel,
        onDataChannelOpen,
        onBinaryMessage,
        onTextMessage,
      );
    };

    // Sender-side: proactively create the labeled channel.
    final init = RTCDataChannelInit()
      ..ordered = true
      ..binaryType = 'binary';
    final channel = await pc.createDataChannel(
      WebrtcService.dataChannelLabel,
      init,
    );
    _bindDataChannel(
      channel,
      onDataChannelOpen,
      onBinaryMessage,
      onTextMessage,
    );

    _pc = pc;
    return pc;
  }

  void _bindDataChannel(
    RTCDataChannel channel,
    void Function(RTCDataChannel) onOpen,
    void Function(Uint8List) onBinary,
    void Function(String) onText,
  ) {
    if (channel.label != WebrtcService.dataChannelLabel) return;
    _dataChannel = channel;
    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        onBinary(message.binary);
      } else {
        onText(message.text);
      }
    };
    channel.stateChangeStream.listen((_) {
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
        onOpen(channel);
      }
    });
  }

  bool get isChannelOpen =>
      _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  int get bufferedAmount {
    final buffered = _dataChannel?.bufferedAmount;
    return buffered ?? 0;
  }

  Future<void> sendBinary(Uint8List bytes) async {
    await _dataChannel?.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  Future<void> sendText(String text) async {
    await _dataChannel?.send(RTCDataChannelMessage(text));
  }

  @override
  Future<SignalingMessage> createOffer() async {
    final pc = _pc!;
    final desc = await pc.createOffer({});
    await pc.setLocalDescription(desc);
    return SignalingMessage(type: SignalingMessageType.offer, sdp: desc.sdp);
  }

  @override
  Future<SignalingMessage?> handleRemoteDescription(
    SignalingMessage msg,
  ) async {
    final pc = _pc!;
    if (msg.type == SignalingMessageType.offer) {
      await pc.setRemoteDescription(RTCSessionDescription(msg.sdp!, 'offer'));
      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);
      return SignalingMessage(
        type: SignalingMessageType.answer,
        sdp: answer.sdp,
      );
    }
    // Answer from the remote peer.
    if (msg.sdp != null) {
      await pc.setRemoteDescription(RTCSessionDescription(msg.sdp!, 'answer'));
    }
    return null;
  }

  @override
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    await _pc?.addCandidate(
      RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ),
    );
  }

  @override
  Future<void> sendSignaling(SignalingMessage message) =>
      signaling.send(message);

  Future<void> dispose() async {
    await _dataChannel?.close();
    await _pc?.close();
    _pc = null;
    _dataChannel = null;
  }
}

/// High-level P2P file-transfer session over WebRTC.
///
/// Sender flow: [startAsSender] → wait for channel open → [sendFiles]
/// Receiver flow: [startAsReceiver] → chunks arrive via [_incomingFile] →
/// completed temp files surfaced by [onFileReceived] / completion future.
class P2PFileSession {
  final SignalingChannel signaling;
  final FlutterWebrtcPeerActions peer;
  late final WebrtcPeerCoordinator coordinator;

  /// Fires when the 8-second connect timeout expires without a DataChannel.
  void Function()? onFallbackToCloud;

  /// Fires for each fully received file (temp path holds encrypted bytes).
  final StreamController<File> _fileReceived =
      StreamController<File>.broadcast();

  File? _currentInboundFile;
  RandomAccessFile? _currentSink;
  final Completer<void> _transferDone = Completer<void>();

  P2PFileSession._(this.signaling, this.peer) {
    coordinator = WebrtcPeerCoordinator(actions: peer)
      ..onP2PFailed = () {
        onFallbackToCloud?.call();
      };
  }

  static Future<P2PFileSession> connect({
    required Uri signalingUrl,
    required PeerRole role,
    required String sessionId,
    void Function()? onFallbackToCloud,
  }) async {
    final socket = WebSocketChannel.connect(signalingUrl);
    final signaling = SignalingChannel(WebSocketChannelAdapter(socket));
    final peer = FlutterWebrtcPeerActions(signaling: signaling);
    final session = P2PFileSession._(signaling, peer)
      ..onFallbackToCloud = onFallbackToCloud;

    // STUN -> TURN ladder: TURN creds come from the backend at session time
    // (short-lived HMAC), so a leaked credential self-expires. Any failure
    // here silently degrades to STUN-only.
    final turn = await fetchTurnCredentials(sessionId);
    final iceServers = buildIceServers(
      turnEnabled: turn != null,
      urls: turn?.urls ?? const [],
      username: turn?.username ?? '',
      credential: turn?.credential ?? '',
    );

    await peer.init(
      iceServers: iceServers,
      onDataChannelOpen: (_) => session.coordinator.notifyConnected(),
      onBinaryMessage: session._onBinary,
      onTextMessage: session._onText,
      onLocalCandidate: (candidate) => signaling.send(
        SignalingMessage(
          type: SignalingMessageType.candidate,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      ),
    );

    signaling.messages.listen(session.coordinator.handleMessage);
    await session.coordinator.start(role: role);

    // Safety net: close the whole stack once the fallback fires.
    session.coordinator.onP2PFailed = () {
      onFallbackToCloud?.call();
      if (!session._transferDone.isCompleted) {
        session._transferDone.completeError(
          const SocketException('P2P connect timeout'),
        );
      }
    };
    return session;
  }

  bool get isReady => peer.isChannelOpen;

  /// Streams already-encrypted files over the DataChannel with framing.
  ///
  /// Returns when the receiver acknowledged everything (`done`) or the
  /// channel died. Each file must be the *encrypted* payload (IV-prefixed).
  Future<void> sendFiles(List<File> encryptedFiles) async {
    while (!peer.isChannelOpen) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final sender = ChunkSender(
      bufferedAmount: () => peer.bufferedAmount,
      send: peer.sendBinary,
    );

    for (final file in encryptedFiles) {
      final name = file.path.split(Platform.pathSeparator).last;
      final size = await file.length();
      await peer.sendText(
        TransferFramer.encodeHeader(
          FramedFileMeta(name: name, size: size),
        ).text!,
      );
      await file.openRead().forEach((chunkBytes) async {
        await sender.sendAll(Uint8List.fromList(chunkBytes));
      });
      await peer.sendText(
        TransferFramer.encodeEof(FramedFileMeta(name: name, size: 0)).text!,
      );
    }
    await peer.sendText(TransferFramer.encodeDone().text!);
  }

  Stream<File> get onFileReceived => _fileReceived.stream;

  /// Completes when the sender signals overall completion.
  Future<void> get transferDone => _transferDone.future;

  Directory? _tempDir;

  void _ensureTempDir() {
    _tempDir ??= Directory.systemTemp.createTempSync('lynk_p2p_');
  }

  void _onText(String text) {
    final parsed = TransferFramer.parseText(text);
    if (parsed == null) return;
    switch (parsed.kind) {
      case FrameKind.header:
        _ensureTempDir();
        _currentInboundFile = File(
          '${_tempDir!.path}/${DateTime.now().microsecondsSinceEpoch}_${parsed.meta!.name}',
        );
        _currentSink = _currentInboundFile!.openSync(mode: FileMode.write);
      case FrameKind.eof:
        _currentSink?.closeSync();
        final file = _currentInboundFile;
        if (file != null && !_fileReceived.isClosed) {
          _fileReceived.add(file);
        }
        _currentInboundFile = null;
        _currentSink = null;
      case FrameKind.done:
        if (!_transferDone.isCompleted) _transferDone.complete();
    }
  }

  void _onBinary(Uint8List bytes) {
    final sink = _currentSink;
    if (sink == null) return; // binary before header → drop
    sink.writeFromSync(bytes);
  }

  /// Tears down PC, channels and any partially written inbound file.
  Future<void> dispose() async {
    try {
      await _currentSink?.close();
    } catch (_) {}
    _currentSink = null;
    if (!_transferDone.isCompleted) {
      _transferDone.completeError(const SocketException('P2P disposed'));
    }
    await _fileReceived.close();
    coordinator.dispose();
    await peer.dispose();
    await signaling.close();
  }
}
