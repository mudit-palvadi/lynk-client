import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/features/file_receive/domain/usecases/decrypt_file_use_case.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = File('test/fixtures/crypto_contract.json');
  final contract =
      jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
  final encrypt = EncryptFileUseCase();
  final decrypt = DecryptFileUseCase();
  const key = '0123456789abcdef0123456789abcdef';
  late Directory directory;

  group('Dart/browser encrypted-byte contract', () {
    setUp(
      () async => directory = await Directory.systemTemp.createTemp(
        'lynk-cipher-test-',
      ),
    );
    tearDown(() async => directory.delete(recursive: true));

    test('fixture copies match when both repositories are checked out', () {
      final browser = File('../web/test/fixtures/crypto_contract.json');
      if (browser.existsSync()) {
        expect(fixture.readAsBytesSync(), browser.readAsBytesSync());
      }
      expect(contract['version'], 1);
    });

    for (final entry in contract['vectors'] as List<dynamic>) {
      final vector = entry as Map<String, dynamic>;
      test(
        'decrypt actual ${vector['name']} bytes in memory and file modes',
        () async {
          final packed = base64Decode(vector['packedBase64'] as String);
          final expected = base64Decode(vector['plainBase64'] as String);
          final vectorKey = vector['key'] as String;
          expect(
            decrypt.executeBytes(
              encryptedBytes: packed,
              aesKey32Bytes: vectorKey,
            ),
            expected,
          );
          final input = await File(
            '${directory.path}/input.enc',
          ).writeAsBytes(packed);
          final output = await decrypt.execute(
            encryptedFile: input,
            aesKey32Bytes: vectorKey,
            outputPath: '${directory.path}/output',
          );
          expect(await output.readAsBytes(), expected);
        },
      );
    }

    for (final size in [
      0,
      1,
      15,
      16,
      17,
      1024 * 1024,
      1024 * 1024 + 16,
      1024 * 1024 + 17,
    ]) {
      test(
        'encrypt $size bytes with exact IV-prefix and PKCS7 bytes',
        () async {
          final plain = Uint8List.fromList(List.generate(size, (i) => i % 251));
          final memory = encrypt.executeBytes(
            inputBytes: plain,
            aesKey32Bytes: key,
          );
          _expectCipher(memory, plain, key);
          expect(
            decrypt.executeBytes(encryptedBytes: memory, aesKey32Bytes: key),
            plain,
          );
          final input = await File(
            '${directory.path}/plain',
          ).writeAsBytes(plain);
          final output = await encrypt.execute(
            inputFile: input,
            aesKey32Bytes: key,
          );
          final packed = await output.readAsBytes();
          _expectCipher(packed, plain, key);
          final recovered = await decrypt.execute(
            encryptedFile: output,
            aesKey32Bytes: key,
            outputPath: '${directory.path}/recovered',
          );
          expect(await recovered.readAsBytes(), plain);
        },
      );
    }

    test('failed file reads close the encrypted output handle', () async {
      final output = File('${directory.path}/failed.enc');
      await expectLater(
        encrypt.execute(
          inputFile: File('${directory.path}/missing'),
          aesKey32Bytes: key,
          outputPath: output.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      // Windows rejects this deletion if the sink is still open.
      await output.delete();
      expect(output.existsSync(), false);
    });

    test('trimmed multibyte UTF-8 keys use exactly 32 bytes', () {
      final vectorKey = '  ${List.filled(16, 'é').join()}  ';
      final plain = Uint8List.fromList([0, 255, 42]);
      final packed = encrypt.executeBytes(
        inputBytes: plain,
        aesKey32Bytes: vectorKey,
      );
      _expectCipher(packed, plain, vectorKey.trim());
      expect(
        decrypt.executeBytes(encryptedBytes: packed, aesKey32Bytes: vectorKey),
        plain,
      );
    });

    for (final invalid in contract['invalidKeys'] as List<dynamic>) {
      test(
        'reject invalid key without putting it in exceptions (${utf8.encode(invalid as String).length} bytes)',
        () async {
          final input = await File('${directory.path}/plain').writeAsBytes([1]);
          final packed = encrypt.executeBytes(
            inputBytes: Uint8List.fromList([1]),
            aesKey32Bytes: key,
          );
          final encrypted = await File(
            '${directory.path}/input.enc',
          ).writeAsBytes(packed);
          final safeError = isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            isNot(contains(invalid)),
          );
          expect(
            () => encrypt.executeBytes(
              inputBytes: Uint8List(1),
              aesKey32Bytes: invalid,
            ),
            throwsA(safeError),
          );
          expect(
            () => decrypt.executeBytes(
              encryptedBytes: packed,
              aesKey32Bytes: invalid,
            ),
            throwsA(safeError),
          );
          await expectLater(
            encrypt.execute(inputFile: input, aesKey32Bytes: invalid),
            throwsA(safeError),
          );
          await expectLater(
            decrypt.execute(
              encryptedFile: encrypted,
              aesKey32Bytes: invalid,
              outputPath: '${directory.path}/output',
            ),
            throwsA(safeError),
          );
        },
      );
    }
  });
}

void _expectCipher(Uint8List packed, Uint8List plain, String key) {
  final pad = 16 - plain.length % 16;
  final padded = [...plain, ...List.filled(pad, pad)];
  final reference = enc.Encrypter(
    enc.AES(enc.Key.fromUtf8(key), mode: enc.AESMode.cbc, padding: null),
  );
  final expected = reference
      .encryptBytes(padded, iv: enc.IV(packed.sublist(0, 16)))
      .bytes;
  expect(packed.length, 16 + padded.length);
  expect(packed.sublist(16), expected);
}
