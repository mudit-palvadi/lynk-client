import 'dart:async';

import 'package:client/core/services/signaling_channel.dart';
import 'package:client/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake of the raw WebSocket surface used by [SignalingChannel].
class FakeSocket implements WebSocketLike {
  final StreamController<dynamic> inbound = StreamController<dynamic>();
  final List<dynamic> sent = [];
  bool closed = false;
  int closeCalls = 0;

  @override
  Stream<dynamic> get stream => inbound.stream;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    await inbound.close();
  }
}

void main() {
  group('SignalingChannel (WebSocket signaling wrapper)', () {
    test('keeps replayed offer and ICE until the peer is ready', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);
      addTearDown(channel.close);

      // The server replays these while TURN lookup and peer init are awaiting.
      socket.inbound.add('{"type":"offer","sdp":"replayed-offer"}');
      socket.inbound.add('{"type":"candidate","candidate":{"candidate":"c1"}}');
      await pumpEventQueue();

      final received = <SignalingMessage>[];
      channel.messages.listen(received.add);
      socket.inbound.add('{"type":"candidate","candidate":{"candidate":"c2"}}');
      await pumpEventQueue();

      expect(received.map((message) => message.type), [
        SignalingMessageType.offer,
        SignalingMessageType.candidate,
        SignalingMessageType.candidate,
      ]);
      expect(received.first.sdp, 'replayed-offer');
      expect(received[1].candidate, {'candidate': 'c1'});
      expect(received[2].candidate, {'candidate': 'c2'});
    });

    test(
      'keeps early parse errors without losing the next valid frame',
      () async {
        final socket = FakeSocket();
        final channel = SignalingChannel(socket);
        addTearDown(channel.close);

        socket.inbound.add('not-json{');
        socket.inbound.add('{"type":"answer","sdp":"early-answer"}');
        await pumpEventQueue();

        final received = <SignalingMessageType>[];
        channel.messages.listen((message) => received.add(message.type));
        await pumpEventQueue();

        expect(received, [
          SignalingMessageType.error,
          SignalingMessageType.answer,
        ]);
      },
    );

    test(
      'preserves early frames when the socket finishes before listening',
      () async {
        final socket = FakeSocket();
        final channel = SignalingChannel(socket);
        addTearDown(channel.close);

        socket.inbound.add('{"type":"offer","sdp":"last-offer"}');
        final socketDone = socket.inbound.close();
        await pumpEventQueue();

        final received = await channel.messages.toList();
        await socketDone;
        expect(received.map((message) => message.sdp), ['last-offer']);
      },
    );

    test('still broadcasts live frames to multiple listeners', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);
      addTearDown(channel.close);
      final first = <SignalingMessageType>[];
      final second = <SignalingMessageType>[];
      channel.messages.listen((message) => first.add(message.type));
      channel.messages.listen((message) => second.add(message.type));

      socket.inbound.add('{"type":"offer","sdp":"live-offer"}');
      await pumpEventQueue();

      expect(first, [SignalingMessageType.offer]);
      expect(second, first);
    });

    test('retains early socket errors for the eventual listener', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);
      addTearDown(channel.close);
      final error = StateError('socket failed during initialization');
      socket.inbound.addError(error);
      await pumpEventQueue();

      final errors = <Object>[];
      channel.messages.listen(null, onError: errors.add);
      await pumpEventQueue();

      expect(errors, [same(error)]);
    });

    test(
      'close discards pending frames without waiting for a listener',
      () async {
        final socket = FakeSocket();
        final channel = SignalingChannel(socket);
        socket.inbound.add('{"type":"offer","sdp":"unused-offer"}');
        await pumpEventQueue();

        await channel.close().timeout(const Duration(seconds: 1));
        await channel.close();

        expect(socket.closeCalls, 1);
        expect(await channel.messages.toList(), isEmpty);
      },
    );

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
      expect(socket.closeCalls, 1);
    });

    test('sendAuth writes the room token as the first frame', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);

      await channel.sendAuth('token-1');

      expect(socket.sent.single, '{"type":"auth","token":"token-1"}');
    });

    test('sendAuth is a no-op once the channel is closed', () async {
      final socket = FakeSocket();
      final channel = SignalingChannel(socket);

      await channel.close();
      await channel.sendAuth('token-1');

      expect(socket.sent, isEmpty);
    });
  });
}
