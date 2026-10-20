import 'package:equatable/equatable.dart';
import '../../features/file_transfer/domain/entities/file_item.dart';
import '../../features/file_transfer/domain/entities/transfer.dart';

enum DownloadPhase { idle, preview, downloading, completed, failed, cancelled }

class DownloadState extends Equatable {
  final Transfer? transfer;
  final List<FileItem> downloadFiles;
  final String? aesKey;
  final String? accessToken;
  final int currentFileIndex;
  final double currentFileProgress;
  final double overallProgress;
  final DownloadPhase phase;
  final List<String> downloadedPaths;
  final String? errorMessage;

  const DownloadState({
    this.transfer,
    this.downloadFiles = const [],
    this.aesKey,
    this.accessToken,
    this.currentFileIndex = 0,
    this.currentFileProgress = 0.0,
    this.overallProgress = 0.0,
    this.phase = DownloadPhase.idle,
    this.downloadedPaths = const [],
    this.errorMessage,
  });

  DownloadState copyWith({
    Transfer? transfer,
    List<FileItem>? downloadFiles,
    String? aesKey,
    String? accessToken,
    int? currentFileIndex,
    double? currentFileProgress,
    double? overallProgress,
    DownloadPhase? phase,
    List<String>? downloadedPaths,
    String? errorMessage,
  }) {
    return DownloadState(
      transfer: transfer ?? this.transfer,
      downloadFiles: downloadFiles ?? this.downloadFiles,
      aesKey: aesKey ?? this.aesKey,
      accessToken: accessToken ?? this.accessToken,
      currentFileIndex: currentFileIndex ?? this.currentFileIndex,
      currentFileProgress: currentFileProgress ?? this.currentFileProgress,
      overallProgress: overallProgress ?? this.overallProgress,
      phase: phase ?? this.phase,
      downloadedPaths: downloadedPaths ?? this.downloadedPaths,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    transfer,
    downloadFiles,
    aesKey,
    accessToken,
    currentFileIndex,
    currentFileProgress,
    overallProgress,
    phase,
    downloadedPaths,
    errorMessage,
  ];
}
