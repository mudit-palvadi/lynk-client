import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Guards the hardening of the Android release build (POTENTIAL_ISSUES #36).
///
/// A release APK is shipped to every user, so anything that only exists in
/// the release variant is a real defect rather than a style question:
///
///  * cleartext HTTP allowed, so any traffic could be read on the wire
///  * Google's sample AdMob app id, so the shipped app shows test ads
///  * the ad-bypass key baked into the binary
///  * no shrinking or obfuscation, so the APK carries every class name and
///    every Dart symbol
///
/// These are build-configuration contracts, so they are asserted against the
/// files themselves.
void main() {
  final manifest = XmlDocument.parse(
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
  );
  final debugManifest = XmlDocument.parse(
    File('android/app/src/debug/AndroidManifest.xml').readAsStringSync(),
  );
  final profileManifest = XmlDocument.parse(
    File('android/app/src/profile/AndroidManifest.xml').readAsStringSync(),
  );
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final codemagic = File('codemagic.yaml').readAsStringSync();

  XmlElement applicationOf(XmlDocument document) =>
      document.findAllElements('application').single;

  String? metaDataValue(XmlDocument document, String name) {
    for (final element in document.findAllElements('meta-data')) {
      if (element.getAttribute('android:name') == name) {
        return element.getAttribute('android:value');
      }
    }
    return null;
  }

  group('cleartext traffic', () {
    test('the release manifest forbids cleartext', () {
      expect(
        applicationOf(manifest).getAttribute('android:usesCleartextTraffic'),
        'false',
        reason:
            'A release app must not allow plaintext HTTP. Debug builds get an '
            'explicit override; the release variant does not.',
      );
    });

    test('the debug manifest re-enables cleartext for local development', () {
      expect(
        applicationOf(debugManifest).getAttribute('android:usesCleartextTraffic'),
        'true',
      );
    });

    test('the profile manifest keeps cleartext off', () {
      expect(
        applicationOf(profileManifest)
            .getAttribute('android:usesCleartextTraffic'),
        'false',
      );
    });
  });

  group('AdMob application id', () {
    test('the manifest takes the id from Gradle, not a literal', () {
      expect(
        metaDataValue(manifest, 'com.google.android.gms.ads.APPLICATION_ID'),
        r'${admobAppId}',
      );
    });

    test("Google's sample app id is not hard-coded in the manifest", () {
      expect(
        File('android/app/src/main/AndroidManifest.xml')
            .readAsStringSync()
            .contains('ca-app-pub-3940256099942544~3347511713'),
        isFalse,
      );
    });

    test('a release build fails without a real app id', () {
      expect(gradle, contains('requireReleaseAdMobAppId'));
      expect(gradle, contains('isSampleAdMobAppId'));
      expect(gradle, contains('GradleException'));
    });

    test('the release pipeline injects the real id', () {
      expect(codemagic, contains('ORG_GRADLE_PROJECT_admobAppId'));
      expect(codemagic, contains('ADMOB_APP_ID'));
    });

    test('the release pipeline refuses a missing or sample ad configuration', () {
      expect(codemagic, contains('Verify release configuration'));
      expect(
        codemagic,
        contains('ca-app-pub-3940256099942544~3347511713'),
        reason:
            'The verification step has to recognise the sample id in order '
            'to reject it.',
      );
    });

    test('every ad unit id is supplied to the release build', () {
      for (final variable in const [
        'ADMOB_APP_ID',
        'ADMOB_BANNER_ID',
        'ADMOB_INTERSTITIAL_ID',
        'ADMOB_REWARDED_ID',
        'ADMOB_REWARDED_INTERSTITIAL_ID',
      ]) {
        expect(codemagic, contains(variable));
      }
    });
  });

  group('shrinking and obfuscation', () {
    test('the release build type shrinks and obfuscates', () {
      expect(gradle, contains('isMinifyEnabled = true'));
      expect(gradle, contains('isShrinkResources = true'));
    });

    test('the release pipeline obfuscates the Dart code', () {
      expect(codemagic, contains('--obfuscate'));
      expect(codemagic, contains('--split-debug-info'));
    });
  });

  group('the ad bypass is not shipped', () {
    // The name may still appear in a comment that explains the history; what
    // must not exist is code that reads the key out of the environment.
    final environmentRead = RegExp(
      r"""env\[\s*['"]DEV_CONFIG_KEY['"]\s*\]""",
    );

    test('no source file reads DEV_CONFIG_KEY', () {
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in sources) {
        expect(
          environmentRead.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: '${file.path} still reads the bypass key from the environment',
        );
      }
    });

    test('the bypass key is a compile-time define behind a debug guard', () {
      final configService =
          File('lib/core/services/config_service.dart').readAsStringSync();

      expect(configService, contains('String.fromEnvironment('));
      expect(configService, contains('LYNK_DEBUG_BYPASS_KEY'));
      expect(configService, contains('kDebugMode'));
    });

    test('the release pipeline never sets the bypass key', () {
      expect(
        RegExp(r'DEV_CONFIG_KEY\s*=').hasMatch(codemagic),
        isFalse,
        reason: 'the pipeline must not put the bypass key into the build',
      );
      expect(
        RegExp(r'LYNK_DEBUG_BYPASS_KEY\s*=').hasMatch(codemagic),
        isFalse,
      );
    });

    test('the local .env does not carry the bypass key', () {
      final env = File('.env');
      if (!env.existsSync()) {
        // A fresh checkout has no .env; the pipeline writes one before the
        // tests run, and the tracked files are checked above.
        return;
      }
      expect(
        RegExp(r'DEV_CONFIG_KEY\s*=').hasMatch(env.readAsStringSync()),
        isFalse,
      );
    });
  });
}
