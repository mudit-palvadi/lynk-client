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
class FramedFileMeta {
  final String name;
  final int size;

  const FramedFileMeta({required this.name, required this.size});
}

enum FrameKind { header, eof, done }

/// Minimal, stable wire protocol framing file transfers over the binary
/// DataChannel (POTENTIAL_ISSUES #1: shared contract with the web receiver).
///
/// - Text frame `{"t":"hdr","name":...,"size":N}` precedes each file's
///   encrypted byte stream (size = encrypted length incl. IV prefix).
/// - Binary frames carry the raw encrypted chunks in order.
/// - Text frame `{"t":"eof","name":...}` marks one file complete.
/// - Text frame `{"t":"done"}` marks the whole transfer complete.
class TransferFramer {
  static const String _typeHeader = 'hdr';
  static const String _typeEof = 'eof';
  static const String _typeDone = 'done';

  const TransferFramer._();

  static TransferFrame encodeHeader(FramedFileMeta meta) => TransferFrame.text(
    jsonEncode({'t': _typeHeader, 'name': meta.name, 'size': meta.size}),
  );

  static TransferFrame encodeEof(FramedFileMeta meta) =>
      TransferFrame.text(jsonEncode({'t': _typeEof, 'name': meta.name}));

  static TransferFrame encodeDone() =>
      TransferFrame.text(jsonEncode({'t': _typeDone}));

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
        final name = json['name'];
        final size = json['size'];
        if (name is! String || size is! int) return null;
        return ParsedFrame(
          FrameKind.header,
          FramedFileMeta(name: name, size: size),
        );
      case _typeEof:
        final name = json['name'];
        if (name is! String) return null;
        return ParsedFrame(FrameKind.eof, FramedFileMeta(name: name, size: 0));
      case _typeDone:
        return const ParsedFrame(FrameKind.done, null);
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
