import 'dart:convert';
import 'dart:typed_data';

/// One framed message on the `fileTransfer` DataChannel.
class TransferFrame {
  final String? text;
  final Uint8List? bytes;

  const TransferFrame.text(this.text) : bytes = null;
  const TransferFrame.binary(this.bytes) : text = null;

  bool get isText => text != null;
  bool get isBinary => bytes != null;
}

/// Metadata carried by a header / eof frame.
///
/// [token] is the base64 sealed file name used by a version-2 peer; when it is
/// set, [name] is empty and the name never travels in clear text (#32).
class FramedFileMeta {
  final String name;
  final int size;
  final String? token;

  const FramedFileMeta({this.name = '', required this.size, this.token});
}

enum FrameKind { header, eof, done, hello, receipt }

/// Minimal, stable wire protocol framing file transfers over the binary
/// DataChannel (POTENTIAL_ISSUES #1: shared contract with the web receiver).
///
/// - Text frame `{"t":"hdr","name":...,"size":N}` precedes each file's
///   encrypted byte stream (size = encrypted length incl. IV prefix).
///   A peer that advertised version 2 gets `{"t":"hdr","v":2,"n":...,"size":N}`
///   instead, where `n` is the sealed name (#32).
/// - Binary frames carry the raw encrypted chunks in order.
/// - Text frame `{"t":"eof","name":...}` marks one file complete.
/// - Text frame `{"t":"done"}` marks the whole transfer complete.
/// - Text frame `{"t":"hi","v":2}` is sent by a receiver that can open a
///   sealed name; a peer that never sends it gets the plain name.
class TransferFramer {
  static const String _typeHeader = 'hdr';
  static const String _typeEof = 'eof';
  static const String _typeDone = 'done';
  static const String _typeHello = 'hi';
  static const int _sealedVersion = 2;

  const TransferFramer._();

  static TransferFrame encodeHeader(FramedFileMeta meta) => TransferFrame.text(
    jsonEncode(
      meta.token == null
          ? {'t': _typeHeader, 'name': meta.name, 'size': meta.size}
          : {
              't': _typeHeader,
              'v': _sealedVersion,
              'n': meta.token,
              'size': meta.size,
            },
    ),
  );

  static TransferFrame encodeEof(FramedFileMeta meta) => TransferFrame.text(
    jsonEncode(
      meta.token == null
          ? {'t': _typeEof, 'name': meta.name}
          : {'t': _typeEof, 'v': _sealedVersion, 'n': meta.token},
    ),
  );

  static TransferFrame encodeDone() =>
      TransferFrame.text(jsonEncode({'t': _typeDone}));

  static TransferFrame encodeHello([
    int version = _sealedVersion,
    bool receipts = false,
  ]) => TransferFrame.text(
    jsonEncode({'t': _typeHello, 'v': version, if (receipts) 'receipts': true}),
  );

  static TransferFrame encodeReceipt(int files, int bytes, {String? sha256}) {
    if (!_validReceipt(files, bytes)) throw ArgumentError('invalid receipt');
    if (sha256 != null && !_validDigest(sha256)) {
      throw ArgumentError('invalid receipt');
    }
    return TransferFrame.text(
      jsonEncode({
        't': 'ack',
        'files': files,
        'bytes': bytes,
        'sha256': ?sha256,
      }),
    );
  }

  static bool _validReceipt(dynamic files, dynamic bytes) =>
      files is num &&
      files.isFinite &&
      files == files.truncateToDouble() &&
      files > 0 &&
      files <= 10 &&
      bytes is num &&
      bytes.isFinite &&
      bytes == bytes.truncateToDouble() &&
      bytes > 0 &&
      bytes <= 9007199254740991;

  static bool _validDigest(String value) {
    if (value.length != 64) return false;
    for (final unit in value.codeUnits) {
      final hex = (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102);
      if (!hex) return false;
    }
    return true;
  }

  /// Lenient parse of an inbound text frame; `null` for anything that is not
  /// a valid protocol frame (never throws).
  static ParsedFrame? parseText(String raw) {
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      json = decoded;
    } catch (_) {
      return null;
    }

    switch (json['t']) {
      case _typeHeader:
        final size = json['size'];
        final token = json['n'];
        if (token is String && size is int) {
          return ParsedFrame(
            FrameKind.header,
            FramedFileMeta(size: size, token: token),
          );
        }
        final name = json['name'];
        if (name is! String || size is! int) return null;
        return ParsedFrame(
          FrameKind.header,
          FramedFileMeta(name: name, size: size),
        );
      case _typeEof:
        final token = json['n'];
        if (token is String) {
          return ParsedFrame(
            FrameKind.eof,
            FramedFileMeta(size: 0, token: token),
          );
        }
        final name = json['name'];
        if (name is! String) return null;
        return ParsedFrame(FrameKind.eof, FramedFileMeta(name: name, size: 0));
      case _typeDone:
        return const ParsedFrame(FrameKind.done, null);
      case _typeHello:
        return ParsedFrame(
          FrameKind.hello,
          null,
          receipts: json['receipts'] == true,
          version: json['v'] is int ? json['v'] as int : 1,
        );
      case 'ack':
        if (!_validReceipt(json['files'], json['bytes'])) return null;
        final digest = json['sha256'];
        if (digest != null && (digest is! String || !_validDigest(digest))) {
          return null;
        }
        return ParsedFrame(
          FrameKind.receipt,
          null,
          files: (json['files'] as num).toInt(),
          bytes: (json['bytes'] as num).toInt(),
          digest: digest as String?,
        );
      default:
        return null;
    }
  }
}

class ParsedFrame {
  final FrameKind kind;
  final FramedFileMeta? meta;
  final bool receipts;
  final int version;
  final int? files;
  final int? bytes;

  /// Lowercase sha256 of the ciphertext, when the peer sent one.
  final String? digest;

  const ParsedFrame(
    this.kind,
    this.meta, {
    this.receipts = false,
    this.version = 1,
    this.files,
    this.bytes,
    this.digest,
  });
}
