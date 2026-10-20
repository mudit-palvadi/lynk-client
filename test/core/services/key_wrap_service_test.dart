import 'package:client/core/services/key_wrap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = KeyWrapService();
  const aesKey = 'abcdefghijklmnopqrstuvwxyz123456'; // 32-byte UTF-8 key
  const sessionId = 'sess_abc123';

  group('KeyWrapService', () {
    test(
      'generateReceiverKeyPair returns base64url pubkey and 32-byte seed',
      () async {
        final pair = await service.generateReceiverKeyPair();

        expect(pair.publicKeyB64.isNotEmpty, isTrue);
        expect(decodeBase64Url(pair.publicKeyB64).length, 32);
        expect(pair.privateKeySeed.length, 32);
      },
    );

    test(
      'wrapKey output layout: 32B ephemeral pub + 12B nonce + ciphertext + 16B mac',
      () async {
        final pair = await service.generateReceiverKeyPair();

        final wrapped = await service.wrapKey(
          aesKey: aesKey,
          receiverPublicKeyB64: pair.publicKeyB64,
          sessionId: sessionId,
        );

        final bytes = decodeBase64Url(wrapped);
        // 32 eph pub + 12 nonce + 32 ct (key len) + 16 mac = 92
        expect(bytes.length, 92);
      },
    );

    test('round-trip: receiver unwraps to the original AES key', () async {
      final pair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: pair.publicKeyB64,
        sessionId: sessionId,
      );

      final unwrapped = await service.unwrapKey(
        wrappedBase64: wrapped,
        privateKeySeed: pair.privateKeySeed,
        sessionId: sessionId,
      );

      expect(unwrapped, equals(aesKey));
    });

    test('v2 wrap carries the access token and still returns the AES key', () async {
      final pair = await service.generateReceiverKeyPair();
      const accessToken = 'access-token-value';

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        accessToken: accessToken,
        receiverPublicKeyB64: pair.publicKeyB64,
        sessionId: sessionId,
      );

      final delivery = await service.unwrapDelivery(
        wrappedBase64: wrapped,
        privateKeySeed: pair.privateKeySeed,
        sessionId: sessionId,
      );

      expect(delivery.aesKey, aesKey);
      expect(delivery.accessToken, accessToken);
      expect(
        await service.unwrapKey(
          wrappedBase64: wrapped,
          privateKeySeed: pair.privateKeySeed,
          sessionId: sessionId,
        ),
        aesKey,
      );
    });

    test(
      'two wraps of the same key produce different blobs (ephemeral)',
      () async {
        final pair = await service.generateReceiverKeyPair();

        final w1 = await service.wrapKey(
          aesKey: aesKey,
          receiverPublicKeyB64: pair.publicKeyB64,
          sessionId: sessionId,
        );
        final w2 = await service.wrapKey(
          aesKey: aesKey,
          receiverPublicKeyB64: pair.publicKeyB64,
          sessionId: sessionId,
        );

        expect(w1, isNot(equals(w2)));
      },
    );

    test('unwrap fails when blob is tampered', () async {
      final pair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: pair.publicKeyB64,
        sessionId: sessionId,
      );

      final bytes = decodeBase64Url(wrapped);
      bytes[40] ^= 0xFF; // corrupt ciphertext byte
      final tampered = encodeBase64Url(bytes);

      expect(
        () => service.unwrapKey(
          wrappedBase64: tampered,
          privateKeySeed: pair.privateKeySeed,
          sessionId: sessionId,
        ),
        throwsA(anything),
      );
    });

    test('unwrap fails with wrong session id (AAD mismatch)', () async {
      final pair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: pair.publicKeyB64,
        sessionId: sessionId,
      );

      expect(
        () => service.unwrapKey(
          wrappedBase64: wrapped,
          privateKeySeed: pair.privateKeySeed,
          sessionId: 'different-session',
        ),
        throwsA(anything),
      );
    });
  });
}
