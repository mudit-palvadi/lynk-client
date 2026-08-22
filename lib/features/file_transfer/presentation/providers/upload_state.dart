import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/entities/transfer.dart';

enum UploadPhase { idle, selecting, uploading, completed, failed, cancelled }

enum TransferMode { p2p, cloud }

class UploadState extends Equatable {
  final List<PlatformFile> selectedFiles;
  final Transfer? transfer;
  final String? aesKey;
  final int currentFileIndex;
  final double currentFileProgress;
  final double overallProgress;
  final int bytesUploaded;
  final UploadPhase phase;
  final String? errorMessage;
  final bool isSizeLimitUnlocked;
  final TransferMode transferMode;

  const UploadState({
    this.selectedFiles = const [],
    this.transfer,
    this.aesKey,
    this.currentFileIndex = 0,
    this.currentFileProgress = 0.0,
    this.overallProgress = 0.0,
    this.bytesUploaded = 0,
    this.phase = UploadPhase.idle,
    this.errorMessage,
    this.isSizeLimitUnlocked = false,
    this.transferMode = TransferMode.cloud,
  });

  int get totalSize =>
      selectedFiles.fold(0, (sum, f) => sum + ((f.size ~/ 16) + 1) * 16 + 16);

  /// Size tiers (bytes):
  /// - Cloud/R2: free = 20 MB, rewarded-ad unlocked = 50 MB
  /// - P2P:      free = 50 MB, rewarded-ad unlocked = 100 MB
  int get maxTotalSize {
    if (transferMode == TransferMode.p2p) {
      return isSizeLimitUnlocked ? 100 * 1024 * 1024 : 50 * 1024 * 1024;
    }
    return isSizeLimitUnlocked ? 50 * 1024 * 1024 : 20 * 1024 * 1024;
  }

  int get maxTotalSizeUnlockedMb => maxTotalSize ~/ (1024 * 1024);

  UploadState copyWith({
    List<PlatformFile>? selectedFiles,
    Transfer? transfer,
    String? aesKey,
    int? currentFileIndex,
    double? currentFileProgress,
    double? overallProgress,
    int? bytesUploaded,
    UploadPhase? phase,
    String? errorMessage,
    bool? isSizeLimitUnlocked,
    TransferMode? transferMode,
  }) {
    return UploadState(
      selectedFiles: selectedFiles ?? this.selectedFiles,
      transfer: transfer ?? this.transfer,
      aesKey: aesKey ?? this.aesKey,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      currentFileProgress: currentFileProgress ?? this.currentFileProgress,
      overallProgress: overallProgress ?? this.overallProgress,
      bytesUploaded: bytesUploaded ?? this.bytesUploaded,
      phase: phase ?? this.phase,
      errorMessage: errorMessage ?? this.errorMessage,
      isSizeLimitUnlocked: isSizeLimitUnlocked ?? this.isSizeLimitUnlocked,
      transferMode: transferMode ?? this.transferMode,
    );
  }

  @override
  List<Object?> get props => [
    selectedFiles,
    transfer,
    aesKey,
    currentFileIndex,
    currentFileProgress,
    overallProgress,
    bytesUploaded,
    phase,
    errorMessage,
    isSizeLimitUnlocked,
    transferMode,
  ];
}
