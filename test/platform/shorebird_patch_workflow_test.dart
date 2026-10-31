import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('patches are manual, staging-only and never publish to Play', () {
    final workflows = loadYaml(
      File('codemagic.yaml').readAsStringSync(),
    )['workflows'];
    final patch = workflows['lynk-android-patch'] as YamlMap;
    final commands = (patch['scripts'] as YamlList)
        .map((step) => step['script'])
        .join('\n');
    expect(patch['triggering'], isNull);
    expect(patch['publishing'], isNull);
    expect(patch['environment']['groups'], contains('shorebird'));
    expect(commands, contains('SHOREBIRD_TOKEN'));
    expect(commands, isNot(contains('shorebird login:ci')));
    expect(commands, contains('shorebird patch android'));
    expect(commands, contains('--release-version'));
    expect(commands, contains('SHOREBIRD_RELEASE_VERSION'));
    expect(commands, contains('--track staging'));
    expect(commands, isNot(contains('PROJECT_BUILD_NUMBER')));
    expect(commands, isNot(contains('--allow-native-diffs')));
    expect(commands, isNot(contains('--allow-asset-diffs')));
  });
}
