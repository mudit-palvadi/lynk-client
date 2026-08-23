import 'dart:async';

import 'package:client/core/services/signaling_channel.dart';
import 'package:client/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake of the raw WebSocket surface used by [SignalingChannel].
class FakeSocket implements WebSocketLike {
  final StreamController<dynamic> inbound = StreamController<dynamic>();
  final List<dynamic> sent = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => inbound.stream;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await inbound.close();
  }
}

void main() {
  group('SignalingChannel (WebSocket signaling wrapper)', () {
    test('parses incoming JSON frames into SignalingMessage', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);
      final received = <SignalingMessageType>[];
      final sub = channel.messages.listen((m) => received.add(m.type));

      socket.inbound.add('{"type":"offer","sdp":"v=0"}');
      socket.inbound.add('{"type":"candidate","candidate":{"candidate":"c"}}');
      await pumpEventQueue();

      expect(received, [
        SignalingMessageType.offer,
        SignalingMessageType.candidate,
      ]);
      await sub.cancel();
    });

    test(
      'invalid JSON frame surfaces an error message, stream survives',
      () async {
        final socket = FakeSocket();
        final channel = SignalingChannel(socket);
        final types = <SignalingMessageType>[];
        final sub = channel.messages.listen((m) => types.add(m.type));
        var done = false;
        channel.messages.listen(null, onDone: () => done = true);

        socket.inbound.add('not-json{');
        socket.inbound.add('{"type":"answer","sdp":"ok"}');
        await pumpEventQueue();

        expect(types, [
          SignalingMessageType.error,
          SignalingMessageType.answer,
        ]);
        expect(done, isFalse);
        await sub.cancel();
      },
    );

    test(
      'send serializes each message kind to the exact wire format',
      () async {
        final socket = FakeSocket();
        final channel = SignalingChannel(socket);

        await channel.send(
          const SignalingMessage(
            type: SignalingMessageType.offer,
            sdp: 'sdp-o',
          ),
        );
        await channel.send(
          const SignalingMessage(
            type: SignalingMessageType.answer,
            sdp: 'sdp-a',
          ),
        );
        await channel.send(
          const SignalingMessage(
            type: SignalingMessageType.candidate,
            candidate: {'candidate': 'c', 'sdpMid': '0'},
          ),
        );

        expect(socket.sent, [
          '{"type":"offer","sdp":"sdp-o"}',
          '{"type":"answer","sdp":"sdp-a"}',
          '{"type":"candidate","candidate":{"candidate":"c","sdpMid":"0"}}',
        ]);
      },
    );

    test('close closes the underlying socket exactly once', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);

      await channel.close();
      await channel.close();

      expect(socket.closed, isTrue);
    });
  });
}
