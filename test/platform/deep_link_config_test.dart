import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Guards the Android side of deep linking, which no Dart test can exercise.
///
/// The app can route a link perfectly and still never receive it if the
/// manifest lacks an intent filter, and Android silently ignores every
/// `https://` filter when Digital Asset Links verification fails. Both
/// failures look identical from the app — the browser opens instead — so these
/// are checked as a contract between three files that must agree:
///
/// * `android/app/build.gradle.kts` — the application id
/// * `android/app/src/main/AndroidManifest.xml` — the intent filters
/// * `../web/.well-known/assetlinks.json` — the verification file
void main() {
  // The web app is a separate checkout, so the verification file may not be
  // next to this one (CI checks out the client repo alone). The Digital Asset
  // Links group then skips instead of failing, exactly like the API contract
  // test does for the sibling backend checkout.
  final assetLinksFile = File('../web/.well-known/assetlinks.json');
  final assetLinksSkipReason = assetLinksFile.existsSync()
      ? null
      : 'web checkout not found next to client/ (expected ../web)';

  final manifest = XmlDocument.parse(
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
  );
  final activity = manifest
      .findAllElements('activity')
      .singleWhere(
        (element) =>
            element.getAttribute('android:name') ==
            'app.xynix.lynk.MainActivity',
      );

  List<XmlElement> filtersWhere(bool Function(XmlElement) predicate) =>
      activity.findElements('intent-filter').where(predicate).toList();

  bool hasAction(XmlElement filter, String name) => filter
      .findElements('action')
      .any((element) => element.getAttribute('android:name') == name);

  bool hasCategory(XmlElement filter, String name) => filter
      .findElements('category')
      .any((element) => element.getAttribute('android:name') == name);

  /// Every filter that can be reached from a browser or another app.
  bool isViewable(XmlElement filter) =>
      hasAction(filter, 'android.intent.action.VIEW') &&
      hasCategory(filter, 'android.intent.category.DEFAULT') &&
      hasCategory(filter, 'android.intent.category.BROWSABLE');

  group('AndroidManifest https App Links', () {
    late XmlElement verifiedFilter;

    setUpAll(() {
      final verified = filtersWhere(
        (filter) =>
            filter.getAttribute('android:autoVerify') == 'true' &&
            isViewable(filter),
      );

      expect(
        verified,
        hasLength(1),
        reason:
            'Exactly one autoVerify VIEW filter must exist. Multiple verified '
            'filters make Android require every declared path to verify.',
      );
      verifiedFilter = verified.single;
    });

    test('declares lynkshare.app over https only', () {
      final data = verifiedFilter
          .findElements('data')
          .where(
            (element) =>
                element.getAttribute('android:host') == 'lynkshare.app',
          )
          .toList();

      expect(data, isNotEmpty, reason: 'No data element for lynkshare.app');
      for (final element in data) {
        // .app is HSTS-preloaded: a plaintext filter would be unusable and
        // would fail verification.
        expect(element.getAttribute('android:scheme'), 'https');
      }
    });

    test('covers both the /send/ and /receive/ deep link prefixes', () {
      final prefixes = verifiedFilter
          .findElements('data')
          .map((element) => element.getAttribute('android:pathPrefix'))
          .whereType<String>()
          .toSet();

      expect(
        prefixes,
        containsAll(<String>['/send/', '/receive/']),
        reason:
            'A missing /receive/ prefix is why scanning a receiver QR opened '
            'the browser instead of the app.',
      );
    });

    test('does not over-claim paths the router cannot handle', () {
      final prefixes = verifiedFilter
          .findElements('data')
          .map((element) => element.getAttribute('android:pathPrefix'))
          .whereType<String>()
          .toSet();

      expect(prefixes, <String>{'/send/', '/receive/'});
    });
  });

  group('AndroidManifest lynk:// custom scheme', () {
    test('declares a VIEW filter for both offline hosts', () {
      final filter = filtersWhere(
        (element) =>
            isViewable(element) &&
            element
                .findElements('data')
                .any((data) => data.getAttribute('android:scheme') == 'lynk'),
      );

      expect(filter, hasLength(1), reason: 'Expected one lynk:// filter');

      final hosts = filter.single
          .findElements('data')
          .map((element) => element.getAttribute('android:host'))
          .whereType<String>()
          .toSet();

      expect(hosts, containsAll(<String>['send', 'receive']));
      // Custom schemes must not be verified; Android has no assetlinks
      // mechanism for them and autoVerify would be silently ignored.
      expect(filter.single.getAttribute('android:autoVerify'), isNull);
    });

    test('every declared host has a router mapping', () {
      // Mirrors normalizeCustomSchemeLink: unknown hosts are dropped on the
      // floor, so a host declared here without a mapping would open the app
      // and show the not-found screen.
      const routedHosts = <String>{'send', 'receive'};

      final filter = filtersWhere(
        (element) =>
            isViewable(element) &&
            element
                .findElements('data')
                .any((data) => data.getAttribute('android:scheme') == 'lynk'),
      ).single;

      final hosts = filter
          .findElements('data')
          .map((element) => element.getAttribute('android:host'))
          .whereType<String>();

      expect(hosts.every(routedHosts.contains), isTrue);
    });
  });

  group('activity launch behaviour', () {
    test('is singleTop so onNewIntent reuses the live router', () {
      // singleTop keeps the existing Flutter engine and router alive, which is
      // what makes warm-start links go through didPushRouteInformation instead
      // of a full restart. A different launchMode silently changes the
      // delivery path.
      expect(activity.getAttribute('android:launchMode'), 'singleTop');
    });

    test('is exported, or no external intent can reach it', () {
      expect(activity.getAttribute('android:exported'), 'true');
    });
  });

  group('Digital Asset Links', () {
    late List<dynamic> assetLinks;
    late String applicationId;

    setUpAll(() {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final match = RegExp(
        r'applicationId\s*=\s*"([^"]+)"',
      ).firstMatch(gradle);
      expect(match, isNotNull, reason: 'applicationId not found in Gradle');
      applicationId = match!.group(1)!;

      // Read only when the file is there; the tests that use it are skipped
      // otherwise, so a missing sibling checkout is not a failure.
      if (assetLinksFile.existsSync()) {
        assetLinks =
            jsonDecode(assetLinksFile.readAsStringSync()) as List<dynamic>;
      }
    });

    test(
      'declares the same package name the app is built with',
      () {
        final packages = assetLinks
            .cast<Map<String, dynamic>>()
            .map((entry) => (entry['target'] as Map)['package_name'])
            .toSet();

        expect(
          packages,
          contains(applicationId),
          reason:
              'Android only honours the statement whose package_name matches '
              'the installed applicationId.',
        );
      },
      skip: assetLinksSkipReason,
    );

    test(
      'grants handle_all_urls for that package',
      () {
        final statement = assetLinks
            .cast<Map<String, dynamic>>()
            .singleWhere(
              (entry) =>
                  (entry['target'] as Map)['package_name'] == applicationId,
            );

        expect(
          statement['relation'],
          contains('delegate_permission/common.handle_all_urls'),
        );
        expect((statement['target'] as Map)['namespace'], 'android_app');
      },
      skip: assetLinksSkipReason,
    );

    test(
      'lists at least one well-formed SHA-256 fingerprint',
      () {
        final fingerprints = assetLinks
            .cast<Map<String, dynamic>>()
            .expand(
              (entry) =>
                  ((entry['target'] as Map)['sha256_cert_fingerprints'] as List)
                      .cast<String>(),
            )
            .toList();

        expect(fingerprints, isNotEmpty);

        final sha256 = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');
        for (final fingerprint in fingerprints) {
          expect(
            sha256.hasMatch(fingerprint),
            isTrue,
            reason:
                'Fingerprints must be uppercase colon-separated SHA-256 digests; '
                'Android compares them literally. Offending value: $fingerprint',
          );
        }
      },
      skip: assetLinksSkipReason,
    );

    test(
      'lists Play app-signing and upload certificates separately',
      () {
        // Play re-signs distributed builds. A single fingerprint means either
        // Play-installed or locally-installed builds fail verification, and the
        // link silently falls back to the browser.
        final fingerprints = assetLinks
            .cast<Map<String, dynamic>>()
            .expand(
              (entry) =>
                  ((entry['target'] as Map)['sha256_cert_fingerprints'] as List)
                      .cast<String>(),
            )
            .toSet();

        expect(fingerprints.length, greaterThanOrEqualTo(2));
      },
      skip: assetLinksSkipReason,
    );
  });
}
