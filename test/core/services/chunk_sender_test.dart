import 'dart:async';
import 'dart:typed_data';

import 'package:client/core/services/chunk_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChunkSender (64 KB chunks + backpressure over DataChannel)', () {
    test('sends every chunk with correct slice boundaries', () async {
      final sent = <Uint8List>[];
      final sender = ChunkSender(
        bufferedAmount: () => 0,
        send: (bytes) async => sent.add(bytes),
      );

      final payload = Uint8List.fromList(List.filled(200 * 1024, 7));
      await sender.sendAll(payload);

      expect(sent.length, 4); // ceil(200 / 64)
      // Reassembly must reproduce the original payload byte-for-byte.
      final rebuilt = BytesBuilder();
      for (final c in sent) {
        rebuilt.add(c);
      }
      expect(rebuilt.toBytes(), payload);
      expect(sent.first.length, 64 * 1024);
      expect(sent.last.length, 8 * 1024);
    });

    test('waits while backpressure is paused, resumes after drain', () async {
      var buffer = 2 * 1024 * 1024; // start above the 1 MB high-water mark
      final sent = <Uint8List>[];
      // Receiver-side drain simulation: frees 32 KB per millisecond,
      // independent of the sender (like a real RTCDataChannel consumer).
      final drainer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        if (buffer >= 32 * 1024) {
          buffer -= 32 * 1024;
        } else {
          buffer = 0;
        }
      });
      final sender = ChunkSender(
        bufferedAmount: () => buffer,
        send: (bytes) async => sent.add(bytes),
        pollInterval: const Duration(milliseconds: 1),
      );

      await sender.sendAll(Uint8List.fromList(List.filled(128 * 1024, 1)));
      drainer.cancel();

      // All chunks eventually delivered despite the initial pause, and the
      // sender demonstrably yielded while the buffer was over the watermark.
      expect(sent.length, 2);
      expect(sender.pauses, greaterThan(0));
    });

    test('payload smaller than one chunk is a single send', () async {
      final sent = <Uint8List>[];
      final sender = ChunkSender(
        bufferedAmount: () => 0,
        send: (bytes) async => sent.add(bytes),
      );

      await sender.sendAll(Uint8List.fromList(List.filled(1024, 3)));

      expect(sent.length, 1);
      expect(sent.single.length, 1024);
    });

    test('empty payload performs no sends', () async {
      var calls = 0;
      final sender = ChunkSender(
        bufferedAmount: () => 0,
        send: (_) async => calls++,
      );

      await sender.sendAll(Uint8List(0));

      expect(calls, 0);
    });

    group('progress callback', () {
      test('reports cumulative sent bytes matching chunk sizes', () async {
        final totals = <int>[];
        final sender = ChunkSender(
          bufferedAmount: () => 0,
          send: (_) async {},
          onProgress: (sent) => totals.add(sent),
        );

        await sender.sendAll(Uint8List.fromList(List.filled(200 * 1024, 5)));

        expect(totals, [64 * 1024, 128 * 1024, 192 * 1024, 200 * 1024]);
      });

      test('stays monotonic across backpressure pauses', () async {
        var buffer = 2 * 1024 * 1024;
        final drainer = Timer.periodic(const Duration(milliseconds: 1), (_) {
          if (buffer >= 32 * 1024) {
            buffer -= 32 * 1024;
          } else {
            buffer = 0;
          }
        });
        var previous = -1;
        var monotonic = true;
        final sender = ChunkSender(
          bufferedAmount: () => buffer,
          send: (_) async {},
          pollInterval: const Duration(milliseconds: 1),
          onProgress: (sent) {
            if (sent <= previous) monotonic = false;
            previous = sent;
          },
        );

        await sender.sendAll(Uint8List.fromList(List.filled(128 * 1024, 1)));
        drainer.cancel();

        expect(monotonic, isTrue);
        expect(previous, 128 * 1024);
      });

      test('no callback registered is fine (optional param)', () async {
        final sender = ChunkSender(bufferedAmount: () => 0, send: (_) async {});

        await sender.sendAll(Uint8List.fromList([1]));

        expect(sender.pauses, 0);
      });
    });
  });
}
