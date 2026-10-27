import 'dart:convert';
import 'dart:io';
import 'package:client/core/services/transfer_framer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = File(
    'test/fixtures/delivery_receipts.json',
  ).readAsStringSync();
  test(
    'receipt fixtures match the browser when both checkouts are present',
    () {
      final web = File('../web/test/fixtures/delivery_receipts.json');
      if (web.existsSync()) expect(web.readAsStringSync(), fixture);
    },
  );
  for (final vector in jsonDecode(fixture) as List) {
    test('receipt contract: ${vector['wire']}', () {
      final frame = TransferFramer.parseText(vector['wire'] as String);
      expect(frame?.kind.name, vector['kind']);
      if (vector['kind'] == 'hello') {
        expect(frame!.receipts, vector['receipts']);
      }
      if (vector['kind'] == 'receipt') {
        expect(frame!.digest, vector['sha256']);
        if (vector['sha256'] == null) {
          expect(
            TransferFramer.encodeReceipt(frame.files!, frame.bytes!).text,
            '{"t":"ack","files":2,"bytes":64}',
          );
        } else {
          expect(
            TransferFramer.encodeReceipt(
              frame.files!,
              frame.bytes!,
              sha256: frame.digest,
            ).text,
            vector['wire'],
          );
        }
      }
    });
  }
  test('receipt negotiation preserves the legacy hello', () {
    expect(TransferFramer.encodeHello().text, '{"t":"hi","v":2}');
    expect(
      TransferFramer.encodeHello(2, true).text,
      '{"t":"hi","v":2,"receipts":true}',
    );
    expect(() => TransferFramer.encodeReceipt(0, 32), throwsArgumentError);
  });
}
