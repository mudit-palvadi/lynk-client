import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:client/core/services/key_wrap_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the zero-knowledge key hand-off still interoperates with the format
/// documented in `KeyWrapService`.
///
/// The usual way to test crypto is to call the production code on both sides.
/// That proves nothing: if the derivation, the byte order or the AAD were
/// wrong, both sides would still agree with each other and every P2P transfer
/// would fail in the field.
///
/// So both sides are re-implemented here, from the wire format description
/// only:
///
/// ```text
/// KEK  = HKDF-SHA256(ikm = ECDH(ephemeral, receiver), salt = sessionId,
///                    info = "lynk-wrapped-key-v1", length = 32)
/// body = AES-256-GCM(key = UTF-8(aesKey), nonce = 12 random bytes,
///                    aad = sessionId)
/// wire = [32 B ephemeral public key][12 B nonce][ciphertext][16 B tag]
/// ```
///
/// The test then crosses the two implementations in both directions.
void main() {
  const aesKey = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
  const sessionId = 'session-under-test';

  late KeyWrapService service;

  setUp(() {
    service = KeyWrapService();
  });

  group('wrapped key interoperability', () {
    test('the app unwraps a key produced by an independent sender', () async {
      final keyPair = await service.generateReceiverKeyPair();

      final wrapped = await _IndependentSender().wrap(
        aesKey: aesKey,
        receiverPublicKeyB64: keyPair.publicKeyB64,
        sessionId: sessionId,
      );

      final unwrapped = await service.unwrapKey(
        wrappedBase64: wrapped,
        privateKeySeed: keyPair.privateKeySeed,
        sessionId: sessionId,
      );

      expect(unwrapped, aesKey);
    });

    test('an independent receiver unwraps a key produced by the app', () async {
      final keyPair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: keyPair.publicKeyB64,
        sessionId: sessionId,
      );

      final unwrapped = await _IndependentReceiver().unwrap(
        wrappedBase64: wrapped,
        privateKeySeed: keyPair.privateKeySeed,
        sessionId: sessionId,
      );

      expect(unwrapped, aesKey);
    });

    test('the app round-trips its own wrapped key', () async {
      final keyPair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: keyPair.publicKeyB64,
        sessionId: sessionId,
      );

      expect(
        await service.unwrapKey(
          wrappedBase64: wrapped,
          privateKeySeed: keyPair.privateKeySeed,
          sessionId: sessionId,
        ),
        aesKey,
      );
    });
  });

  group('wrapped key wire format', () {
    test('is base64url without padding', () async {
      final keyPair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: keyPair.publicKeyB64,
        sessionId: sessionId,
      );

      expect(wrapped, isNot(contains('=')));
      expect(wrapped, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test(
      'is 32 byte ephemeral key, 12 byte nonce, ciphertext and 16 byte tag',
      () async {
        final keyPair = await service.generateReceiverKeyPair();

        final wrapped = await service.wrapKey(
          aesKey: aesKey,
          receiverPublicKeyB64: keyPair.publicKeyB64,
          sessionId: sessionId,
        );

        final bytes = _decodeBase64Url(wrapped);
        expect(bytes.length, 32 + 12 + aesKey.length + 16);
      },
    );

    test('a short payload is rejected instead of crashing', () async {
      final keyPair = await service.generateReceiverKeyPair();

      expect(
        () => service.unwrapKey(
          wrappedBase64: _encodeBase64Url(List<int>.filled(10, 0)),
          privateKeySeed: keyPair.privateKeySeed,
          sessionId: sessionId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('wrapped key is bound to the session', () {
    test('a different session id cannot unwrap the key', () async {
      final keyPair = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: keyPair.publicKeyB64,
        sessionId: sessionId,
      );

      // The session id is both the HKDF salt and the GCM aad, so replaying a
      // wrapped key against another session must fail rather than decrypt.
      expect(
        () => service.unwrapKey(
          wrappedBase64: wrapped,
          privateKeySeed: keyPair.privateKeySeed,
          sessionId: 'another-session',
        ),
        throwsA(anything),
      );
    });

    test('a different receiver key cannot unwrap the key', () async {
      final receiver = await service.generateReceiverKeyPair();
      final stranger = await service.generateReceiverKeyPair();

      final wrapped = await service.wrapKey(
        aesKey: aesKey,
        receiverPublicKeyB64: receiver.publicKeyB64,
        sessionId: sessionId,
      );

      expect(
        () => service.unwrapKey(
          wrappedBase64: wrapped,
          privateKeySeed: stranger.privateKeySeed,
          sessionId: sessionId,
        ),
        throwsA(anything),
      );
    });
  });
}

/// The sender half of the wire format, written from the format description.
class _IndependentSender {
  static const String _keyInfo = 'lynk-wrapped-key-v1';

  final X25519 _x25519 = X25519();
  final AesGcm _aead = AesGcm.with256bits();
  final Random _random = Random(7);

  Future<String> wrap({
    required String aesKey,
    required String receiverPublicKeyB64,
    required String sessionId,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();

    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        _decodeBase64Url(receiverPublicKeyB64),
        type: KeyPairType.x25519,
      ),
    );

    final kek = await _hkdfSha256(
      ikm: await shared.extractBytes(),
      salt: utf8.encode(sessionId),
      info: utf8.encode(_keyInfo),
      length: 32,
    );

    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final box = await _aead.encrypt(
      utf8.encode(aesKey),
      secretKey: SecretKey(kek),
      nonce: nonce,
      aad: utf8.encode(sessionId),
    );

    return _encodeBase64Url(<int>[
      ...ephemeralPublic.bytes,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }
}

/// The receiver half of the wire format, written from the format description.
class _IndependentReceiver {
  static const String _keyInfo = 'lynk-wrapped-key-v1';

  final X25519 _x25519 = X25519();
  final AesGcm _aead = AesGcm.with256bits();

  Future<String> unwrap({
    required String wrappedBase64,
    required List<int> privateKeySeed,
    required String sessionId,
  }) async {
    final bytes = _decodeBase64Url(wrappedBase64);

    final ephemeralPublic = SimplePublicKey(
      bytes.sublist(0, 32),
      type: KeyPairType.x25519,
    );
    final nonce = bytes.sublist(32, 44);
    final cipherText = bytes.sublist(44, bytes.length - 16);
    final mac = bytes.sublist(bytes.length - 16);

    final receiverKeyPair = await _x25519.newKeyPairFromSeed(privateKeySeed);
    final shared = await _x25519.sharedSecretKey(
      keyPair: receiverKeyPair,
      remotePublicKey: ephemeralPublic,
    );

    final kek = await _hkdfSha256(
      ikm: await shared.extractBytes(),
      salt: utf8.encode(sessionId),
      info: utf8.encode(_keyInfo),
      length: 32,
    );

    final plain = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(kek),
      aad: utf8.encode(sessionId),
    );

    return utf8.decode(plain);
  }
}

/// HKDF-SHA256 (RFC 5869) written out by hand, extract then expand.
Future<Uint8List> _hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  required int length,
}) async {
  final hmac = Hmac.sha256();

  final prk = await hmac.calculateMac(ikm, secretKey: SecretKey(salt));

  final output = <int>[];
  var previous = const <int>[];
  var counter = 1;
  while (output.length < length) {
    final block = await hmac.calculateMac(<int>[
      ...previous,
      ...info,
      counter,
    ], secretKey: SecretKey(prk.bytes));
    previous = block.bytes;
    output.addAll(previous);
    counter++;
  }

  return Uint8List.fromList(output.sublist(0, length));
}

String _encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decodeBase64Url(String value) =>
    base64Url.decode(base64Url.normalize(value));
