import 'dart:convert';

import 'package:client/core/utils/file_name_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sender picks the names in a transfer and every receiver writes those
/// names to disk. These are the rules that keep a name from escaping the
/// download directory.
void main() {
  group('ordinary names are left alone', () {
    test('a plain file name is unchanged', () {
      expect(FileNameSanitizer.safeFileName('photo.jpg'), 'photo.jpg');
    });

    test('a name with spaces and dots is unchanged', () {
      expect(
        FileNameSanitizer.safeFileName('my holiday photo.tar.gz'),
        'my holiday photo.tar.gz',
      );
    });

    test('a dotfile is unchanged', () {
      expect(FileNameSanitizer.safeFileName('.gitignore'), '.gitignore');
    });

    test('a non-latin name is unchanged', () {
      expect(FileNameSanitizer.safeFileName('ünïcödé.txt'), 'ünïcödé.txt');
    });
  });

  group('path segments are removed', () {
    test('a parent directory reference keeps only the last segment', () {
      expect(FileNameSanitizer.safeFileName('../etc/passwd'), 'passwd');
    });

    test('a deep traversal keeps only the last segment', () {
      expect(
        FileNameSanitizer.safeFileName('../../.ssh/authorized_keys'),
        'authorized_keys',
      );
    });

    test('a directory prefix is dropped', () {
      expect(FileNameSanitizer.safeFileName('folder/file.txt'), 'file.txt');
    });

    test('a windows separator is treated as a separator too', () {
      expect(FileNameSanitizer.safeFileName('folder\\file.txt'), 'file.txt');
    });

    test('an absolute windows path keeps only the last segment', () {
      expect(
        FileNameSanitizer.safeFileName('C:\\Windows\\System32\\config'),
        'config',
      );
    });

    test('an absolute posix path keeps only the last segment', () {
      expect(FileNameSanitizer.safeFileName('/etc/passwd'), 'passwd');
    });
  });

  group('names that are not files at all', () {
    test('a lone parent directory reference falls back', () {
      expect(FileNameSanitizer.safeFileName('..'), 'file');
    });

    test('a lone current directory reference falls back', () {
      expect(FileNameSanitizer.safeFileName('.'), 'file');
    });

    test('an empty name falls back', () {
      expect(FileNameSanitizer.safeFileName(''), 'file');
    });

    test('a whitespace-only name falls back', () {
      expect(FileNameSanitizer.safeFileName('   '), 'file');
    });

    test('trailing spaces cannot hide a directory name', () {
      expect(FileNameSanitizer.safeFileName('.. '), 'file');
      expect(FileNameSanitizer.safeFileName('... '), 'file');
      expect(FileNameSanitizer.safeFileName('. '), 'file');
    });

    test('a real name keeps its text after a trailing space', () {
      expect(FileNameSanitizer.safeFileName('file.txt '), 'file.txt');
    });
  });

  group('control characters are removed', () {
    test('a null byte is dropped', () {
      expect(
        FileNameSanitizer.safeFileName('with\x00null.txt'),
        'withnull.txt',
      );
    });

    test('a newline is dropped', () {
      expect(
        FileNameSanitizer.safeFileName('with\nnewline.txt'),
        'withnewline.txt',
      );
    });

    test('a tab is dropped', () {
      expect(FileNameSanitizer.safeFileName('with\ttab.txt'), 'withtab.txt');
    });

    test('a colon is dropped so it cannot name an alternate stream', () {
      expect(
        FileNameSanitizer.safeFileName('report.txt:stream'),
        'report.txtstream',
      );
      expect(FileNameSanitizer.safeFileName(':'), 'file');
    });
  });

  group('bidi formatting controls are removed', () {
    // A control takes no width, so a name with one in it is written one way
    // and shown another: `invoice\u202Egpj.apk` displays as `invoiceapk.jpg`.
    test('a right-to-left override cannot hide the extension', () {
      expect(
        FileNameSanitizer.safeFileName('invoice\u202Egpj.apk'),
        'invoicegpj.apk',
      );
    });

    test('the direction marks are dropped', () {
      expect(
        FileNameSanitizer.safeFileName('left\u200Eright.txt'),
        'leftright.txt',
      );
      expect(
        FileNameSanitizer.safeFileName('left\u200Fright.txt'),
        'leftright.txt',
      );
    });

    test('the embeddings and overrides are dropped', () {
      for (final mark in const [
        '\u202A', // left-to-right embedding
        '\u202B', // right-to-left embedding
        '\u202C', // pop directional formatting
        '\u202D', // left-to-right override
        '\u202E', // right-to-left override
      ]) {
        expect(
          FileNameSanitizer.safeFileName('a${mark}b.txt'),
          'ab.txt',
          reason: 'U+${mark.codeUnitAt(0).toRadixString(16)} survived',
        );
      }
    });

    test('the isolates are dropped', () {
      for (final mark in const [
        '\u2066', // left-to-right isolate
        '\u2067', // right-to-left isolate
        '\u2068', // first strong isolate
        '\u2069', // pop directional isolate
      ]) {
        expect(
          FileNameSanitizer.safeFileName('a${mark}b.txt'),
          'ab.txt',
          reason: 'U+${mark.codeUnitAt(0).toRadixString(16)} survived',
        );
      }
    });

    test('ordinary right-to-left text passes through', () {
      // Removing the formatting controls must not remove the letters of the
      // scripts that use them.
      expect(FileNameSanitizer.safeFileName('חשבונית.pdf'), 'חשבונית.pdf');
      expect(FileNameSanitizer.safeFileName('فاتورة.pdf'), 'فاتورة.pdf');
      expect(
        FileNameSanitizer.safeFileName('تقرير-2026.pdf'),
        'تقرير-2026.pdf',
      );
    });

    test('no bidi control survives any name', () {
      const hostile = <String>[
        'invoice\u202Egpj.apk',
        '\u202Edoc.txt',
        '\u2066report.pdf',
        'a\u200Eb\u202Ac\u2069d.txt',
      ];
      final controls = RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069]');

      for (final raw in hostile) {
        expect(controls.hasMatch(FileNameSanitizer.safeFileName(raw)), isFalse);
      }
    });
  });

  group('a repeated name gets a counter', () {
    test('a name nobody uses is returned as it is', () {
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const []),
        'report.pdf',
      );
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const ['other.pdf']),
        'report.pdf',
      );
    });

    test('the first collision gets (1) before the extension', () {
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const ['report.pdf']),
        'report (1).pdf',
      );
    });

    test('further collisions count up', () {
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const [
          'report.pdf',
          'report (1).pdf',
        ]),
        'report (2).pdf',
      );
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const [
          'report.pdf',
          'report (1).pdf',
          'report (2).pdf',
        ]),
        'report (3).pdf',
      );
    });

    test('a gap in the counters is reused', () {
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const [
          'report.pdf',
          'report (1).pdf',
          'report (3).pdf',
        ]),
        'report (2).pdf',
      );
    });

    test('only the last extension is kept out of the way', () {
      expect(
        FileNameSanitizer.uniqueFileName('archive.tar.gz', const [
          'archive.tar.gz',
        ]),
        'archive.tar (1).gz',
      );
    });

    test('an extension keeps its case', () {
      expect(
        FileNameSanitizer.uniqueFileName('Photo.JPG', const ['Photo.JPG']),
        'Photo (1).JPG',
      );
    });

    test('a dotfile keeps its whole name and gets the counter at the end', () {
      expect(
        FileNameSanitizer.uniqueFileName('.gitignore', const ['.gitignore']),
        '.gitignore (1)',
      );
    });

    test('a name without an extension gets the counter at the end', () {
      expect(
        FileNameSanitizer.uniqueFileName('README', const ['README']),
        'README (1)',
      );
    });

    test('a name with only a trailing dot is treated as having none', () {
      expect(
        FileNameSanitizer.uniqueFileName('report.', const ['report.']),
        'report. (1)',
      );
    });

    test('the comparison ignores case, as the folder may', () {
      expect(
        FileNameSanitizer.uniqueFileName('report.pdf', const ['Report.PDF']),
        'report (1).pdf',
      );
    });

    test('a suffixed name stays inside the byte budget', () {
      final longest = 'a' * 251; // 251 bytes leaves room for ".txt"
      final desired = '$longest.txt';
      expect(desired.length, FileNameSanitizer.maxFileNameBytes);

      final unique = FileNameSanitizer.uniqueFileName(desired, [desired]);

      expect(utf8.encode(unique).length, lessThanOrEqualTo(255));
      expect(unique, endsWith(' (1).txt'));
      expect(unique, startsWith('a' * 247));
    });

    test('a long name without an extension gives up bytes for the counter', () {
      final desired = 'b' * FileNameSanitizer.maxFileNameBytes;

      final unique = FileNameSanitizer.uniqueFileName(desired, [desired]);

      expect(utf8.encode(unique).length, lessThanOrEqualTo(255));
      expect(unique, endsWith(' (1)'));
    });

    test('a multi-byte name is cut on a character boundary', () {
      final desired = '${'é' * 120}.txt'; // 244 bytes

      final unique = FileNameSanitizer.uniqueFileName(desired, [desired]);

      expect(utf8.encode(unique).length, lessThanOrEqualTo(255));
      expect(unique, isNot(contains('�')));
      expect(unique, endsWith(' (1).txt'));
    });

    test('a second save of the same name does not reuse the first path', () {
      final saved = <String>[];
      for (var i = 0; i < 3; i++) {
        final name = FileNameSanitizer.uniqueFileName('note.bin', saved);
        expect(saved, isNot(contains(name)));
        saved.add(name);
      }

      expect(saved, ['note.bin', 'note (1).bin', 'note (2).bin']);
    });
  });

  group('the result is always a single safe segment', () {
    const hostile = <String>[
      '../etc/passwd',
      '..\\..\\windows\\system32',
      '/absolute/path.txt',
      '..',
      'a/b/c/d.txt',
      'name with \x00 null',
      'invoice\u202Egpj.apk',
      '',
    ];

    for (final raw in hostile) {
      test('"$raw" cannot escape the download directory', () {
        final safe = FileNameSanitizer.safeFileName(raw);

        expect(safe, isNot(contains('/')));
        expect(safe, isNot(contains('\\')));
        expect(safe, isNot(startsWith('..')));
        expect(safe, isNotEmpty);
      });
    }
  });

  group('long names are trimmed to the byte budget', () {
    test('a long ascii name is trimmed to 255 bytes', () {
      final safe = FileNameSanitizer.safeFileName('a' * 400);

      expect(safe.length, FileNameSanitizer.maxFileNameBytes);
    });

    test('a multi-byte name is trimmed on a character boundary', () {
      final safe = FileNameSanitizer.safeFileName('é' * 200);

      expect(safe.length, lessThan(200));
      // A split character would leave a replacement character behind.
      expect(safe, isNot(contains('�')));
    });

    test('a name that is already within budget is untouched', () {
      final name = 'a' * FileNameSanitizer.maxFileNameBytes;

      expect(FileNameSanitizer.safeFileName(name), name);
    });
  });
}
