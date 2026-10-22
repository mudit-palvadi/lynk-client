import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A transfer that arrives through a pairing session comes from a sender that
/// put it on the server, so the receiver must not wait for a direct
/// connection that is never coming.
///
/// The signal travels from the receiver screen, through the route, into the
/// download screen and on to the notifier. Each of those steps is checked
/// here, because a break anywhere in the chain puts the download back to
/// waiting for a connection that cannot arrive.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the receiver screen says the transfer came through a session', () {
    final screen = read(
      'lib/features/file_receive/presentation/pages/receive_qr_screen.dart',
    );
    expect(screen, contains('via=pairing'));
  });

  test('the route passes the signal on to the download screen', () {
    final router = read('lib/core/routing/app_router.dart');
    expect(router, contains("queryParameters['via'] == 'pairing'"));
    expect(router, contains('viaPairing: viaPairing'));
  });

  test('the download screen hands the signal to the notifier', () {
    final screen = read(
      'lib/features/file_transfer/presentation/pages/download_progress_screen.dart',
    );
    expect(screen, contains('viaPairing: widget.viaPairing'));
  });

  test('the notifier goes straight to the server for a paired transfer', () {
    final notifier = read('lib/core/providers/download_notifier.dart');
    expect(notifier, contains('bool viaPairing = false'));
    expect(notifier, contains('if (viaPairing)'));
  });
}
