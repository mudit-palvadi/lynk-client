import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A transfer that arrives through a pairing session comes from a sender that
/// put it on the server, so the receiver must not wait for a direct
/// connection that is never coming.
///
/// Screen-to-route handoff is exercised behaviorally in
/// core/routing/transfer_navigation_test.dart; cloud bypass is covered by
/// integration/p2p_cloud_fallback_test.dart. Keep the screen-to-notifier guard.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the download screen hands the signal to the notifier', () {
    final screen = read(
      'lib/features/file_transfer/presentation/pages/download_progress_screen.dart',
    );
    expect(screen, contains('viaPairing: widget.viaPairing'));
  });
}
