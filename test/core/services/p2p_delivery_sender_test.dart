import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:client/core/services/p2p_delivery_sender.dart';
import 'package:client/core/services/transfer_framer.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:client/features/file_receive/domain/usecases/decrypt_file_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = '0123456789abcdef0123456789abcdef';
  late Directory sandbox;
  late File file;
  late Uint8List packed;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('lynk-confirmation-');
    packed = EncryptFileUseCase().executeBytes(
      inputBytes: Uint8List.fromList([7, 8, 9]),
      aesKey32Bytes: key,
    );
    file = await File('${sandbox.path}/payload.enc').writeAsBytes(packed);
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  test(
    'only a matching post-done receipt completes a real encrypted send',
    () async {
      final frames = <String>[];
      final chunks = <int>[];
      final done = Completer<void>();
      late P2PDeliverySender sender;
      sender = P2PDeliverySender(
        aesKey: key,
        bufferedAmount: () => 100,
        isOpen: () => true,
        sendBinary: (bytes) async {
          chunks.addAll(bytes);
        },
        sendText: (text) async {
          frames.add(text);
          if (text == '{"t":"done"}') done.complete();
        },
      );
      sender.accept(
        TransferFramer.parseText(
          TransferFramer.encodeReceipt(1, packed.length).text!,
        )!,
      );
      sender.accept(
        TransferFramer.parseText(TransferFramer.encodeHello(2, true).text!)!,
      );
      var finished = false;
      final sending = sender
          .sendFiles([file], names: ['note.txt'])
          .then((_) => finished = true);
      await done.future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(
        finished,
        isFalse,
        reason: 'An early receipt cannot acknowledge a later transfer.',
      );
      sender.accept(
        TransferFramer.parseText(
          TransferFramer.encodeReceipt(2, packed.length).text!,
        )!,
      );
      sender.accept(
        TransferFramer.parseText(
          TransferFramer.encodeReceipt(1, packed.length + 1).text!,
        )!,
      );
      expect(finished, isFalse);
      sender.accept(
        TransferFramer.parseText(
          TransferFramer.encodeReceipt(1, packed.length).text!,
        )!,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(
        finished,
        isFalse,
        reason: 'A receipt without the ciphertext digest is not delivery.',
      );
      sender.accept(
        TransferFramer.parseText(
          TransferFramer.encodeReceipt(
            1,
            packed.length,
            sha256: sha256.convert(packed).toString(),
          ).text!,
        )!,
      );
      await sending;
      expect(finished, isTrue);
      expect(
        frames.first,
        isNot(contains('note.txt')),
        reason: 'Names remain sealed.',
      );
      expect(
        DecryptFileUseCase().executeBytes(
          encryptedBytes: Uint8List.fromList(chunks),
          aesKey32Bytes: key,
        ),
        [7, 8, 9],
      );
    },
  );

  for (final mode in ['timeout', 'closed', 'cancelled', 'legacy']) {
    test('$mode cannot turn queued bytes into success', () async {
      var open = true;
      var bytes = 0;
      final done = Completer<void>();
      late P2PDeliverySender sender;
      sender = P2PDeliverySender(
        bufferedAmount: () => 0,
        isOpen: () => open,
        confirmationTimeout: const Duration(milliseconds: 25),
        sendBinary: (chunk) async {
          bytes += chunk.length;
        },
        sendText: (text) async {
          if (text == '{"t":"done"}') {
            done.complete();
            if (mode == 'closed') open = false;
            if (mode == 'cancelled') sender.cancel();
          }
        },
      );
      sender.accept(
        TransferFramer.parseText(
          TransferFramer.encodeHello(2, mode != 'legacy').text!,
        )!,
      );
      await expectLater(sender.sendFiles([file]), throwsA(anything));
      if (mode == 'legacy') {
        expect(
          bytes,
          0,
          reason: 'Fall back before streaming to an older peer.',
        );
      } else {
        expect(bytes, packed.length);
        expect(done.isCompleted, isTrue);
      }
    });
  }
  test('a missing hello has a bounded fallback without streaming', () async {
    var frames = 0;
    final sender = P2PDeliverySender(
      sendText: (_) async {
        frames++;
      },
      sendBinary: (_) async {
        frames++;
      },
      bufferedAmount: () => 0,
      isOpen: () => true,
      helloTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      sender.sendFiles([file]),
      throwsA(isA<TimeoutException>()),
    );
    expect(frames, 0);
  });
}
