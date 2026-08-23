import 'dart:async';
import 'dart:typed_data';

import 'webrtc_service.dart';

/// Streams a file payload over the `RTCDataChannel` as 64 KB encrypted
/// sub-chunks, honoring `bufferedAmount` backpressure via
/// [BackpressureController] (pause >1 MB, resume <256 KB — Phases.md).
class ChunkSender {
  /// Current `bufferedAmount` of the underlying data channel.
  final int Function() bufferedAmount;

  /// Hands one chunk to the data channel.
  final Future<void> Function(Uint8List chunk) send;

  /// How long to yield between backpressure polls.
  final Duration pollInterval;

  final BackpressureController _backpressure = BackpressureController();
  int _pauses = 0;

  ChunkSender({
    required this.bufferedAmount,
    required this.send,
    this.pollInterval = const Duration(milliseconds: 10),
  });

  /// Number of poll cycles spent waiting on backpressure (diagnostics).
  int get pauses => _pauses;

  /// Sends [payload] in [WebrtcService.chunkSize] slices, in order.
  ///
  /// Returns once every byte has been handed to the channel sink. The
  /// receiver-side consumer drains the buffer asynchronously; while the
  /// buffer is over the high-water mark this method yields instead of
  /// queueing unbounded memory.
  Future<void> sendAll(Uint8List payload) async {
    if (payload.isEmpty) return;

    for (final offset in chunkOffsets(
      payload.length,
      WebrtcService.chunkSize,
    )) {
      while (!_backpressure.canSend(bufferedAmount())) {
        _pauses++;
        await Future<void>.delayed(pollInterval);
      }
      await send(Uint8List.sublistView(payload, offset.start, offset.end));
    }
  }
}
