import 'dart:convert';

import 'package:client/core/utils/entropy_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntropyGenerator.generateKey', () {
    test('returns 32 lowercase hex characters', () async {
      final key = await EntropyGenerator.generateKey();

      expect(key, hasLength(32));
      expect(key, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('is 32 bytes of raw UTF-8, which is what AES-256 needs', () async {
      final key = await EntropyGenerator.generateKey();

      expect(utf8.encode(key), hasLength(32));
    });

    test('is not reproducible', () async {
      // POTENTIAL_ISSUES #26: the old key was a hash of the device UUID, a
      // clock-derived "temperature" and the timestamp, so it could be rebuilt
      // from the send time. A fresh key every time is the point.
      final keys = <String>{};
      for (var i = 0; i < 50; i++) {
        keys.add(await EntropyGenerator.generateKey());
      }

      expect(keys, hasLength(50));
    });
  });
}
