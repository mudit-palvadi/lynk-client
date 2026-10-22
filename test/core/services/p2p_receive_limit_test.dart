import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// A peer must not be able to send more than it said it would.
///
/// The file header carries the size of the file, and the tiers cap how big a
/// transfer may be. A receiver that trusts neither could be made to fill the
/// device's disk, so both limits are checked before a byte is written.
void main() {
  group('isWithinReceiveLimit', () {
    test('accepts a transfer that stays inside what it declared', () {
      expect(
        isWithinReceiveLimit(
          receivedBytes: 1000,
          declaredBytes: 1000,
          maxBytes: maxP2PReceiveBytes,
        ),
        isTrue,
      );
    });

    test('rejects a peer that sends more than it declared', () {
      expect(
        isWithinReceiveLimit(
          receivedBytes: 1001,
          declaredBytes: 1000,
          maxBytes: maxP2PReceiveBytes,
        ),
        isFalse,
      );
    });

    test('rejects a transfer bigger than the biggest one on offer', () {
      expect(
        isWithinReceiveLimit(
          receivedBytes: maxP2PReceiveBytes + 1,
          declaredBytes: maxP2PReceiveBytes + 1,
          maxBytes: maxP2PReceiveBytes,
        ),
        isFalse,
      );
    });
  });

  test('the cap is the biggest device-to-device transfer on offer', () {
    // The app offers 50 MB for a direct transfer once the limit is unlocked.
    // The cap leaves a little room for the per-file encryption overhead.
    expect(maxP2PReceiveBytes, greaterThan(50 * 1024 * 1024));
    expect(maxP2PReceiveBytes, lessThan(51 * 1024 * 1024));
  });
}
