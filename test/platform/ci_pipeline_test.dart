import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Guards the CI workflow that gates merges.
///
/// The workflow is the only thing standing between a broken build and main,
/// and a workflow fails silently: delete a step, add `continue-on-error`, or
/// narrow the trigger to a branch nobody pushes to, and every pull request
/// turns green without anything being tested. These tests read the workflow
/// file and assert the properties that make it a gate.
void main() {
  final file = File('.github/workflows/ci.yml');
  final contents = file.readAsStringSync();
  final workflow = loadYaml(contents) as YamlMap;

  /// The trigger block. YAML 1.1 readers resolve a bare `on` key to the
  /// boolean true, so both spellings are accepted.
  final triggers = (workflow['on'] ?? workflow[true]) as YamlMap;

  final jobs = workflow['jobs'] as YamlMap;
  final steps = <YamlMap>[
    for (final job in jobs.values)
      ...((job as YamlMap)['steps'] as List).cast<YamlMap>(),
  ];

  final runCommands = steps
      .map((step) => step['run'])
      .whereType<String>()
      .toList();

  group('CI triggers', () {
    test('runs on every push to main', () {
      final push = triggers['push'] as YamlMap?;

      expect(push, isNotNull, reason: 'a push trigger is required');
      expect(push!['branches'], contains('main'));
    });

    test('runs on every pull request', () {
      // `pull_request:` with no body is a null value, so the key has to be
      // checked rather than the value.
      expect(
        triggers.containsKey('pull_request'),
        isTrue,
        reason:
            'without a pull_request trigger a change can reach main without '
            'ever being tested',
      );
    });

    test('can be started by hand', () {
      expect(triggers.containsKey('workflow_dispatch'), isTrue);
    });

    test('cancels a superseded run for the same ref', () {
      final concurrency = workflow['concurrency'] as YamlMap?;

      expect(concurrency, isNotNull);
      expect(concurrency!['cancel-in-progress'], isTrue);
    });
  });

  group('CI is a real gate', () {
    test('no step is allowed to continue on error', () {
      for (final step in steps) {
        expect(
          step['continue-on-error'],
          isNot(true),
          reason:
              'a step with continue-on-error cannot fail the run, so the '
              'pipeline would report green while the check it performs is '
              'broken',
        );
      }
    });

    test('the token is read-only', () {
      final permissions = workflow['permissions'] as YamlMap?;

      expect(permissions, isNotNull);
      expect(permissions!['contents'], 'read');
    });
  });

  group('CI runs the client checks', () {
    test('analyzes the code', () {
      expect(
        runCommands.any((command) => command.contains('flutter analyze')),
        isTrue,
      );
    });

    test('runs the test suite', () {
      expect(
        runCommands.any((command) => command.contains('flutter test')),
        isTrue,
      );
    });

    test('installs the packages the tests need', () {
      expect(
        runCommands.any((command) => command.contains('flutter pub get')),
        isTrue,
      );
    });

    test('pins the Flutter version', () {
      // An unpinned SDK means the suite can break when Flutter ships, with
      // no change in this repository to blame.
      final setup = steps.firstWhere(
        (step) => (step['uses'] as String?)?.contains('flutter-action') ?? false,
      );
      final setupOptions = setup['with'] as YamlMap;

      expect(setupOptions['flutter-version'], isNotNull);
      expect(setupOptions['flutter-version'], isNot('any'));
    });
  });

  group('CI can actually run', () {
    test('creates the .env the asset bundle needs', () {
      // pubspec.yaml lists .env under assets; without the file the asset
      // bundle fails to build and every test dies before it starts.
      expect(
        runCommands.any((command) => command.contains('.env')),
        isTrue,
        reason: 'the .env asset must be created before flutter test runs',
      );
    });

    test('does not put a secret in the workflow', () {
      for (final command in runCommands) {
        expect(command, isNot(contains('DEV_CONFIG_KEY')));
        expect(command, isNot(contains('key.properties')));
        expect(command, isNot(contains('keystore')));
      }
    });
  });
}
