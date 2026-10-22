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

    test('a name sealed on the web opens with the same key rules', () {
      // The web's sanitizeKey pads a short key with '0' the same way.
      final token = NameSealer.seal('report.pdf', 'short-key');

      expect(NameSealer.open(token!, 'short-key'), 'report.pdf');
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
