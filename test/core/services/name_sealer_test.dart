import 'package:client/core/services/name_sealer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NameSealer (#32)', () {
    const key = '0123456789abcdef0123456789abcdef';
    const otherKey = 'ffffffffffffffffffffffffffffffff';

    test('seals and opens a file name with the transfer key', () {
      final token = NameSealer.seal('holiday photo.jpg', key);

      expect(token, isNotNull);
      expect(token, isNot(contains('holiday')));
      expect(NameSealer.open(token!, key), 'holiday photo.jpg');
    });

    test('every seal uses a fresh IV', () {
      final first = NameSealer.seal('a.txt', key);
      final second = NameSealer.seal('a.txt', key);

      expect(first, isNot(second));
      expect(NameSealer.open(first!, key), 'a.txt');
      expect(NameSealer.open(second!, key), 'a.txt');
    });

    test('rejects a key that is not 32 bytes (#46)', () {
      // The old rule padded a short key with '0', so 'short-key' and
      // 'short-key000...' sealed the same way.
      expect(
        () => NameSealer.seal('report.pdf', 'short-key'),
        throwsArgumentError,
      );
      expect(
        () => NameSealer.seal('report.pdf', '$key extra'),
        throwsArgumentError,
      );
      // 32 characters, but 64 UTF-8 bytes.
      expect(
        () => NameSealer.seal('report.pdf', 'é' * 32),
        throwsArgumentError,
      );
      // A key the wrong length opens nothing rather than guessing.
      expect(NameSealer.open('AAAA', 'short-key'), isNull);
    });

    test('accepts a valid key with surrounding whitespace', () {
      final token = NameSealer.seal('report.pdf', '  $key  ');

      expect(NameSealer.open(token!, key), 'report.pdf');
    });

    test('another key never reveals the name', () {
      final token = NameSealer.seal('a.txt', key)!;

      expect(NameSealer.open(token, otherKey), isNot('a.txt'));
    });

    test('a missing key seals and opens nothing', () {
      expect(NameSealer.seal('a.txt', null), isNull);
      expect(NameSealer.seal('a.txt', ''), isNull);
      expect(NameSealer.open('AAAA', null), isNull);
    });

    test('a malformed or truncated token opens nothing', () {
      expect(NameSealer.open('not base64 !!', key), isNull);
      expect(NameSealer.open('AAAA', key), isNull);
    });
  });
}
