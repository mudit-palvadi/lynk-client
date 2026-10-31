import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Public project documentation', () {
    test(
      'README introduces the shipped app and preserves developer guidance',
      () {
        final readme = File('README.md').readAsStringSync();

        expect(readme, contains('store_assets/png/app_icon_512.png'));
        expect(File('store_assets/png/app_icon_512.png').existsSync(), isTrue);
        expect(
          readme,
          contains(
            'https://play.google.com/store/apps/details?id=app.xynix.lynk',
          ),
        );
        expect(readme, contains('https://lynkshare.app'));
        expect(readme, contains('## Screenshots'));
        expect(
          RegExp(
            r'<img src="https://play-lh\.googleusercontent\.com/[^"\s]+"',
          ).allMatches(readme),
          hasLength(4),
        );
        expect(readme, contains('Light, Dark and System'));
        expect(readme, contains('SECURITY.md'));
        expect(readme, contains('docs/release-process.md'));
        expect(File('docs/release-process.md').existsSync(), isTrue);
        expect(readme, contains('lynk-android-release'));
        expect(readme, contains('lynk-android-patch'));
        expect(readme, isNot(contains('Dark interface.')));
        expect(readme, isNot(contains('License-MIT')));
      },
    );

    test(
      'client license is GPL version 3 only with the requested attribution',
      () {
        final license = File('LICENSE').readAsStringSync();
        final readme = File('README.md').readAsStringSync();

        expect(license, contains('GNU GENERAL PUBLIC LICENSE'));
        expect(license, contains('Version 3, 29 June 2007'));
        expect(license, contains('END OF TERMS AND CONDITIONS'));
        expect(license, contains('16. Limitation of Liability.'));
        // SPDX license-list-data/text/GPL-3.0-only.txt, normalized to LF.
        expect(
          sha256
              .convert(utf8.encode(license.replaceAll('\r\n', '\n')))
              .toString(),
          'fb981668c18a279e285fc4d83fba1e836cc84dd4daa73c9697d3cfd2d8aca6e0',
        );
        expect(readme, contains('GPL-3.0-only'));
        expect(readme, contains('Copyright (c) 2026 Mudit Palvadi'));
        expect(readme, contains('[LICENSE](LICENSE)'));
      },
    );
  });
}
