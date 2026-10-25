import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

/// Seals a file name for the version-2 data-channel header (#32).
///
/// The name used to travel in clear text in the `hdr` / `eof` text frames, so
/// anyone holding the DataChannel saw it without the transfer key. It is now
/// encrypted with the same AES-256-CBC key as the payload (16-byte random IV
/// prepended), then base64 encoded so it can live inside the JSON frame.
///
/// The key must be exactly 32 UTF-8 bytes, the format the app issues. A
/// shorter or longer key is rejected rather than padded, so two different
/// strings can never open the same sealed name (#46).
/// Everything here is synchronous: the receive path is a sync callback.
class NameSealer {
  const NameSealer._();

  /// Returns the base64 token for [name], or `null` when [aesKey] is empty.
  static String? seal(String name, String? aesKey) {
    if (aesKey == null || aesKey.isEmpty) return null;
    final iv = enc.IV.fromSecureRandom(16);
    final sealed = _encrypter(aesKey).encryptBytes(utf8.encode(name), iv: iv);
    final builder = BytesBuilder(copy: false)
      ..add(iv.bytes)
      ..add(sealed.bytes);
    return base64Encode(builder.takeBytes());
  }

  /// Opens a token produced by [seal] (or by the web's `sealName`); `null` when
  /// the token is malformed or sealed with a different key.
  static String? open(String token, String? aesKey) {
    if (aesKey == null || aesKey.isEmpty) return null;
    try {
      final packed = base64Decode(token);
      if (packed.length <= 16) return null;
      final iv = enc.IV(Uint8List.sublistView(packed, 0, 16));
      final body = enc.Encrypted(Uint8List.sublistView(packed, 16));
      return _encrypter(aesKey).decrypt(body, iv: iv);
    } catch (_) {
      return null;
    }
  }

  static enc.Encrypter _encrypter(String aesKey) => enc.Encrypter(
    enc.AES(
      enc.Key.fromUtf8(_requireKey(aesKey)),
      mode: enc.AESMode.cbc,
      padding: 'PKCS7',
    ),
  );

  static String _requireKey(String key) {
    final clean = key.trim();
    if (utf8.encode(clean).length != 32) {
      throw ArgumentError.value(
        key,
        'aesKey',
        'an AES-256 key must be exactly 32 bytes',
      );
    }
    return clean;
  }
}
