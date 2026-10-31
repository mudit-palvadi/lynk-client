import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'the registered Shorebird identity is bundled with background updates',
    () {
      final registration = loadYaml(File('shorebird.yaml').readAsStringSync());
      expect(registration['app_id'], 'e0d614ae-2b54-45d5-b7ac-63dd5133f8f0');
      final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync());
      expect(pubspec['flutter']['assets'], contains('shorebird.yaml'));
      expect(registration['auto_update'], isNot(false));
    },
  );
}
