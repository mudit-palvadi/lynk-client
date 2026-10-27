import 'dart:convert';

/// Makes a sender-supplied file name safe to write to disk.
///
/// A sender picks the names in a transfer and every receiver writes those
/// names straight into its download directory. A name like
/// `../../.ssh/authorized_keys` would therefore write outside that
/// directory, so every name that reaches the file system goes through here
/// first.
///
/// The server applies the same rules to names that arrive over the API, but
/// the peer-to-peer channel has no server in the middle: the receiving peer
/// has to be able to trust nothing but its own checks.
class FileNameSanitizer {
  FileNameSanitizer._();

  /// The longest name most filesystems accept, in bytes rather than
  /// characters: a multi-byte name is far shorter in characters than in bytes.
  static const int maxFileNameBytes = 255;

  /// NUL and the other control characters. They truncate paths on some
  /// platforms and corrupt them on others.
  static final RegExp _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

  /// A name made only of dots is a directory reference (`.`, `..`), never a
  /// file.
  static final RegExp _onlyDots = RegExp(r'^\.+$');

  /// Reduces [raw] to a single, safe path segment.
  ///
  /// The last path segment is kept, so `photos/2024/img.jpg` and
  /// `../../img.jpg` both become `img.jpg`. Everything that could still
  /// escape the target directory is removed, and a name that is left with
  /// nothing usable falls back to `file`.
  static String safeFileName(String raw) {
    // Treat a Windows separator as a separator too, so a name crafted for
    // Windows cannot slip past on POSIX.
    var name = raw.replaceAll('\\', '/');

    final lastSeparator = name.lastIndexOf('/');
    if (lastSeparator >= 0) {
      name = name.substring(lastSeparator + 1);
    }

    // A colon is an alternate data stream on Windows, so it is not part of
    // the name that gets written.
    name = name.replaceAll(_controlCharacters, '').replaceAll(':', '');

    if (name.trim().isEmpty || _onlyDots.hasMatch(name)) {
      return 'file';
    }

    return _truncateToBytes(name, maxFileNameBytes);
  }

  /// Trims [name] to [maxBytes] UTF-8 bytes without splitting a character.
  static String _truncateToBytes(String name, int maxBytes) {
    final encoded = utf8.encode(name);
    if (encoded.length <= maxBytes) return name;

    final result = StringBuffer();
    var used = 0;
    for (final rune in name.runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (used + size > maxBytes) break;
      result.writeCharCode(rune);
      used += size;
    }
    final truncated = result.toString();

    // Trimming can leave nothing behind (a name of pure multi-byte padding).
    return truncated.trim().isEmpty ? 'file' : truncated;
  }
}
