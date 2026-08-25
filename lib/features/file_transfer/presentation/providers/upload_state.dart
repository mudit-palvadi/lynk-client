import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/entities/transfer.dart';

enum UploadPhase { idle, selecting, uploading, completed, failed, cancelled }

enum TransferMode { p2p, cloud }

/// Fine-grained sender-side P2P progress, so the UI can show the QR/waiting
/// panel instead of a fake upload percentage.
enum P2PSendStage { none, preparing, waitingForReceiver, transferring }

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
  final P2PSendStage p2pStage;

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
    this.p2pStage = P2PSendStage.none,
  });

  int get totalSize =>
      selectedFiles.fold(0, (sum, f) => sum + ((f.size ~/ 16) + 1) * 16 + 16);

  /// Size tiers (bytes):
  /// - Cloud/R2: free = 20 MB, rewarded-ad unlocked = 50 MB
  /// - P2P:      free = 10 MB, rewarded-ad unlocked = 200 MB
  int get maxTotalSize {
    if (transferMode == TransferMode.p2p) {
      return isSizeLimitUnlocked ? 200 * 1024 * 1024 : 10 * 1024 * 1024;
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
    P2PSendStage? p2pStage,
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
      p2pStage: p2pStage ?? this.p2pStage,
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
    p2pStage,
  ];
}
