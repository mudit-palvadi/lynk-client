import 'dart:math';

class FileSizeFormatter {
  static String format(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    var num = bytes / pow(1024, i);
    return '${num.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
  }
}
