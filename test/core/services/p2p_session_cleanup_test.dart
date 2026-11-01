import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/core/services/signaling_channel.dart';
import 'package:client/core/services/webrtc_peer.dart';
import 'package:client/core/services/webrtc_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// In-memory stand-in for the signaling WebSocket.
class _FakeSocket implements WebSocketLike {
  final StreamController<dynamic> inbound = StreamController<dynamic>();
  bool closed = false;

  void addIncoming(String frame) => inbound.add(frame);

  void addError(Object error) => inbound.addError(error);

  @override
  Stream<dynamic> get stream => inbound.stream;

  @override
  void add(dynamic data) {}

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await inbound.close();
  }
}

Future<TurnCredentials?> _noTurn(
  String sessionId, {
  String? accessToken,
  Dio? dio,
}) async => null;

/// A channel the fake peer holds but no test reads from.
SignalingChannel _unusedSignaling() => SignalingChannel(_FakeSocket());

/// Peer stub that never touches the WebRTC plugin.
class _FakePeer extends FlutterWebrtcPeerActions {
  _FakePeer({
    required super.signaling,
    this.failInit = false,
    this.failOffer = false,
    this.failRemoteDescription = false,
    this.failCandidate = false,
    this.throwOnDispose = false,
  });

  final bool failInit;
  final bool failOffer;
  final bool failRemoteDescription;
  final bool failCandidate;
  final bool throwOnDispose;

  int initCalls = 0;
  int disposeCalls = 0;

  @override
  Future<RTCPeerConnection> init({
    required PeerRole role,
    required List<Map<String, Object>> iceServers,
    required void Function(RTCDataChannel channel) onDataChannelOpen,
    required void Function(Uint8List bytes) onBinaryMessage,
    required void Function(String text) onTextMessage,
    void Function(String reason)? onTransportLost,
  }) async {
    initCalls++;
    if (failInit) throw StateError('peer init failed');
    return _FakePeerConnection();
  }

  @override
  Future<SignalingMessage> createOffer() async {
    if (failOffer) throw StateError('coordinator start failed');
    return const SignalingMessage(
      type: SignalingMessageType.offer,
      sdp: 'offer-sdp',
    );
  }

  @override
  Future<SignalingMessage?> handleRemoteDescription(
    SignalingMessage msg,
  ) async {
    if (failRemoteDescription) throw StateError('remote description failed');
    return null;
  }

  @override
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    if (failCandidate) throw StateError('candidate failed');
  }

  @override
  Future<void> sendSignaling(SignalingMessage message) async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (throwOnDispose) throw StateError('peer dispose failed');
  }
}

/// Minimal peer connection for the candidate path.
class _FakePeerConnection extends Fake implements RTCPeerConnection {
  @override
  RTCPeerConnectionState? connectionState;

  bool throwOnAdd = false;
  bool closed = false;
  int addCalls = 0;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCDataChannel channel)? onDataChannel;

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    addCalls++;
    if (throwOnAdd) throw StateError('addCandidate after close');
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit dataChannelDict,
  ) async {
    throw StateError('DataChannel setup failed');
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<P2PFileSession> _connect({
  required _FakeSocket socket,
  required _FakePeer Function(SignalingChannel signaling) buildPeer,
  PeerRole role = PeerRole.receiver,
}) {
  return P2PFileSession.connect(
    signalingUrl: Uri.parse('ws://test.local/ws/signaling/session-1'),
    role: role,
    sessionId: 'session-1',
    connectSocket: (_) => socket,
    createPeer: buildPeer,
    turnCredentials: _noTurn,
  );
}

void main() {
  group('P2PFileSession.connect cleanup (#75)', () {
    test('disposes the peer and socket when peer.init throws', () async {
      final socket = _FakeSocket();
      final peer = _FakePeer(signaling: _unusedSignaling(), failInit: true);

      await expectLater(
        _connect(socket: socket, buildPeer: (_) => peer),
        throwsA(isA<StateError>()),
      );

      expect(peer.initCalls, 1);
      expect(peer.disposeCalls, greaterThanOrEqualTo(1));
      expect(socket.closed, isTrue);
    });

    test('closes a connection whose DataChannel setup failed', () async {
      final pc = _FakePeerConnection();
      final actions = FlutterWebrtcPeerActions(
        signaling: SignalingChannel(_FakeSocket()),
        createConnection: (_) async => pc,
      );

      await expectLater(
        actions.init(
          role: PeerRole.sender,
          iceServers: const [],
          onDataChannelOpen: (_) {},
          onBinaryMessage: (_) {},
          onTextMessage: (_) {},
        ),
        throwsA(isA<StateError>()),
      );

      await actions.dispose();
      expect(pc.closed, isTrue);
    });

    test('disposes the peer and socket when start throws', () async {
      final socket = _FakeSocket();
      final peer = _FakePeer(signaling: _unusedSignaling(), failOffer: true);

      await expectLater(
        _connect(socket: socket, buildPeer: (_) => peer, role: PeerRole.sender),
        throwsA(isA<StateError>()),
      );

      expect(peer.initCalls, 1);
      expect(peer.disposeCalls, greaterThanOrEqualTo(1));
      expect(socket.closed, isTrue);
    });

    test('closes signaling even when peer disposal throws', () async {
      final socket = _FakeSocket();
      final peer = _FakePeer(
        signaling: _unusedSignaling(),
        failInit: true,
        throwOnDispose: true,
      );

      await expectLater(
        _connect(socket: socket, buildPeer: (_) => peer),
        throwsA(isA<StateError>()),
      );

      expect(socket.closed, isTrue);
    });
  });

  group('signaling handler failures (#75)', () {
    test('a throwing remote-description handler fails the transfer', () async {
      final socket = _FakeSocket();
      final session = await _connect(
        socket: socket,
        buildPeer: (signaling) =>
            _FakePeer(signaling: signaling, failRemoteDescription: true),
      );
      addTearDown(session.dispose);

      final failed = expectLater(
        session.transferDone,
        throwsA(isA<SocketException>()),
      );
      socket.addIncoming('{"type":"offer","sdp":"offer-sdp"}');
      await failed;

      // A handler failure takes the transport path, not the connect timeout.
      expect(session.hasFailed, isFalse);
    });

    test('a throwing candidate handler fails the transfer', () async {
      final socket = _FakeSocket();
      final session = await _connect(
        socket: socket,
        buildPeer: (signaling) =>
            _FakePeer(signaling: signaling, failCandidate: true),
      );
      addTearDown(session.dispose);

      final failed = expectLater(
        session.transferDone,
        throwsA(isA<SocketException>()),
      );
      socket.addIncoming(
        '{"type":"candidate","candidate":{"candidate":"c1","sdpMid":"0"}}',
      );
      await failed;
    });

    test('a signaling socket error fails the transfer', () async {
      final socket = _FakeSocket();
      final session = await _connect(
        socket: socket,
        buildPeer: (signaling) => _FakePeer(signaling: signaling),
      );
      addTearDown(session.dispose);

      final failed = expectLater(
        session.transferDone,
        throwsA(isA<SocketException>()),
      );
      socket.addError(StateError('signaling socket reset'));
      await failed;
    });
  });

  group('remote ICE candidates (#75)', () {
    Future<FlutterWebrtcPeerActions> actionsFor(
      _FakePeerConnection pc, {
      void Function(String reason)? onTransportLost,
    }) async {
      final socket = _FakeSocket();
      final actions = FlutterWebrtcPeerActions(
        signaling: SignalingChannel(socket),
        createConnection: (_) async => pc,
      );
      await actions.init(
        role: PeerRole.receiver,
        iceServers: const [],
        onDataChannelOpen: (_) {},
        onBinaryMessage: (_) {},
        onTextMessage: (_) {},
        onTransportLost: onTransportLost,
      );
      // A candidate is only applied once the remote description arrived.
      await actions.handleRemoteDescription(
        const SignalingMessage(
          type: SignalingMessageType.answer,
          sdp: 'answer',
        ),
      );
      return actions;
    }

    test('ignores a candidate on an already-closed connection', () async {
      final pc = _FakePeerConnection()
        ..connectionState = RTCPeerConnectionState.RTCPeerConnectionStateClosed
        ..throwOnAdd = true;
      var lost = 0;
      final actions = await actionsFor(pc, onTransportLost: (_) => lost++);

      await actions.addIceCandidate(const {'candidate': 'c1'});

      expect(pc.addCalls, 0);
      expect(lost, 0);
      await actions.dispose();
    });

    test('reports a rejected candidate as a transport failure', () async {
      final pc = _FakePeerConnection()
        ..connectionState =
            RTCPeerConnectionState.RTCPeerConnectionStateConnected
        ..throwOnAdd = true;
      final reasons = <String>[];
      final actions = await actionsFor(pc, onTransportLost: reasons.add);

      await actions.addIceCandidate(const {'candidate': 'c1'});

      expect(pc.addCalls, 1);
      expect(reasons.single, contains('ICE candidate'));
      await actions.dispose();
    });
  });
}
