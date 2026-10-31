import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final workflows =
      (loadYaml(File('codemagic.yaml').readAsStringSync())
              as YamlMap)['workflows']
          as YamlMap;

  String scripts(YamlMap workflow) => (workflow['scripts'] as YamlList)
      .map((step) => (step as YamlMap)['script'])
      .join('\n');

  test('the manual Play baseline is built with Shorebird', () {
    final release = workflows['lynk-android-release'] as YamlMap;
    final commands = scripts(release);
    expect(release['triggering'], isNull);
    expect(commands, contains('shorebird release android'));
    expect(commands, contains('--flutter-version'));
    expect(commands, contains('--build-number'));
    expect(commands, contains('--obfuscate'));
    expect(commands, contains('--split-debug-info'));
    expect(commands, isNot(contains('shorebird login:ci')));
    expect(release['publishing']['google_play']['track'], 'beta');
  });

  test('CI authenticates with an API key and not an obsolete login token', () {
    final release = workflows['lynk-android-release'] as YamlMap;
    expect(release['environment']['groups'], contains('shorebird'));
    expect(scripts(release), contains('SHOREBIRD_TOKEN'));
    expect(scripts(release), isNot(contains('shorebird login:ci')));
  });
}
