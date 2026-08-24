import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'encrypt_file_use_case.g.dart';

class EncryptFileUseCase {
  static String _sanitizeKey(String key) {
    final clean = key.trim();
    if (clean.length == 32) return clean;
    if (clean.length > 32) return clean.substring(0, 32);
    return clean.padRight(32, '0');
  }

  /// Encrypts an input file using AES-256-CBC with chunked streaming.
  /// The 16-byte random IV is prepended to the output file.
  /// Memory footprint remains under 5 MB regardless of file size.
  /// Execution is offloaded to a background Dart Isolate for 60 FPS UI performance.
  Future<File> execute({
    required File inputFile,
    required String aesKey32Bytes,
  }) async {
    final inputPath = inputFile.path;
    final outputPath = '$inputPath.enc';
    final keyStr = _sanitizeKey(aesKey32Bytes);

    await Isolate.run(() async {
      final key = enc.Key.fromUtf8(keyStr);
      final initialIv = enc.IV.fromSecureRandom(16);

      final inFile = File(inputPath);
      final outFile = File(outputPath);
      if (await outFile.exists()) {
        await outFile.delete();
      }

      final sink = outFile.openWrite();
      sink.add(initialIv.bytes);

      final encrypterStandard = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
      );
      final encrypterNoPadding = enc.Encrypter(
        enc.AES(key, mode: enc.AESMode.cbc, padding: null),
      );

      final inputStream = inFile.openRead();
      final buffer = BytesBuilder(copy: false);
      const chunkSize = 1024 * 1024;
      enc.IV currentIv = initialIv;

      await for (final chunk in inputStream) {
        buffer.add(chunk);

        while (buffer.length >= chunkSize + 16) {
          final rawChunk = buffer.takeBytes();
          final processLength = (rawChunk.length ~/ 16) * 16;
          final toProcess = rawChunk.sublist(0, processLength);
          final remainder = rawChunk.sublist(processLength);

          final encrypted = encrypterNoPadding.encryptBytes(
            toProcess,
            iv: currentIv,
          );
          sink.add(encrypted.bytes);

          currentIv = enc.IV(
            encrypted.bytes.sublist(encrypted.bytes.length - 16),
          );
          buffer.add(remainder);
        }
      }

      final remaining = buffer.takeBytes();
      final finalEncrypted = encrypterStandard.encryptBytes(
        remaining,
        iv: currentIv,
      );
      sink.add(finalEncrypted.bytes);

      await sink.flush();
      await sink.close();
    });

    return File(outputPath);
  }

  Uint8List executeBytes({
    required Uint8List inputBytes,
    required String aesKey32Bytes,
  }) {
    final keyStr = _sanitizeKey(aesKey32Bytes);
    final key = enc.Key.fromUtf8(keyStr);
    final iv = enc.IV.fromSecureRandom(16);

    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );
    final encrypted = encrypter.encryptBytes(inputBytes, iv: iv);

    final builder = BytesBuilder();
    builder.add(iv.bytes);
    builder.add(encrypted.bytes);
    return builder.toBytes();
  }
}

@riverpod
EncryptFileUseCase encryptFileUseCase(Ref ref) {
  return EncryptFileUseCase();
}
