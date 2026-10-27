/// How many files and bytes a direct receive may write.
///
/// Each file is also limited to the size in its header. This budget is the
/// transfer as a whole: one more file, or one more byte than was declared,
/// is refused before it is written.
class ReceiveBudget {
  ReceiveBudget({required this.maxFiles, required this.maxBytes});

  final int maxFiles;
  final int maxBytes;
  int files = 0;
  int bytes = 0;

  bool canStartFile({required bool fileOpen, required int declaredSize}) {
    if (fileOpen || declaredSize < 0 || files >= maxFiles) return false;
    return bytes + declaredSize <= maxBytes;
  }

  bool canAcceptChunk({
    required int writtenInFile,
    required int incoming,
    required int declaredSize,
  }) {
    if (incoming < 0) return false;
    final next = writtenInFile + incoming;
    if (next > declaredSize) return false;
    return bytes + next <= maxBytes;
  }

  void finishFile(int written) {
    files += 1;
    bytes += written;
  }
}
