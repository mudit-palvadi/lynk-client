import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'p2p_delivery_sender.dart';
import 'ice_ladder.dart';
import 'name_sealer.dart';
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
}) => receivedBytes <= declaredBytes && receivedBytes <= maxBytes;

/// How long an open channel may stay silent before the receive is given up.
///
/// The sender encrypts everything before the channel opens and then streams
/// without pausing, so a gap this long means the link is gone (#52).
const Duration p2pReceiveIdleTimeout = Duration(seconds: 30);

/// Whether a data channel in [state] can no longer carry the transfer.
bool isDeadChannelState(RTCDataChannelState? state) =>
    state == RTCDataChannelState.RTCDataChannelClosing ||
    state == RTCDataChannelState.RTCDataChannelClosed;

/// Whether a peer connection in [state] can no longer carry the transfer.
///
/// `disconnected` can still recover, so it is left to the idle timeout.
bool isDeadConnectionState(RTCPeerConnectionState? state) =>
    state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
    state == RTCPeerConnectionState.RTCPeerConnectionStateClosed;

/// Ends a receive whose link died after the channel opened (#52).
///
/// The connect fuse only covers the handshake. Once the channel is open,
/// a closed channel, a failed connection or a silent channel must each end
/// the receive, or the receiver waits forever and never reaches the R2 copy.
class ReceiveWatchdog {
  ReceiveWatchdog({required this.idleTimeout, required this.onLost});

  final Duration idleTimeout;
  final void Function(String reason) onLost;
  Timer? _timer;
  bool _armed = false;
  bool _stopped = false;

  /// Starts the idle timer. Called once the channel is open.
  void start() {
    if (_stopped) return;
    _armed = true;
    _reset();
  }

  /// Records a frame from the peer.
  void activity() {
    if (_armed && !_stopped) _reset();
  }

  /// Reports a closed channel or a failed connection.
  void lost(String reason) {
    if (!_armed || _stopped) return;
    stop();
    onLost(reason);
  }

  /// Stops watching: the transfer finished or the session is gone.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  void _reset() {
    _timer?.cancel();
    _timer = Timer(idleTimeout, () => lost('the peer went silent'));
  }
}

/// Fetches short-lived TURN credentials from the backend. Returns null when
/// TURN is disabled, unreachable, or the response is malformed -- the caller
/// then degrades to STUN-only (transfer still succeeds via R2 fallback).
///
/// The endpoint requires the transfer access token, so a caller that holds one
/// must pass it: TURN credentials are the relay's bandwidth budget (#47).
Future<({List<String> urls, String username, String credential})?>
fetchTurnCredentials(String sessionId, {String? accessToken, Dio? dio}) async {
  try {
    final base =
        dotenv.env['API_BASE_URL'] ?? 'https://api.lynkshare.app/api/v1/';
    final client = dio ?? Dio();
    final resp = await client.getUri(
      Uri.parse(base).resolve('transfers/$sessionId/turn-credentials'),
      options: Options(
        headers: {
          if (accessToken != null && accessToken.isNotEmpty)
            'X-Lynk-Access-Token': accessToken,
        },
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

  /// [names] are the names the receiver saves under, one per file. Without
  /// them the header falls back to the file's own name, which for an
  /// encrypted temp file still carries `.enc` (#53).
  Future<void> sendFiles(
    List<File> files, {
    List<String>? names,
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
  final LocalSignalingOrder _outbound = LocalSignalingOrder();
  final RemoteCandidateQueue _inbound = RemoteCandidateQueue();
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  void Function(String reason)? _onTransportLost;

  FlutterWebrtcPeerActions({required this.signaling});

  /// Creates the peer connection. Only the SENDER creates the DataChannel --
  /// the receiver receives it via `onDataChannel`.
  Future<RTCPeerConnection> init({
    required PeerRole role,
    required List<Map<String, Object>> iceServers,
    required void Function(RTCDataChannel channel) onDataChannelOpen,
    required void Function(Uint8List bytes) onBinaryMessage,
    required void Function(String text) onTextMessage,
    void Function(String reason)? onTransportLost,
  }) async {
    _onTransportLost = onTransportLost;
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onConnectionState = (state) {
      if (isDeadConnectionState(state)) {
        _onTransportLost?.call('the peer connection ${state.name}');
      }
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      // Held until the offer or answer is actually written to the socket.
      for (final message in _outbound.stage(
        SignalingMessage(
          type: SignalingMessageType.candidate,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      )) {
        signaling.send(message);
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
    var opened = false;
    void notifyOpen() {
      if (opened || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        return;
      }
      opened = true;
      onOpen(channel);
    }

    channel.stateChangeStream.listen((state) {
      notifyOpen();
      if (opened && isDeadChannelState(state)) {
        _onTransportLost?.call('the data channel closed');
      }
    });
    // The open event is broadcast and is not replayed. A channel that is
    // already open when this listener attaches would otherwise never notify.
    notifyOpen();
  }

  bool get isChannelOpen =>
      _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  int get bufferedAmount {
    final buffered = _dataChannel?.bufferedAmount;
    return buffered ?? 0;
  }

  Future<void> sendBinary(Uint8List bytes) async {
    if (!isChannelOpen) throw const SocketException('DataChannel is closed');
    await _dataChannel!.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  Future<void> sendText(String text) async {
    if (!isChannelOpen) throw const SocketException('DataChannel is closed');
    await _dataChannel!.send(RTCDataChannelMessage(text));
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
      await _flushRemoteCandidates();
      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);
      return SignalingMessage(
        type: SignalingMessageType.answer,
        sdp: answer.sdp,
      );
    }
    if (msg.sdp != null) {
      await pc.setRemoteDescription(RTCSessionDescription(msg.sdp!, 'answer'));
      await _flushRemoteCandidates();
    }
    return null;
  }

  @override
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    for (final ready in _inbound.add(candidate)) {
      await _addCandidateNow(ready);
    }
  }

  Future<void> _flushRemoteCandidates() async {
    for (final candidate in _inbound.markReady()) {
      await _addCandidateNow(candidate);
    }
  }

  Future<void> _addCandidateNow(Map<String, dynamic> candidate) async {
    await _pc?.addCandidate(
      RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ),
    );
  }

  @override
  Future<void> sendSignaling(SignalingMessage message) async {
    for (final ready in _outbound.stage(message)) {
      await signaling.send(ready);
    }
  }

  Future<void> dispose() async {
    _onTransportLost = null;
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

  /// The transfer key, when this side holds it. Used to seal the file name in
  /// the data-channel header instead of sending it in clear text (#32).
  final String? aesKey;

  late final P2PDeliverySender _sender;
  int _receivedFiles = 0;
  int _receivedBytes = 0;

  File? _currentInboundFile;
  RandomAccessFile? _currentSink;
  String? _currentName;
  String? _currentToken;
  int _currentExpected = 0;
  int _currentWritten = 0;
  Directory? _tempDir;
  bool _transportLost = false;
  late final ReceiveWatchdog _watchdog;

  P2PFileSession._(this.signaling, this.peer, this.aesKey) {
    // Transport loss can precede the receiver subscribing (or occur on a
    // sender, which never awaits transferDone). Keep the original future's
    // error available to its consumer without an unhandled early error.
    unawaited(
      _transferDone.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    _sender = P2PDeliverySender(
      sendText: peer.sendText,
      sendBinary: peer.sendBinary,
      bufferedAmount: () => peer.bufferedAmount,
      isOpen: () => peer.isChannelOpen,
      aesKey: aesKey,
    );
    coordinator = WebrtcPeerCoordinator(actions: peer);
    _watchdog = ReceiveWatchdog(
      idleTimeout: p2pReceiveIdleTimeout,
      onLost: _failTransport,
    );
  }

  /// Ends the transfer because the link is gone; the caller falls back to R2.
  void _failTransport(String reason) {
    _transportLost = true;
    _sender.cancel();
    if (!_transferDone.isCompleted) {
      _transferDone.completeError(SocketException(reason));
    }
  }

  static Future<P2PFileSession> connect({
    required Uri signalingUrl,
    required PeerRole role,
    required String sessionId,
    String? accessToken,
    String? aesKey,
    void Function()? onFallbackToCloud,
  }) async {
    final socket = WebSocketChannel.connect(signalingUrl);
    final signaling = SignalingChannel(WebSocketChannelAdapter(socket));
    if (accessToken != null && accessToken.isNotEmpty) {
      // The room refuses a socket that does not present this token first (#32).
      await signaling.sendAuth(accessToken);
    }
    final peer = FlutterWebrtcPeerActions(signaling: signaling);
    final session = P2PFileSession._(signaling, peer, aesKey)
      ..onFallbackToCloud = onFallbackToCloud;

    final turn = await fetchTurnCredentials(
      sessionId,
      accessToken: accessToken,
    );
    final iceServers = buildIceServers(
      turnEnabled: turn != null,
      urls: turn?.urls ?? const [],
      username: turn?.username ?? '',
      credential: turn?.credential ?? '',
    );

    await peer.init(
      role: role,
      iceServers: iceServers,
      onDataChannelOpen: (_) {
        if (role == PeerRole.receiver) {
          session._watchdog.start();
          // A sender that sees this seals the file name in the header (#32).
          unawaited(
            session.peer
                .sendText(TransferFramer.encodeHello(2, true).text!)
                .catchError((Object _) {}),
          );
        }
        session.coordinator.notifyConnected();
      },
      onBinaryMessage: session._onBinary,
      onTextMessage: session._onText,
      // The sender hears nothing back while it streams, so only the receiver
      // runs the idle timer. A sender still stops on a dead link.
      onTransportLost: role == PeerRole.receiver
          ? session._watchdog.lost
          : session._failTransport,
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
    String? accessToken,
    String? aesKey,
    required void Function() onFallbackToCloud,
  }) => connect(
    signalingUrl: signalingUrl,
    role: PeerRole.sender,
    sessionId: sessionId,
    accessToken: accessToken,
    aesKey: aesKey,
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
      if (hasFailed || _transportLost) {
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
    _sender.cancel();
    if (!_waitCancelled.isCompleted) _waitCancelled.complete();
  }

  /// Streams already-encrypted files over the DataChannel with framing.
  ///
  /// Each file must be the *encrypted* payload (IV-prefixed). Chunks are read
  /// with `await for` so ordering is guaranteed and backpressure honored.
  @override
  Future<void> sendFiles(
    List<File> encryptedFiles, {
    List<String>? names,
    void Function(int totalBytesSent)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    await _sender.sendFiles(
      encryptedFiles,
      names: names,
      onProgress: onProgress,
      shouldAbort: shouldAbort,
    );
  }

  /// Called only after the notifier has decrypted and delivered every file.
  Future<void> confirmDelivery({required int files, required int bytes}) async {
    if (!_transferDone.isCompleted ||
        _transportLost ||
        files != _receivedFiles ||
        bytes != _receivedBytes ||
        files == 0) {
      throw StateError('file delivery does not match the received transfer');
    }
    await peer.sendText(TransferFramer.encodeReceipt(files, bytes).text!);
    final elapsed = Stopwatch()..start();
    while (peer.isChannelOpen && peer.bufferedAmount > 0) {
      if (elapsed.elapsed > const Duration(seconds: 5)) {
        throw TimeoutException('receipt did not drain');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Stream<ReceivedFile> get onFileReceived => _fileReceived.stream;

  /// Completes when the sender signals overall completion.
  Future<void> get transferDone => _transferDone.future;

  void _ensureTempDir() {
    _tempDir ??= Directory.systemTemp.createTempSync('lynk_p2p_');
  }

  void _onText(String text) {
    _watchdog.activity();
    final parsed = TransferFramer.parseText(text);
    if (parsed == null) return;
    switch (parsed.kind) {
      case FrameKind.header:
        if (_currentSink != null || _transferDone.isCompleted) {
          _abortReceive('unexpected file header');
          return;
        }
        final meta = parsed.meta!;
        final name = meta.token != null
            ? NameSealer.open(meta.token!, aesKey)
            : meta.name;
        if (name == null) {
          // The name is sealed with a key this side does not hold.
          if (!_transferDone.isCompleted) {
            _transferDone.completeError(
              const SocketException('cannot open the file name'),
            );
          }
          return;
        }
        _ensureTempDir();
        _currentName = name;
        _currentToken = meta.token;
        _currentExpected = meta.size;
        _currentWritten = 0;
        _currentInboundFile = File(
          '${_tempDir!.path}/'
          // The name comes from the peer, so it is reduced to a single safe
          // path segment before it is joined onto the temp directory.
          '${DateTime.now().microsecondsSinceEpoch}_'
          '${FileNameSanitizer.safeFileName(name)}',
        );
        _currentSink = _currentInboundFile!.openSync(mode: FileMode.write);
      case FrameKind.hello:
      case FrameKind.receipt:
        _sender.accept(parsed);
      case FrameKind.eof:
        final meta = parsed.meta!;
        final sameFile = meta.token != null
            ? meta.token == _currentToken
            : meta.name == _currentName;
        if (!sameFile) return;
        _currentSink?.closeSync();
        final file = _currentInboundFile;
        final name = _currentName ?? '';
        if (file != null && _currentWritten == _currentExpected) {
          _receivedFiles++;
          _receivedBytes += _currentWritten;
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
        _currentToken = null;
        _currentWritten = 0;
      case FrameKind.done:
        if (_currentSink != null || _receivedFiles == 0) {
          _abortReceive('incomplete direct transfer');
          return;
        }
        _watchdog.stop();
        if (!_transferDone.isCompleted) _transferDone.complete();
    }
  }

  void _onBinary(Uint8List bytes) {
    _watchdog.activity();
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
    _watchdog.stop();
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
