import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'decrypt_file_use_case.g.dart';

class DecryptFileUseCase {
  static String _sanitizeKey(String key) {
    final clean = key.trim();
    if (clean.length == 32) return clean;
    if (clean.length > 32) return clean.substring(0, 32);
    return clean.padRight(32, '0');
  }

  /// Decrypts an encrypted file using AES-256-CBC with chunked streaming.
  /// The first 16 bytes are extracted as the IV, and payload is decrypted in 1 MB streams.
  /// Memory footprint remains under 5 MB regardless of file size.
  /// Execution is offloaded to a background Dart Isolate for 60 FPS UI performance.
  Future<File> execute({
    required File encryptedFile,
    required String aesKey32Bytes,
    required String outputPath,
  }) async {
    final encPath = encryptedFile.path;
    final keyStr = _sanitizeKey(aesKey32Bytes);

    await Isolate.run(() async {
      final inFile = File(encPath);
      final outFile = File(outputPath);
      if (await outFile.exists()) {
        await outFile.delete();
      }

      final key = enc.Key.fromUtf8(keyStr);
      final encrypterStandard = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
      );
      final encrypterNoPadding = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.cbc, padding: null),
      );

      final inputStream = inFile.openRead();
      final buffer = BytesBuilder(copy: false);
      Uint8List? initialIvBytes;
      enc.IV? currentIv;
      final sink = outFile.openWrite();
      const chunkSize = 1024 * 1024;

      await for (final chunk in inputStream) {
        buffer.add(chunk);

        if (initialIvBytes == null) {
          if (buffer.length >= 16) {
            final allBytes = buffer.takeBytes();
            initialIvBytes = allBytes.sublist(0, 16);
            currentIv = enc.IV(initialIvBytes);
            buffer.add(allBytes.sublist(16));
          } else {
            continue;
          }
        }

        while (buffer.length >= chunkSize + 16) {
          final rawChunk = buffer.takeBytes();
          final processLength = ((rawChunk.length - 16) ~/ 16) * 16;
          if (processLength <= 0) {
            buffer.add(rawChunk);
            break;
          }

          final toDecrypt = rawChunk.sublist(0, processLength);
          final remainder = rawChunk.sublist(processLength);

          final decrypted = encrypterNoPadding.decryptBytes(
            enc.Encrypted(toDecrypt),
            iv: currentIv!,
          );
          sink.add(decrypted);

          currentIv = enc.IV(toDecrypt.sublist(toDecrypt.length - 16));
          buffer.add(remainder);
        }
      }

      if (initialIvBytes == null) {
        sink.close();
        throw const FormatException(
          'Encrypted file payload is truncated or invalid',
        );
      }

      final remaining = buffer.takeBytes();
      if (remaining.isEmpty || remaining.length % 16 != 0) {
        sink.close();
        throw const FormatException(
          'Encrypted ciphertext payload is corrupted or invalid block length',
        );
      }

      final finalDecrypted = encrypterStandard.decryptBytes(
        enc.Encrypted(remaining),
        iv: currentIv!,
      );
      sink.add(finalDecrypted);

      await sink.flush();
      await sink.close();
    });

    return File(outputPath);
  }

  /// Decrypts encrypted bytes in-memory for Web targets
  Uint8List executeBytes({
    required Uint8List encryptedBytes,
    required String aesKey32Bytes,
  }) {
    if (encryptedBytes.length < 16) {
      throw const FormatException(
        'Encrypted bytes payload is truncated or invalid',
      );
    }

    final keyStr = _sanitizeKey(aesKey32Bytes);
    final ivBytes = encryptedBytes.sublist(0, 16);
    final ciphertext = encryptedBytes.sublist(16);

    final key = enc.Key.fromUtf8(keyStr);
    final iv = enc.IV(ivBytes);

    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );
    return Uint8List.fromList(
      encrypter.decryptBytes(enc.Encrypted(ciphertext), iv: iv),
    );
  }
}

@riverpod
DecryptFileUseCase decryptFileUseCase(Ref ref) {
  return DecryptFileUseCase();
}
