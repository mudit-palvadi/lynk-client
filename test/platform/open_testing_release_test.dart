import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('codemagic.yaml').readAsStringSync();
  final block = workflow
      .split('      - name: Resolve AdMob configuration\n')
      .last
      .split('      - name: Recreate .env')
      .first;
  final script = block
      .split('        script: |\n')
      .last
      .split('\n')
      .map((line) => line.startsWith('          ') ? line.substring(10) : line)
      .join('\n');
  const names = [
    'ADMOB_APP_ID',
    'ADMOB_BANNER_ID',
    'ADMOB_INTERSTITIAL_ID',
    'ADMOB_REWARDED_ID',
    'ADMOB_REWARDED_INTERSTITIAL_ID',
  ];
  // Public fixture values, not a configured AdMob account.
  final valid = <String, String>{
    for (var i = 0; i < names.length; i++)
      names[i]: 'ca-app-pub-1234567890123456${i == 0 ? '~' : '/'}123456789$i',
  };

  ProcessResult resolve(
    Map<String, String> configuration, {
    bool readOutput = false,
  }) {
    final directory = Directory.systemTemp.createTempSync('lynk-ad-config-');
    try {
      final environment = Map<String, String>.of(Platform.environment)
        ..removeWhere(
          (key, _) =>
              key.startsWith('ADMOB_') ||
              key.startsWith('ORG_GRADLE_PROJECT_') ||
              key == 'GOOGLE_PLAY_TRACK',
        )
        ..addAll({
          'CM_BUILD_DIR': directory.path.replaceAll('\\', '/'),
          ...configuration,
        });
      return Process.runSync(
        Platform.isWindows ? r'C:\Program Files\Git\bin\bash.exe' : 'bash',
        [
          '-c',
          '$script${readOutput ? '\ncat "\$CM_BUILD_DIR/.admob-release.env"' : ''}',
        ],
        environment: environment,
        // Codemagic exports the real AdMob IDs before flutter test. Removing
        // them from this map does not unset them while the parent environment
        // is still inherited.
        includeParentEnvironment: false,
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  group('open testing release configuration', () {
    test('publishes manually to beta rather than production or alpha', () {
      expect(workflow, contains('track: beta'));
      expect(workflow, contains('Open Testing'));
      expect(
        RegExp(r'^    triggering:', multiLine: true).hasMatch(workflow),
        isFalse,
      );
    });
    test('missing AdMob configuration cannot produce a release', () {
      expect(resolve({}).exitCode, isNot(0));
    });
    test('partial AdMob configuration cannot produce a release', () {
      expect(
        resolve({'ADMOB_APP_ID': valid['ADMOB_APP_ID']!}).exitCode,
        isNot(0),
      );
    });
    test('Google sample publisher cannot be shipped as live configuration', () {
      final sample = valid.map(
        (key, value) => MapEntry(
          key,
          value.replaceAll('1234567890123456', '3940256099942544'),
        ),
      );
      expect(resolve(sample).exitCode, isNot(0));
    });
    test('every configured ID must have the correct format', () {
      for (final name in names) {
        expect(
          resolve({...valid, name: 'invalid-id'}).exitCode,
          isNot(0),
          reason: name,
        );
      }
    });
    test('a production track override is refused', () {
      expect(
        resolve({...valid, 'GOOGLE_PLAY_TRACK': 'production'}).exitCode,
        isNot(0),
      );
    });
    test('syntactically valid configuration succeeds without changing IDs', () {
      final result = resolve(valid, readOutput: true);
      expect(result.exitCode, 0);
      for (final entry in valid.entries) {
        expect(result.stdout, contains('export ${entry.key}="${entry.value}"'));
      }
    });
    test('IDs from different publisher accounts are refused', () {
      expect(
        resolve({
          ...valid,
          'ADMOB_BANNER_ID': 'ca-app-pub-9876543210987654/1234567891',
        }).exitCode,
        isNot(0),
      );
    });
    test('a sample unit cannot be mixed with a real application ID', () {
      expect(
        resolve({
          ...valid,
          'ADMOB_BANNER_ID': 'ca-app-pub-3940256099942544/6300978111',
        }).exitCode,
        isNot(0),
      );
    });
    test('closed testing cannot override the intended open track', () {
      expect(
        resolve({...valid, 'GOOGLE_PLAY_TRACK': 'alpha'}).exitCode,
        isNot(0),
      );
    });
    test('configured public identifiers match the supplied AdMob account', () {
      for (final id in [
        'ca-app-pub-9472143004063972~5082510676',
        'ca-app-pub-9472143004063972/3345777238',
        'ca-app-pub-9472143004063972/9528042202',
        'ca-app-pub-9472143004063972/1768498260',
        'ca-app-pub-9472143004063972/5516171584',
      ]) {
        expect(workflow, contains(id));
      }
      expect(
        workflow,
        contains('keytool -J-Duser.language=en -printcert -jarfile'),
      );
      expect(
        workflow,
        contains(
          '74:25:40:24:ED:53:EF:1F:A7:8F:00:B7:D1:72:7B:6A:CC:4B:12:B9:20:8D:EB:8D:48:11:58:6C:6C:C8:F0:94',
        ),
      );
    });
    test('release signing cannot silently select the debug key', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    });
  });
}
