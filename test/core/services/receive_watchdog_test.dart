import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  const idle = Duration(milliseconds: 60);

  group('a receive ends when the link dies after the channel opens', () {
    test('a silent channel ends the receive', () async {
      final reasons = <String>[];
      final watchdog = ReceiveWatchdog(idleTimeout: idle, onLost: reasons.add);

      watchdog.start();
      await Future<void>.delayed(idle * 2);

      expect(reasons, ['the peer went silent']);
    });

    test('frames keep the receive alive', () async {
      final reasons = <String>[];
      final watchdog = ReceiveWatchdog(idleTimeout: idle, onLost: reasons.add);
      addTearDown(watchdog.stop);

      watchdog.start();
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(idle ~/ 2);
        watchdog.activity();
      }

      expect(reasons, isEmpty);
    });

    test('a closed channel ends the receive once', () {
      final reasons = <String>[];
      final watchdog = ReceiveWatchdog(idleTimeout: idle, onLost: reasons.add);

      watchdog.start();
      watchdog.lost('the data channel closed');
      watchdog.lost('the peer connection failed');

      expect(reasons, ['the data channel closed']);
    });

    test('nothing ends a receive before the channel opens', () async {
      final reasons = <String>[];
      final watchdog = ReceiveWatchdog(idleTimeout: idle, onLost: reasons.add);

      watchdog.lost('the peer connection failed');
      await Future<void>.delayed(idle * 2);

      expect(reasons, isEmpty);
    });

    test('a finished transfer is not ended by the sender closing', () async {
      final reasons = <String>[];
      final watchdog = ReceiveWatchdog(idleTimeout: idle, onLost: reasons.add);

      watchdog.start();
      watchdog.stop();
      watchdog.lost('the data channel closed');
      await Future<void>.delayed(idle * 2);

      expect(reasons, isEmpty);
    });
  });

  group('dead link states', () {
    test('closing and closed channels are dead', () {
      expect(
        isDeadChannelState(RTCDataChannelState.RTCDataChannelClosing),
        isTrue,
      );
      expect(
        isDeadChannelState(RTCDataChannelState.RTCDataChannelClosed),
        isTrue,
      );
      expect(
        isDeadChannelState(RTCDataChannelState.RTCDataChannelOpen),
        isFalse,
      );
      expect(isDeadChannelState(null), isFalse);
    });

    test(
      'failed and closed connections are dead, disconnected may recover',
      () {
        expect(
          isDeadConnectionState(
            RTCPeerConnectionState.RTCPeerConnectionStateFailed,
          ),
          isTrue,
        );
        expect(
          isDeadConnectionState(
            RTCPeerConnectionState.RTCPeerConnectionStateClosed,
          ),
          isTrue,
        );
        expect(
          isDeadConnectionState(
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
          ),
          isFalse,
        );
        expect(
          isDeadConnectionState(
            RTCPeerConnectionState.RTCPeerConnectionStateConnected,
          ),
          isFalse,
        );
      },
    );
  });
}
