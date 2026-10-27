import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a done frame is complete only when every declared file arrived', () {
    expect(
      directReceiveIsComplete(
        fileOpen: false,
        receivedFiles: 2,
        expectedFiles: 2,
      ),
      isTrue,
    );
    expect(
      directReceiveIsComplete(
        fileOpen: false,
        receivedFiles: 1,
        expectedFiles: 2,
      ),
      isFalse,
    );
    expect(
      directReceiveIsComplete(
        fileOpen: true,
        receivedFiles: 2,
        expectedFiles: 2,
      ),
      isFalse,
    );
    expect(
      directReceiveIsComplete(
        fileOpen: false,
        receivedFiles: 0,
        expectedFiles: 1,
      ),
      isFalse,
    );
  });
}
