import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The client must never contact the project's hosted API by default. Local
/// development uses a contributor-owned backend, and a missing `API_BASE_URL`
/// is a configuration error rather than a fallback.
void main() {
  const productionApiHost = 'api.lynkshare.app';

  Iterable<File> dartSources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  test('no client source references the production API', () {
    for (final file in dartSources()) {
      expect(
        file.readAsStringSync(),
        isNot(contains(productionApiHost)),
        reason: '${file.path} still references the production API',
      );
    }
  });

  test('the README does not send contributors to the production API', () {
    expect(
      File('README.md').readAsStringSync(),
      isNot(contains(productionApiHost)),
    );
  });

  test('API_BASE_URL is read in exactly one place', () {
    final readers = dartSources()
        .where(
          (file) => file.readAsStringSync().contains("env['API_BASE_URL']"),
        )
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    expect(readers, ['lib/core/services/config_service.dart']);
  });
}
