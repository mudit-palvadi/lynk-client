import 'dart:typed_data';

import 'package:client/core/services/webrtc_peer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChunkCollector (receiver-side reassembly)', () {
    test('concatenates chunks in arrival order', () async {
      final collector = ChunkCollector();

      collector.add(Uint8List.fromList([1, 2, 3]));
      collector.add(Uint8List.fromList([4, 5]));
      final result = await collector.close();

      expect(result, [1, 2, 3, 4, 5]);
    });

    test('empty transfer yields empty payload', () async {
      final collector = ChunkCollector();
      expect(await collector.close(), isEmpty);
    });

    test('receivedBytes tracks cumulative count before close', () {
      final collector = ChunkCollector();
      expect(collector.receivedBytes, 0);

      collector.add(Uint8List.fromList(List.filled(64 * 1024, 9)));
      collector.add(Uint8List.fromList([7]));

      expect(collector.receivedBytes, 64 * 1024 + 1);
      expect(collector.chunkCount, 2);
    });

    test('adding after close is rejected with StateError', () async {
      final collector = ChunkCollector();
      await collector.close();

      expect(() => collector.add(Uint8List.fromList([1])), throwsStateError);
    });
  });
}
