import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'key_wrap_service.g.dart';

/// Ephemeral X25519 key pair held by the receiving device.
///
/// The private seed never leaves device memory. Only the base64url public
/// key travels — inside the receiver QR's URL #fragment.
class ReceiverKeyPair {
  final String publicKeyB64;
  final Uint8List privateKeySeed;

  const ReceiverKeyPair({
    required this.publicKeyB64,
    required this.privateKeySeed,
  });
}

/// Zero-knowledge AES key delivery for the reverse-pairing flow.
///
/// Wire format (all parts concatenated, base64url encoded, no padding):
///   [32 B ephemeral X25519 public key]
///   [12 B AES-GCM nonce]
///   [N B ciphertext = UTF-8 bytes of the AES key string]
///   [16 B AES-GCM tag]
///
/// KEK = HKDF-SHA256(ECDH(ephemeralPriv, receiverPub),
///                   salt: sessionId, info: 'lynk-wrapped-key-v1')
/// AAD = sessionId
///
/// The backend relays only this opaque blob — it can never derive the key.
class KeyWrapService {
  static final X25519 _x25519 = X25519();
  static final AesGcm _aead = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const String _keyInfo = 'lynk-wrapped-key-v1';

  final Random _random;

  KeyWrapService({Random? random}) : _random = random ?? Random.secure();

  Future<ReceiverKeyPair> generateReceiverKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    return ReceiverKeyPair(
      publicKeyB64: encodeBase64Url(pub.bytes),
      privateKeySeed: Uint8List.fromList(privBytes),
    );
  }

  Future<String> wrapKey({
    required String aesKey,
    required String receiverPublicKeyB64,
    required String sessionId,
  }) async {
    final ephemeral = await _x25519.newKeyPair();
    final receiverPub = SimplePublicKey(
      decodeBase64Url(receiverPublicKeyB64),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: receiverPub,
    );
    final kek = await _deriveKek(sharedSecret, sessionId);

    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );
    final secretBox = await _aead.encrypt(
      utf8.encode(aesKey),
      secretKey: kek,
      nonce: nonce,
      aad: utf8.encode(sessionId),
    );

    final ephPub = await ephemeral.extractPublicKey();
    final output = BytesBuilder()
      ..add(ephPub.bytes)
      ..add(secretBox.nonce)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);

    return encodeBase64Url(output.toBytes());
  }

  Future<String> unwrapKey({
    required String wrappedBase64,
    required List<int> privateKeySeed,
    required String sessionId,
  }) async {
    final bytes = decodeBase64Url(wrappedBase64);
    if (bytes.length < 60) {
      throw ArgumentError('wrapped_key payload too short');
    }

    final ephPubBytes = bytes.sublist(0, 32);
    final nonce = bytes.sublist(32, 44);
    final cipherText = bytes.sublist(44, bytes.length - 16);
    final macBytes = bytes.sublist(bytes.length - 16);

    final receiverKeyPair = await _x25519.newKeyPairFromSeed(privateKeySeed);
    final ephPub = SimplePublicKey(ephPubBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: receiverKeyPair,
      remotePublicKey: ephPub,
    );
    final kek = await _deriveKek(sharedSecret, sessionId);

    final plainBytes = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: kek,
      aad: utf8.encode(sessionId),
    );

    return utf8.decode(plainBytes);
  }

  Future<SecretKey> _deriveKek(SecretKey sharedSecret, String sessionId) {
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(sessionId),
      info: utf8.encode(_keyInfo),
    );
  }
}

String encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List decodeBase64Url(String value) {
  final normalized = base64Url.normalize(value);
  return Uint8List.fromList(base64Url.decode(normalized));
}

@riverpod
KeyWrapService keyWrapService(Ref ref) => KeyWrapService();
