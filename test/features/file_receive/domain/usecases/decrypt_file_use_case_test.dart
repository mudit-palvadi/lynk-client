import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:client/features/file_receive/domain/usecases/decrypt_file_use_case.dart';

void main() {
  group('DecryptFileUseCase', () {
    final encryptUseCase = EncryptFileUseCase();
    final decryptUseCase = DecryptFileUseCase();

    late File originalFile;
    late File encryptedFile;
    late File decryptedFile;
    late String aesKey;
    const testContent =
        'Secure client-side end-to-end decryption verification payload.';

    setUp(() async {
      originalFile = File('original_payload_test.txt');
      originalFile.writeAsStringSync(testContent);
      aesKey = 'abcdefghijklmnopqrstuvwxyz123456'; // 32 bytes

      encryptedFile = await encryptUseCase.execute(
        inputFile: originalFile,
        aesKey32Bytes: aesKey,
      );

      decryptedFile = File('decrypted_payload_test.txt');
    });

    tearDown(() {
      if (originalFile.existsSync()) originalFile.deleteSync();
      if (encryptedFile.existsSync()) encryptedFile.deleteSync();
      if (decryptedFile.existsSync()) decryptedFile.deleteSync();
    });

    test(
      'execute extracts prepended IV and decrypts AES-256-CBC ciphertext back to original plaintext',
      () async {
        final result = await decryptUseCase.execute(
          encryptedFile: encryptedFile,
          aesKey32Bytes: aesKey,
          outputPath: decryptedFile.path,
        );

        expect(result.existsSync(), true);
        expect(result.readAsStringSync(), testContent);
      },
    );

    test(
      'execute accepts a valid key with surrounding whitespace',
      () async {
        final paddedKey = '  $aesKey  ';
        final result = await decryptUseCase.execute(
          encryptedFile: encryptedFile,
          aesKey32Bytes: paddedKey,
          outputPath: decryptedFile.path,
        );

        expect(result.existsSync(), true);
        expect(result.readAsStringSync(), testContent);
      },
    );

    test('execute rejects a key that is not 32 bytes (#46)', () async {
      await expectLater(
        decryptUseCase.execute(
          encryptedFile: encryptedFile,
          aesKey32Bytes: 'short',
          outputPath: decryptedFile.path,
        ),
        throwsArgumentError,
      );
    });

    test('executeBytes rejects a key that is not 32 bytes (#46)', () {
      final encryptedBytes = encryptUseCase.executeBytes(
        inputBytes: Uint8List.fromList([1, 2, 3]),
        aesKey32Bytes: aesKey,
      );
      expect(
        () => decryptUseCase.executeBytes(
          encryptedBytes: encryptedBytes,
          aesKey32Bytes: 'short',
        ),
        throwsArgumentError,
      );
    });

    test(
      'execute streams and decrypts multi-megabyte large files correctly across 1MB chunk boundaries',
      () async {
        final largeFile = File('large_payload_test.bin');
        final largeBytes = Uint8List(
          2 * 1024 * 1024 + 500,
        ); // 2.0005 MB payload
        for (int i = 0; i < largeBytes.length; i++) {
          largeBytes[i] = i % 256;
        }
        await largeFile.writeAsBytes(largeBytes);

        final encLargeFile = await encryptUseCase.execute(
          inputFile: largeFile,
          aesKey32Bytes: aesKey,
        );

        final decLargeFile = File('decrypted_large_payload.bin');
        await decryptUseCase.execute(
          encryptedFile: encLargeFile,
          aesKey32Bytes: aesKey,
          outputPath: decLargeFile.path,
        );

        expect(decLargeFile.existsSync(), true);
        expect(decLargeFile.lengthSync(), largeBytes.length);
        final decBytes = await decLargeFile.readAsBytes();
        expect(decBytes, largeBytes);

        if (largeFile.existsSync()) await largeFile.delete();
        if (encLargeFile.existsSync()) await encLargeFile.delete();
        if (decLargeFile.existsSync()) await decLargeFile.delete();
      },
    );
  });
}
