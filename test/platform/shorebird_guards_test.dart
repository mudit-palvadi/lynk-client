import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final workflows = loadYaml(
    File('codemagic.yaml').readAsStringSync(),
  )['workflows'];
  final release = workflows['lynk-android-release'] as YamlMap;
  final patch = workflows['lynk-android-patch'] as YamlMap;

  String script(YamlMap workflow, String name) =>
      (workflow['scripts'] as YamlList).singleWhere(
            (step) => step['name'] == name,
          )['script']
          as String;

  ProcessResult run(
    String command, {
    Map<String, String> variables = const {},
    String contents = 'API_BASE_URL=https://api.example.test/api/v1/\n',
  }) {
    final directory = Directory.systemTemp.createTempSync('lynk-shorebird-ci-');
    try {
      File('${directory.path}/.env').writeAsStringSync(contents);
      File('${directory.path}/.admob-release.env').writeAsStringSync('');
      final environment = Map<String, String>.of(Platform.environment)
        ..removeWhere(
          (key, _) =>
              key.startsWith('SHOREBIRD_') || key == 'PROJECT_BUILD_NUMBER',
        )
        ..addAll({
          'CM_BUILD_DIR': directory.path.replaceAll('\\', '/'),
          ...variables,
        });
      // Shadow only the publication boundary. No actual Shorebird operation,
      // login, native build or network call can run in this harness.
      final wrapped =
          '''
shorebird() { printf '%s\\n' "\$@"; }
$command
''';
      return Process.runSync(
        Platform.isWindows ? r'C:\Program Files\Git\bin\bash.exe' : 'bash',
        ['-c', wrapped],
        workingDirectory: directory.path,
        environment: environment,
        includeParentEnvironment: false,
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  const digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const valid = {
    'SHOREBIRD_RELEASE_VERSION': '0.1.0+137',
    'SHOREBIRD_ENV_SHA256': digest,
  };

  test('patch validation refuses missing, latest and malformed baselines', () {
    final validate = script(patch, 'Validate exact patch baseline');
    for (final version in [
      '',
      'latest',
      '0.1.0',
      '0.1.0+abc',
      '0.1.0+7; exit 0',
    ]) {
      expect(
        run(
          validate,
          variables: {...valid, 'SHOREBIRD_RELEASE_VERSION': version},
        ).exitCode,
        isNot(0),
        reason: 'invalid baseline accepted',
      );
    }
    expect(run(validate, variables: valid).exitCode, 0);
  });

  test('patch validation requires the baseline configuration fingerprint', () {
    final validate = script(patch, 'Validate exact patch baseline');
    for (final value in ['', 'abc', 'A' * 64]) {
      expect(
        run(
          validate,
          variables: {...valid, 'SHOREBIRD_ENV_SHA256': value},
        ).exitCode,
        isNot(0),
      );
    }
  });

  test('bundled configuration must match the actual baseline hash', () {
    const contents = 'API_BASE_URL=https://api.example.test/api/v1/\n';
    final hash = sha256.convert(utf8.encode(contents)).toString();
    final check = script(patch, 'Verify unchanged bundled configuration');
    expect(run(check, variables: {'SHOREBIRD_ENV_SHA256': hash}).exitCode, 0);
    expect(run(check, variables: valid).exitCode, isNot(0));
  });

  test(
    'missing CI authentication fails before installation or publication',
    () {
      for (final workflow in [release, patch]) {
        expect(
          run(script(workflow, 'Install pinned Shorebird CLI')).exitCode,
          isNot(0),
        );
      }
    },
  );

  test('baseline retains the current SDK, obfuscation and version counter', () {
    final result = run(
      script(release, 'Build release AAB'),
      variables: {'PROJECT_BUILD_NUMBER': '37'},
    );
    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains('release\nandroid\n--flutter-version=3.44.6'),
    );
    expect(result.stdout, contains('--build-number=137'));
    expect(result.stdout, contains('--obfuscate'));
    expect(result.stdout, contains('--split-debug-info=build/symbols'));
  });

  test(
    'patch command targets exactly one baseline and staging, without increment',
    () {
      final result = run(
        script(patch, 'Build and publish a staging patch'),
        variables: valid,
      );
      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('patch\nandroid\n--release-version=0.1.0+137'),
      );
      expect(result.stdout, contains('--track\nstaging'));
      expect(result.stdout, contains('--build-name=0.1.0'));
      expect(result.stdout, contains('--build-number=137'));
      expect(result.stdout, isNot(contains('--allow-native-diffs')));
      expect(result.stdout, isNot(contains('--allow-asset-diffs')));
    },
  );

  test(
    'both workflows verify the upload keystore before publishing to Shorebird',
    () {
      for (final workflow in [release, patch]) {
        final steps = workflow['scripts'] as YamlList;
        final names = steps.map((step) => step['name']).toList();
        final verify = names.indexOf(
          'Verify upload keystore before Shorebird publication',
        );
        final publish = names.indexOf(
          workflow == release
              ? 'Build release AAB'
              : 'Build and publish a staging patch',
        );
        expect(verify, greaterThanOrEqualTo(0));
        expect(verify, lessThan(publish));
        expect(
          script(workflow, names[verify] as String),
          contains('-storepass:env CM_KEYSTORE_PASSWORD'),
        );
        expect(
          script(workflow, 'Verify release upload signing certificate'),
          contains('jar verified'),
        );
      }
      expect(patch['environment']['groups'], isNot(contains('google_play')));
      expect(patch['publishing'], isNull);
    },
  );
}
