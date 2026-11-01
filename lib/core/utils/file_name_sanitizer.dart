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

  /// The Unicode bidirectional formatting controls.
  ///
  /// They take no width of their own, so they reorder the text around them
  /// rather than appearing in it. A name like `invoice\u202Egpj.apk` is shown
  /// as `invoiceapk.jpg`: the bytes on disk say one thing and every file
  /// manager shows another. Only the controls are removed, so ordinary Arabic
  /// and Hebrew letters survive.
  static final RegExp _bidiControls = RegExp(
    r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );

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
    // the name that gets written. Windows also drops trailing dots and
    // spaces, so ".. " would otherwise land as "..".
    name = name
        .replaceAll(_controlCharacters, '')
        .replaceAll(_bidiControls, '')
        .replaceAll(':', '')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');

    if (name.isEmpty || _onlyDots.hasMatch(name)) {
      return 'file';
    }

    return _truncateToBytes(name, maxFileNameBytes);
  }

  /// A version of [desired] that none of [existing] already uses.
  ///
  /// Two files with the same name would otherwise land on the same path, and
  /// the second would replace the first. A counter is inserted before the
  /// extension instead: `report.pdf`, then `report (1).pdf`, then
  /// `report (2).pdf`. A name without an extension, including a dotfile such
  /// as `.gitignore`, gets the counter at the end.
  ///
  /// The comparison ignores case because the shared folders Android hands out
  /// are usually case-insensitive, and the byte budget still applies to a
  /// suffixed name: the stem is shortened to make room for the suffix.
  static String uniqueFileName(String desired, Iterable<String> existing) {
    final taken = existing.map(_foldCase).toSet();
    if (!taken.contains(_foldCase(desired))) return desired;

    final dot = desired.lastIndexOf('.');
    // A leading dot is not an extension: it is a dotfile.
    final hasExtension = dot > 0 && dot < desired.length - 1;
    final stem = hasExtension ? desired.substring(0, dot) : desired;
    final extension = hasExtension ? desired.substring(dot) : '';

    // Every candidate is distinct and [taken] is finite, so this ends.
    for (var index = 1; ; index++) {
      final candidate = _suffixed(stem, extension, index);
      if (!taken.contains(_foldCase(candidate))) return candidate;
    }
  }

  /// Lowercases the name so that a different case cannot slip past the same
  /// file on a case-insensitive folder.
  static String _foldCase(String name) => name.toLowerCase();

  /// Builds `stem (index)extension` inside the byte budget.
  ///
  /// The suffix and the extension are kept whole; only the stem gives way.
  static String _suffixed(String stem, String extension, int index) {
    final tail = ' ($index)$extension';
    final budget = maxFileNameBytes - utf8.encode(tail).length;
    final head = budget <= 0 ? '' : _truncateToBytes(stem, budget);
    final name = '$head$tail';

    // A pathological extension can fill the budget on its own.
    return utf8.encode(name).length <= maxFileNameBytes
        ? name
        : _truncateToBytes(name, maxFileNameBytes);
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
