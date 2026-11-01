import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Guards the two release-safety contracts from issue #73:
///
///  * the app keeps transfer names/paths, the device id and the folder URI in
///    app-private storage, so Android backup and device transfer must be off;
///  * a release build must be signed with the upload keystore, never with the
///    debug key, and a missing/incomplete key.properties must fail the build.
///
/// Both are build-configuration contracts, so they are asserted against the
/// manifest, the extraction rules and the Gradle build file themselves.
void main() {
  final manifest = XmlDocument.parse(
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
  );
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  XmlElement applicationOf(XmlDocument document) =>
      document.findAllElements('application').single;

  /// Returns the body of the first `name { ... }` block, with nested braces
  /// balanced so inner blocks do not truncate the result.
  String block(String source, String name) {
    final match = RegExp('\\b${RegExp.escape(name)}\\s*\\{').firstMatch(source);
    if (match == null) {
      throw StateError('expected a $name { ... } block');
    }
    var depth = 1;
    var index = match.end;
    while (index < source.length && depth > 0) {
      final character = source[index];
      if (character == '{') depth++;
      if (character == '}') depth--;
      index++;
    }
    if (depth != 0) {
      throw StateError('unbalanced braces in the $name block');
    }
    return source.substring(match.end, index - 1);
  }

  group('Android backup is disabled', () {
    test('the manifest turns backup off', () {
      expect(
        applicationOf(manifest).getAttribute('android:allowBackup'),
        'false',
        reason:
            'recent transfer names/paths, the device id and the folder URI '
            'must not leave the device through a backup',
      );
    });

    test('debug and profile variants do not re-enable backup', () {
      for (final variant in const ['debug', 'profile']) {
        final variantManifest = XmlDocument.parse(
          File(
            'android/app/src/$variant/AndroidManifest.xml',
          ).readAsStringSync(),
        );
        expect(
          applicationOf(variantManifest).getAttribute('android:allowBackup'),
          isNot('true'),
          reason: '$variant builds must not opt back into backup',
        );
      }
    });

    test('the Android 12+ extraction rules exclude every domain', () {
      final rulesPath = applicationOf(
        manifest,
      ).getAttribute('android:dataExtractionRules');
      expect(rulesPath, '@xml/data_extraction_rules');

      final rulesFile = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      );
      expect(rulesFile.existsSync(), isTrue);

      final rules = XmlDocument.parse(rulesFile.readAsStringSync());
      const expectedDomains = {
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
        'device_root',
        'device_file',
        'device_database',
        'device_sharedpref',
      };

      for (final section in const ['cloud-backup', 'device-transfer']) {
        final element = rules.findAllElements(section).single;
        expect(
          element.findElements('include'),
          isEmpty,
          reason: '$section must not include anything',
        );
        final excluded = element
            .findElements('exclude')
            .map((exclude) => exclude.getAttribute('domain'))
            .toSet();
        expect(
          excluded,
          containsAll(expectedDomains),
          reason: '$section must exclude every data domain',
        );
      }
    });
  });

  group('Release signing never falls back to debug', () {
    final buildTypes = block(gradle, 'buildTypes');
    final release = block(buildTypes, 'release');
    final debug = block(buildTypes, 'debug');

    test('the release build type uses the release signing config', () {
      expect(
        release,
        contains('signingConfig = signingConfigs.getByName("release")'),
      );
    });

    test('the release build type never references the debug config', () {
      expect(release, isNot(contains('getByName("debug")')));
      expect(release, isNot(contains('signingConfigs.debug')));
    });

    test('debug builds still use the debug signing config', () {
      expect(
        debug,
        contains('signingConfig = signingConfigs.getByName("debug")'),
      );
    });

    test(
      'the debug config is selected exactly once, inside the debug block',
      () {
        final selections = RegExp(
          r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        ).allMatches(gradle);
        expect(selections, hasLength(1));
      },
    );

    test('a release without key.properties fails closed', () {
      expect(gradle, contains('fun requireReleaseSigning()'));
      expect(gradle, contains('keystorePropertiesFile.exists()'));
      expect(gradle, contains('android/key.properties'));
      expect(
        gradle,
        contains('Refusing to fall back to the debug signing key'),
      );
    });

    test('every signing property is required for a release', () {
      for (final property in const [
        'keyAlias',
        'keyPassword',
        'storeFile',
        'storePassword',
      ]) {
        expect(
          gradle,
          contains('"$property"'),
          reason: '$property must be validated as a required signing value',
        );
      }
    });

    test('release tasks validate signing before anything else', () {
      final hook = block(gradle, 'doFirst');
      expect(hook, contains('requireReleaseSigning()'));
      expect(hook, contains('requireReleaseAdMobAppId()'));
      expect(
        hook.indexOf('requireReleaseSigning()'),
        lessThan(hook.indexOf('requireReleaseAdMobAppId()')),
      );
    });
  });
}
