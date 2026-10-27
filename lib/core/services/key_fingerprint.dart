import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Short check value for a receiver public key.
///
/// Both devices hash the same base64 public key. The first four digest bytes
/// are shown as eight hex digits, so a swapped key is visible.
String keyFingerprint(String publicKeyB64) {
  final digest = sha256.convert(utf8.encode(publicKeyB64));
  final hex = digest.bytes
      .take(4)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 4)} ${hex.substring(4)}';
}
