import 'package:client/core/services/key_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a public key has a stable eight-digit check', () {
    expect(
      keyFingerprint('receiver-public-key-000000000000000000'),
      '00f5 cb04',
    );
  });

  test('a different public key has a different check', () {
    expect(
      keyFingerprint('another-public-key-111111111111111111'),
      isNot('00f5 cb04'),
    );
  });
}
