import 'package:client/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The direct-transfer handshake has to survive a phone that is cold starting
/// from a QR code.
///
/// The phone opens the app, reads the QR, starts the app's own connection
/// machinery and only then answers the offer. With the old eight-second
/// budget the connection was torn down before the phone had finished starting
/// up, and the transfer silently fell back to the cloud.
void main() {
  test('the peer handshake waits long enough for a cold-starting phone', () {
    expect(
      P2PConnectionController.defaultTimeout,
      greaterThanOrEqualTo(const Duration(seconds: 15)),
    );
  });
}
