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

enum FrameKind { header, eof, done, hello }

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
          : {'t': _typeHeader, 'v': _sealedVersion, 'n': meta.token, 'size': meta.size},
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

  static TransferFrame encodeHello([int version = _sealedVersion]) =>
      TransferFrame.text(jsonEncode({'t': _typeHello, 'v': version}));

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
        return const ParsedFrame(FrameKind.hello, null);
      default:
        return null;
    }
  }
}

class ParsedFrame {
  final FrameKind kind;
  final FramedFileMeta? meta;

  const ParsedFrame(this.kind, this.meta);
}
