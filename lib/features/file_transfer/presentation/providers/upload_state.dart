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
  /// - Cloud/R2: free = 15 MB, rewarded-ad unlocked = 30 MB
  /// - P2P:      free = 20 MB, rewarded-ad unlocked = 50 MB
  ///
  /// Both unlocked tiers stay inside the server's 50 MB per-file cap, so every
  /// advertised tier is actually accepted by the API.
  int get maxTotalSizeFree => transferMode == TransferMode.p2p
      ? 20 * 1024 * 1024
      : 15 * 1024 * 1024;

  /// Rewarded-ad unlocked tier (bytes), whatever the current unlock state is.
  int get maxTotalSizeUnlocked => transferMode == TransferMode.p2p
      ? 50 * 1024 * 1024
      : 30 * 1024 * 1024;

  /// The limit that currently applies (bytes).
  int get maxTotalSize =>
      isSizeLimitUnlocked ? maxTotalSizeUnlocked : maxTotalSizeFree;

  /// The current limit in MB: what the user may send right now.
  int get maxTotalSizeMb => maxTotalSize ~/ (1024 * 1024);

  /// The unlocked tier in MB: the number the "watch an ad to unlock" hint has
  /// to advertise.
  int get maxTotalSizeUnlockedMb => maxTotalSizeUnlocked ~/ (1024 * 1024);

  /// The free tier in MB.
  int get maxTotalSizeFreeMb => maxTotalSizeFree ~/ (1024 * 1024);

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
