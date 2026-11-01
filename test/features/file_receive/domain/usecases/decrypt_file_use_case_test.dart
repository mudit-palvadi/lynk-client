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

    test(
      'execute keeps a pre-existing output file when the key is rejected (#70)',
      () async {
        decryptedFile.writeAsStringSync('previous download');

        await expectLater(
          decryptUseCase.execute(
            encryptedFile: encryptedFile,
            aesKey32Bytes: 'short',
            outputPath: decryptedFile.path,
          ),
          throwsArgumentError,
        );

        expect(decryptedFile.existsSync(), isTrue);
        expect(decryptedFile.readAsStringSync(), 'previous download');
      },
    );

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

    test(
      'execute deletes partial plaintext when a truncated ciphertext fails (#70)',
      () async {
        final sourceFile = File('truncated_source_test.bin');
        final truncatedFile = File('truncated_payload_test.enc');
        addTearDown(() async {
          if (sourceFile.existsSync()) await sourceFile.delete();
          if (truncatedFile.existsSync()) await truncatedFile.delete();
        });

        final sourceBytes = Uint8List(2 * 1024 * 1024);
        for (var i = 0; i < sourceBytes.length; i++) {
          sourceBytes[i] = i % 251;
        }
        await sourceFile.writeAsBytes(sourceBytes);

        final encryptedSourceFile = await encryptUseCase.execute(
          inputFile: sourceFile,
          aesKey32Bytes: aesKey,
        );
        addTearDown(() async {
          if (encryptedSourceFile.existsSync()) {
            await encryptedSourceFile.delete();
          }
        });

        // Keep the 16-byte IV, one full streaming chunk, and a 23-byte
        // leftover. Decryption writes that chunk to disk before the leftover
        // is rejected as an invalid block length.
        final encryptedBytes = await encryptedSourceFile.readAsBytes();
        await truncatedFile.writeAsBytes(
          encryptedBytes.sublist(0, 16 + 1024 * 1024 + 23),
        );

        await expectLater(
          decryptUseCase.execute(
            encryptedFile: truncatedFile,
            aesKey32Bytes: aesKey,
            outputPath: decryptedFile.path,
          ),
          throwsFormatException,
        );

        expect(decryptedFile.existsSync(), isFalse);
      },
    );

    test(
      'execute deletes the output when the final block fails to unpad (#70)',
      () async {
        final blockAlignedFile = File('block_aligned_payload_test.bin');
        final corruptFile = File('corrupt_final_block_test.enc');
        addTearDown(() async {
          if (blockAlignedFile.existsSync()) await blockAlignedFile.delete();
          if (corruptFile.existsSync()) await corruptFile.delete();
        });

        // A 16-byte payload pads to a final block that is all 0x10.
        await blockAlignedFile.writeAsBytes(
          Uint8List(16)..fillRange(0, 16, 65),
        );

        final encryptedBlockFile = await encryptUseCase.execute(
          inputFile: blockAlignedFile,
          aesKey32Bytes: aesKey,
        );
        addTearDown(() async {
          if (encryptedBlockFile.existsSync()) {
            await encryptedBlockFile.delete();
          }
        });

        // Flipping the block before the final ciphertext block turns the last
        // plaintext byte from 0x10 into 0x11, so unpadding must fail.
        final corruptBytes = await encryptedBlockFile.readAsBytes();
        corruptBytes[corruptBytes.length - 16 - 1] ^= 0x01;
        await corruptFile.writeAsBytes(corruptBytes);

        await expectLater(
          decryptUseCase.execute(
            encryptedFile: corruptFile,
            aesKey32Bytes: aesKey,
            outputPath: decryptedFile.path,
          ),
          throwsArgumentError,
        );

        expect(decryptedFile.existsSync(), isFalse);
      },
    );
  });
}
