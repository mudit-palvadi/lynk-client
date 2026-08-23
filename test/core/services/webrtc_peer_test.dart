import 'package:client/core/services/webrtc_peer.dart';
import 'package:client/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every platform action the coordinator triggers.
class FakePeerActions implements PeerActions {
  final List<SignalingMessage> sent = [];
  final List<SignalingMessage> remoteDescriptions = [];
  final List<Map<String, dynamic>> remoteCandidates = [];

  SignalingMessage? Function(SignalingMessage msg)? onRemoteDescription;
  SignalingMessage? offerToCreate;

  @override
  Future<SignalingMessage?> handleRemoteDescription(
    SignalingMessage msg,
  ) async {
    remoteDescriptions.add(msg);
    return onRemoteDescription?.call(msg);
  }

  @override
  Future<SignalingMessage> createOffer() async {
    return offerToCreate ??
        const SignalingMessage(type: SignalingMessageType.offer, sdp: 'local');
  }

  @override
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> sendSignaling(SignalingMessage message) async {
    sent.add(message);
  }
}

void main() {
  group('WebrtcPeerCoordinator (sender side)', () {
    test('startAsSender creates and signals an offer', () async {
      final actions = FakePeerActions()
        ..offerToCreate = const SignalingMessage(
          type: SignalingMessageType.offer,
          sdp: 'offer-sdp',
        );
      final coordinator = WebrtcPeerCoordinator(actions: actions);

      await coordinator.start(role: PeerRole.sender);

      expect(actions.sent.single.type, SignalingMessageType.offer);
      expect(actions.sent.single.sdp, 'offer-sdp');
      coordinator.dispose();
    });

    test('sender receiving an answer forwards it to the platform only', () async {
      final actions = FakePeerActions();
      final coordinator = WebrtcPeerCoordinator(actions: actions)
        ..role = PeerRole.sender;
      await coordinator.start(role: PeerRole.sender);

      await coordinator.handleMessage(
        const SignalingMessage(
          type: SignalingMessageType.answer,
          sdp: 'answer-sdp',
        ),
      );

      expect(actions.remoteDescriptions.single.sdp, 'answer-sdp');
      // Nothing new was signaled back — the answer terminates the SDP exchange.
      expect(actions.sent.length, 1); // just the initial offer
      coordinator.dispose();
    });

    test('sender receiving candidates forwards each to the platform', () async {
      final actions = FakePeerActions();
      final coordinator = WebrtcPeerCoordinator(actions: actions);
      await coordinator.start(role: PeerRole.sender);

      const cand = {'candidate': 'c1', 'sdpMid': '0'};
      await coordinator.handleMessage(
        const SignalingMessage(
          type: SignalingMessageType.candidate,
          candidate: cand,
        ),
      );

      expect(actions.remoteCandidates.single, cand);
      coordinator.dispose();
    });
  });

  group('WebrtcPeerCoordinator (receiver side)', () {
    test('receiver answering an offer sends the created answer', () async {
      final actions = FakePeerActions()
        ..onRemoteDescription = (msg) => SignalingMessage(
          type: SignalingMessageType.answer,
          sdp: 'answer-sdp',
        );
      final coordinator = WebrtcPeerCoordinator(actions: actions);

      await coordinator.start(role: PeerRole.receiver);
      await coordinator.handleMessage(
        const SignalingMessage(
          type: SignalingMessageType.offer,
          sdp: 'offer-sdp',
        ),
      );

      expect(actions.remoteDescriptions.single.sdp, 'offer-sdp');
      expect(actions.sent.single.type, SignalingMessageType.answer);
      expect(actions.sent.single.sdp, 'answer-sdp');
      coordinator.dispose();
    });

    test('error and unknown messages are ignored without throwing', () async {
      final actions = FakePeerActions();
      final coordinator = WebrtcPeerCoordinator(actions: actions);
      await coordinator.start(role: PeerRole.receiver);

      await coordinator.handleMessage(
        const SignalingMessage(type: SignalingMessageType.error),
      );

      expect(actions.remoteDescriptions, isEmpty);
      expect(actions.remoteCandidates, isEmpty);
      expect(actions.sent, isEmpty);
      coordinator.dispose();
    });
  });

  group('connection lifecycle (timeout -> R2 fallback)', () {
    test('notifyConnected cancels the fallback timer', () async {
      final actions = FakePeerActions();
      var fallbackFired = false;
      final coordinator = WebrtcPeerCoordinator(
        actions: actions,
        connectTimeout: const Duration(milliseconds: 50),
      )..onP2PFailed = () => fallbackFired = true;

      await coordinator.start(role: PeerRole.sender);
      coordinator.notifyConnected();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fallbackFired, isFalse);
      coordinator.dispose();
    });

    test(
      'no connection within timeout fires onP2PFailed exactly once',
      () async {
        final actions = FakePeerActions();
        var fires = 0;
        final coordinator = WebrtcPeerCoordinator(
          actions: actions,
          connectTimeout: const Duration(milliseconds: 40),
        )..onP2PFailed = () => fires++;

        await coordinator.start(role: PeerRole.sender);
        await Future<void>.delayed(const Duration(milliseconds: 90));
        coordinator.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(fires, 1);
      },
    );

    test('default timeout is 8 seconds per Phases.md', () {
      final coordinator = WebrtcPeerCoordinator(actions: FakePeerActions());
      expect(coordinator.connectTimeout, const Duration(seconds: 8));
      coordinator.dispose();
    });
  });
}
