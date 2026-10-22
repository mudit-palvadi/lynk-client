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
import '../utils/file_name_sanitizer.dart';

/// Legacy alias kept for callers that only need STUN.
const List<Map<String, String>> kLynkIceServers = kStunServers;

/// The most a peer may send in one transfer.
///
/// The largest device-to-device transfer the app offers is the unlocked
/// 50 MB tier, plus a little for the per-file encryption overhead (a 16-byte
/// IV and up to 16 bytes of padding for every file).
const int maxP2PReceiveBytes = 50 * 1024 * 1024 + 1024;

/// Whether [receivedBytes] may still be accepted.
///
/// A peer may not send more than it declared ([declaredBytes]), and no
/// transfer may be larger than the biggest one the app offers ([maxBytes]).
bool isWithinReceiveLimit({
  required int receivedBytes,
  required int declaredBytes,
  required int maxBytes,
}) =>
    receivedBytes <= declaredBytes && receivedBytes <= maxBytes;

/// Fetches short-lived TURN credentials from the backend. Returns null when
/// TURN is disabled, unreachable, or the response is malformed -- the caller
/// then degrades to STUN-only (transfer still succeeds via R2 fallback).
Future<({List<String> urls, String username, String credential})?>
fetchTurnCredentials(String sessionId, {Dio? dio}) async {
  try {
    final base =
        dotenv.env['API_BASE_URL'] ?? 'https://api.lynkshare.app/api/v1/';
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

/// Sender-side handle used by the upload flow. Abstract so the notifier is
/// unit-testable without the native WebRTC plugin.
abstract class P2PSenderSession {
  bool get isOpen;

  /// Resolves once the DataChannel is open. Throws [TimeoutException] when
  /// [timeout] elapses first, or [SocketException] on cancel/failure.
  Future<void> waitUntilOpen({required Duration timeout});

  /// Breaks a pending [waitUntilOpen] immediately (user chose cloud / cancel).
  void cancelWait();

  Future<void> sendFiles(
    List<File> files, {
    void Function(int totalBytesSent)? onProgress,
    bool Function()? shouldAbort,
  });

  Future<void> dispose();
}

/// A fully received file plus its original name (no path-derived guessing).
class ReceivedFile {
  final File file;
  final String name;
  final int expectedSize;
  const ReceivedFile({
    required this.file,
    required this.name,
    required this.expectedSize,
  });
}

/// Thin `flutter_webrtc` glue implementing [PeerActions]. All decision logic
/// lives in [WebrtcPeerCoordinator]; this class only translates calls.
class FlutterWebrtcPeerActions implements PeerActions {
  final SignalingChannel signaling;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;

  FlutterWebrtcPeerActions({required this.signaling});

  /// Creates the peer connection. Only the SENDER creates the DataChannel --
  /// the receiver receives it via `onDataChannel`.
  Future<RTCPeerConnection> init({
    required PeerRole role,
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

    if (role == PeerRole.sender) {
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
    }

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
/// Sender flow: [connectAsSender] -> [waitUntilOpen] -> [sendFiles].
/// Receiver flow: chunks arrive via [_onBinary]/[_onText]; completed files
/// surface on [onFileReceived] and completion via [transferDone].
class P2PFileSession implements P2PSenderSession {
  final SignalingChannel signaling;
  final FlutterWebrtcPeerActions peer;
  late final WebrtcPeerCoordinator coordinator;

  /// Fires when the connect timeout expires without a DataChannel.
  void Function()? onFallbackToCloud;

  final StreamController<ReceivedFile> _fileReceived =
      StreamController<ReceivedFile>.broadcast();
  final Completer<void> _transferDone = Completer<void>();
  final Completer<void> _waitCancelled = Completer<void>();

  File? _currentInboundFile;
  RandomAccessFile? _currentSink;
  String? _currentName;
  int _currentExpected = 0;
  int _currentWritten = 0;
  Directory? _tempDir;

  P2PFileSession._(this.signaling, this.peer) {
    coordinator = WebrtcPeerCoordinator(actions: peer);
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

    final turn = await fetchTurnCredentials(sessionId);
    final iceServers = buildIceServers(
      turnEnabled: turn != null,
      urls: turn?.urls ?? const [],
      username: turn?.username ?? '',
      credential: turn?.credential ?? '',
    );

    await peer.init(
      role: role,
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
    await session.coordinator.start(
      role: role,
      armConnectionTimeout: role == PeerRole.receiver,
    );

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

  /// Sender-side factory matching [P2PSenderSessionFactory].
  static Future<P2PFileSession> connectAsSender({
    required Uri signalingUrl,
    required String sessionId,
    required void Function() onFallbackToCloud,
  }) => connect(
    signalingUrl: signalingUrl,
    role: PeerRole.sender,
    sessionId: sessionId,
    onFallbackToCloud: onFallbackToCloud,
  );

  @override
  bool get isOpen => peer.isChannelOpen;

  bool get hasFailed => coordinator.hasFailed;

  @override
  Future<void> waitUntilOpen({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (!peer.isChannelOpen) {
      if (_waitCancelled.isCompleted) {
        throw const SocketException('P2P wait cancelled');
      }
      if (hasFailed) {
        throw TimeoutException('P2P connection failed');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('DataChannel did not open in time');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  void cancelWait() {
    if (!_waitCancelled.isCompleted) _waitCancelled.complete();
  }

  /// Streams already-encrypted files over the DataChannel with framing.
  ///
  /// Each file must be the *encrypted* payload (IV-prefixed). Chunks are read
  /// with `await for` so ordering is guaranteed and backpressure honored.
  @override
  Future<void> sendFiles(
    List<File> encryptedFiles, {
    void Function(int totalBytesSent)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    if (!peer.isChannelOpen) {
      throw StateError('DataChannel is not open');
    }
    final abort = shouldAbort;
    var cumulative = 0;
    for (final file in encryptedFiles) {
      if (abort != null && abort()) {
        throw const SocketException('P2P send aborted');
      }
      final name = file.path.split(Platform.pathSeparator).last;
      final size = await file.length();
      await peer.sendText(
        TransferFramer.encodeHeader(
          FramedFileMeta(name: name, size: size),
        ).text!,
      );
      final sender = ChunkSender(
        bufferedAmount: () => peer.bufferedAmount,
        send: peer.sendBinary,
        onProgress: (fileSent) => onProgress?.call(cumulative + fileSent),
        shouldAbort: shouldAbort,
      );
      await for (final chunkBytes in file.openRead()) {
        await sender.sendAll(Uint8List.fromList(chunkBytes));
      }
      cumulative += size;
      await peer.sendText(
        TransferFramer.encodeEof(FramedFileMeta(name: name, size: 0)).text!,
      );
    }
    await peer.sendText(TransferFramer.encodeDone().text!);
  }

  Stream<ReceivedFile> get onFileReceived => _fileReceived.stream;

  /// Completes when the sender signals overall completion.
  Future<void> get transferDone => _transferDone.future;

  void _ensureTempDir() {
    _tempDir ??= Directory.systemTemp.createTempSync('lynk_p2p_');
  }

  void _onText(String text) {
    final parsed = TransferFramer.parseText(text);
    if (parsed == null) return;
    switch (parsed.kind) {
      case FrameKind.header:
        _ensureTempDir();
        _currentName = parsed.meta!.name;
        _currentExpected = parsed.meta!.size;
        _currentWritten = 0;
        _currentInboundFile = File(
          '${_tempDir!.path}/'
          // The name comes from the peer, so it is reduced to a single safe
          // path segment before it is joined onto the temp directory.
          '${DateTime.now().microsecondsSinceEpoch}_'
          '${FileNameSanitizer.safeFileName(parsed.meta!.name)}',
        );
        _currentSink = _currentInboundFile!.openSync(mode: FileMode.write);
      case FrameKind.eof:
        _currentSink?.closeSync();
        final file = _currentInboundFile;
        final name = _currentName ?? '';
        if (file != null && _currentWritten == _currentExpected) {
          if (!_fileReceived.isClosed) {
            _fileReceived.add(
              ReceivedFile(
                file: file,
                name: name,
                expectedSize: _currentExpected,
              ),
            );
          }
        } else {
          // Size mismatch means a corrupt transfer: drop temp and fail fast.
          try {
            file?.deleteSync();
          } catch (_) {}
          if (!_transferDone.isCompleted) {
            _transferDone.completeError(
              SocketException('size mismatch for "$name"'),
            );
          }
        }
        _currentInboundFile = null;
        _currentSink = null;
        _currentName = null;
        _currentWritten = 0;
      case FrameKind.done:
        if (!_transferDone.isCompleted) _transferDone.complete();
    }
  }

  void _onBinary(Uint8List bytes) {
    final sink = _currentSink;
    if (sink == null) return;
    // A peer may not send more than it declared, and a transfer may not be
    // bigger than the largest one the app offers. Without this a peer could
    // fill the device's disk.
    if (!isWithinReceiveLimit(
      receivedBytes: _currentWritten + bytes.length,
      declaredBytes: _currentExpected,
      maxBytes: maxP2PReceiveBytes,
    )) {
      _abortReceive("the peer sent more data than it declared");
      return;
    }
    sink.writeFromSync(bytes);
    _currentWritten += bytes.length;
  }

  /// Stops a transfer that broke the size rules.
  void _abortReceive(String reason) {
    try {
      _currentSink?.closeSync();
    } catch (_) {}
    _currentSink = null;
    final file = _currentInboundFile;
    _currentInboundFile = null;
    try {
      file?.deleteSync();
    } catch (_) {}
    _currentName = null;
    _currentExpected = 0;
    _currentWritten = 0;
    if (!_transferDone.isCompleted) {
      _transferDone.completeError(SocketException(reason));
    }
  }

  /// Tears down PC, channels, pending files and the whole temp directory.
  @override
  Future<void> dispose() async {
    cancelWait();
    try {
      await _currentSink?.close();
    } catch (_) {}
    _currentSink = null;
    if (!_transferDone.isCompleted) {
      _transferDone.completeError(const SocketException('P2P disposed'));
    }
    try {
      _tempDir?.deleteSync(recursive: true);
    } catch (_) {}
    _tempDir = null;
    await _fileReceived.close();
    coordinator.dispose();
    await peer.dispose();
    await signaling.close();
  }
}
