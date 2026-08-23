import 'package:client/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignalingMessage parsing (offer / answer / candidate)', () {
    test('parses an offer message', () {
      final msg = SignalingMessage.fromJson({
        'type': 'offer',
        'sdp': 'v=0 offer-sdp',
      });

      expect(msg.type, SignalingMessageType.offer);
      expect(msg.sdp, 'v=0 offer-sdp');
      expect(msg.candidate, isNull);
    });

    test('parses an answer message', () {
      final msg = SignalingMessage.fromJson({
        'type': 'answer',
        'sdp': 'v=0 answer-sdp',
      });

      expect(msg.type, SignalingMessageType.answer);
      expect(msg.sdp, 'v=0 answer-sdp');
    });

    test('parses a candidate message with full ICE fields', () {
      final msg = SignalingMessage.fromJson({
        'type': 'candidate',
        'candidate': {
          'candidate': 'udp://192.168.1.5:50000',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });

      expect(msg.type, SignalingMessageType.candidate);
      expect(msg.sdp, isNull);
      expect(msg.candidate, isNotNull);
      expect(msg.candidate!['candidate'], 'udp://192.168.1.5:50000');
      expect(msg.candidate!['sdpMid'], '0');
      expect(msg.candidate!['sdpMLineIndex'], 0);
    });

    test('round-trips toJson for every message kind', () {
      const inputs = [
        {'type': 'offer', 'sdp': 'offer'},
        {'type': 'answer', 'sdp': 'answer'},
        {
          'type': 'candidate',
          'candidate': <String, dynamic>{'candidate': 'c', 'sdpMid': '0'},
        },
      ];

      for (final input in inputs) {
        final parsed = SignalingMessage.fromJson(input);
        final restored = SignalingMessage.fromJson(parsed.toJson());
        expect(restored.toJson(), parsed.toJson());

        // Cross-language wire format stability: keys must be exactly these.
        expect(parsed.toJson().keys.toSet(), input.keys.toSet());
      }
    });

    test('unknown or missing type falls back to error, never throws', () {
      final unknown = SignalingMessage.fromJson({'type': 'bogus'});
      expect(unknown.type, SignalingMessageType.error);

      final missing = SignalingMessage.fromJson(<String, dynamic>{});
      expect(missing.type, SignalingMessageType.error);

      final invalidJson = SignalingMessage.fromRaw('not-json{');
      expect(invalidJson.type, SignalingMessageType.error);
    });
  });

  group('P2P connection timeout (8s -> R2 fallback)', () {
    test(
      'transitions to failed after the timeout elapses without connect',
      () async {
        final controller = P2PConnectionController(
          connectTimeout: const Duration(milliseconds: 50),
        );

        SignalingMessageType? terminalState;
        controller.onP2PFailed = () {
          terminalState = controller.state;
        };

        controller.beginConnecting();
        expect(controller.state, SignalingMessageType.connecting);

        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(controller.state, SignalingMessageType.failed);
        expect(terminalState, SignalingMessageType.failed);
        controller.dispose();
      },
    );

    test('markConnected cancels the timeout — no false fallback', () async {
      final controller = P2PConnectionController(
        connectTimeout: const Duration(milliseconds: 50),
      );

      var failedCalled = false;
      controller.onP2PFailed = () => failedCalled = true;

      controller.beginConnecting();
      controller.markConnected();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(controller.state, SignalingMessageType.connected);
      expect(failedCalled, isFalse);
      controller.dispose();
    });

    test('default timeout is 8 seconds per Phases.md', () {
      final controller = P2PConnectionController();
      expect(controller.connectTimeout, const Duration(seconds: 8));
      controller.dispose();
    });

    test('dispose after failure does not fire callbacks again', () async {
      final controller = P2PConnectionController(
        connectTimeout: const Duration(milliseconds: 30),
      );

      var calls = 0;
      controller.onP2PFailed = () => calls++;

      controller.beginConnecting();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      controller.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls, 1);
    });
  });

  group('bufferedAmount backpressure (pause > 1 MB, resume below)', () {
    test('allows sending while buffer is under the high-water mark', () {
      final bp = BackpressureController();
      expect(bp.canSend(512 * 1024), isTrue); // 512 KB
      expect(bp.isPaused, isFalse);
    });

    test('pauses sending when buffer exceeds 1 MB', () {
      final bp = BackpressureController();
      expect(bp.canSend(1 * 1024 * 1024 + 1), isFalse);
      expect(bp.isPaused, isTrue);
    });

    test('stays paused until buffer drains below the resume mark', () {
      final bp = BackpressureController();
      bp.canSend(2 * 1024 * 1024); // trigger pause
      expect(bp.isPaused, isTrue);

      // Still above resume threshold -> remain paused.
      expect(bp.canSend(800 * 1024), isFalse);
      expect(bp.isPaused, isTrue);

      // Drained below resume threshold -> resume.
      expect(bp.canSend(128 * 1024), isTrue);
      expect(bp.isPaused, isFalse);
    });

    test('high-water mark is 1 MB and resume mark is below it', () {
      final bp = BackpressureController();
      expect(bp.highWaterMark, 1 * 1024 * 1024);
      expect(bp.resumeWaterMark, lessThan(bp.highWaterMark));
      expect(bp.resumeWaterMark, greaterThan(0));
    });

    test('boundary: exactly at 1 MB is still allowed to send', () {
      final bp = BackpressureController();
      expect(bp.canSend(1 * 1024 * 1024), isTrue);
    });
  });

  group('chunking contract (64 KB sub-chunks)', () {
    test('splits a payload into 64 KB chunks with correct offsets', () {
      const payloadLength = 200 * 1024; // 200 KB
      final chunks = chunkOffsets(payloadLength, WebrtcService.chunkSize);

      expect(chunks.length, 4);
      expect(chunks.first.start, 0);
      expect(chunks.first.end, 64 * 1024);
      expect(chunks.last.end, payloadLength);
    });

    test('payload smaller than one chunk yields a single chunk', () {
      final chunks = chunkOffsets(1024, WebrtcService.chunkSize);
      expect(chunks.length, 1);
      expect(chunks.single.start, 0);
      expect(chunks.single.end, 1024);
    });

    test('exact multiple of chunk size has no empty tail chunk', () {
      final chunks = chunkOffsets(
        WebrtcService.chunkSize * 3,
        WebrtcService.chunkSize,
      );
      expect(chunks.length, 3);
    });
  });
}
