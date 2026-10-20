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
  });

  group('control characters are removed', () {
    test('a null byte is dropped', () {
      expect(FileNameSanitizer.safeFileName('with\x00null.txt'), 'withnull.txt');
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
  });

  group('the result is always a single safe segment', () {
    const hostile = <String>[
      '../etc/passwd',
      '..\\..\\windows\\system32',
      '/absolute/path.txt',
      '..',
      'a/b/c/d.txt',
      'name with \x00 null',
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
