import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/services/transfer_framer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferFramer (DataChannel framing protocol)', () {
    test('header round-trips file metadata', () {
      final frame = TransferFramer.encodeHeader(
        const FramedFileMeta(name: 'photo.jpg', size: 12345),
      );
      expect(frame.isText, isTrue);

      final meta = TransferFramer.parseText(frame.text!);
      expect(meta, isNotNull);
      expect(meta!.kind, FrameKind.header);
      expect(meta.meta!.name, 'photo.jpg');
      expect(meta.meta!.size, 12345);
    });

    test('eof frame round-trips and is distinguishable from header', () {
      final eof = TransferFramer.encodeEof(
        const FramedFileMeta(name: 'a.bin', size: 0),
      );
      final parsed = TransferFramer.parseText(eof.text!);

      expect(parsed!.kind, FrameKind.eof);
      expect(parsed.meta!.name, 'a.bin');

      final header = TransferFramer.parseText(
        TransferFramer.encodeHeader(
          const FramedFileMeta(name: 'a.bin', size: 1),
        ).text!,
      );
      expect(header!.kind, FrameKind.header);
    });

    test('done frame signals overall transfer completion', () {
      final done = TransferFramer.encodeDone();
      final parsed = TransferFramer.parseText(done.text!);
      expect(parsed!.kind, FrameKind.done);
      expect(parsed.meta, isNull);
    });

    test('non-protocol or malformed text parses to null, never throws', () {
      expect(TransferFramer.parseText('hello world'), isNull);
      expect(TransferFramer.parseText('{"t":"bogus"}'), isNull);
      expect(TransferFramer.parseText('{broken json'), isNull);
      // Header missing required fields.
      expect(TransferFramer.parseText('{"t":"hdr","name":"x"}'), isNull);
    });

    test('binary frames pass through untouched', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final frame = TransferFrame.binary(bytes);
      expect(frame.isBinary, isTrue);
      expect(frame.bytes, bytes);
    });

    test('wire keys stay minimal and stable', () {
      final json =
          jsonDecode(
                TransferFramer.encodeHeader(
                  const FramedFileMeta(name: 'n', size: 5),
                ).text!,
              )
              as Map<String, dynamic>;
      expect(json.keys.toSet(), {'t', 'name', 'size'});
    });

    test('a sealed header carries a token instead of the name (#32)', () {
      const token = 'c2VhbGVkLXRva2Vu';
      final frame = TransferFramer.encodeHeader(
        const FramedFileMeta(name: 'holiday.jpg', size: 4096, token: token),
      );
      final json = jsonDecode(frame.text!) as Map<String, dynamic>;

      expect(json.keys.toSet(), {'t', 'v', 'n', 'size'});
      expect(frame.text, isNot(contains('holiday.jpg')));

      final parsed = TransferFramer.parseText(frame.text!);
      expect(parsed!.kind, FrameKind.header);
      expect(parsed.meta!.token, token);
      expect(parsed.meta!.size, 4096);
    });

    test('a sealed eof carries the same token shape', () {
      final parsed = TransferFramer.parseText(
        TransferFramer.encodeEof(
          const FramedFileMeta(size: 0, token: 'c2VhbGVkLXRva2Vu'),
        ).text!,
      );

      expect(parsed!.kind, FrameKind.eof);
      expect(parsed.meta!.token, 'c2VhbGVkLXRva2Vu');
    });

    test('hello advertises the sealed-name version', () {
      final hello = TransferFramer.encodeHello();
      expect(jsonDecode(hello.text!), {'t': 'hi', 'v': 2});

      final parsed = TransferFramer.parseText(hello.text!);
      expect(parsed!.kind, FrameKind.hello);
      expect(parsed.meta, isNull);
    });
  });
}
