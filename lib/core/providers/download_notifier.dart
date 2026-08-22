import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/download_service.dart';
import 'download_state.dart';
import 'transfer_providers.dart';
import '../../features/file_receive/domain/usecases/decrypt_file_use_case.dart';
import '../../features/file_transfer/domain/entities/file_item.dart';
import '../../features/recent_transfers/data/models/recent_transfer_record_model.dart';
import '../../features/recent_transfers/domain/entities/recent_transfer_record.dart';
import '../../features/recent_transfers/presentation/providers/recent_transfers_notifier.dart';

part 'download_notifier.g.dart';

@riverpod
DownloadService downloadService(Ref ref) => DownloadService();

@Riverpod(keepAlive: true)
class DownloadNotifier extends _$DownloadNotifier {
  CancelToken? _cancelToken;

  @override
  DownloadState build() => const DownloadState();

  Future<void> loadTransferPreview(String transferId) async {
    state = const DownloadState(phase: DownloadPhase.idle);
    final repo = ref.read(transferRepositoryProvider);
    final result = await repo.getTransferMetadata(transferId);

    result.fold(
      (transfer) async {
        state = state.copyWith(
          transfer: transfer,
          phase: DownloadPhase.preview,
        );

        // Pre-fetch presigned download URLs so startDownload begins instantly
        final urlResult = await repo.getDownloadUrls(transferId: transfer.id);
        urlResult.fold((downloadFiles) {
          state = state.copyWith(downloadFiles: downloadFiles);
        }, (_) {});
      },
      (failure) {
        state = state.copyWith(
          phase: DownloadPhase.failed,
          errorMessage: failure.message,
        );
      },
    );
  }

  Future<void> startDownload({String? aesKey}) async {
    if (state.transfer == null) return;

    // Strict key resolution: only the explicitly provided key (from the QR
    // #fragment or the in-memory unwrapped wrapped_key) may be used. No
    // cross-provider stale-key fallbacks.
    String? key = (aesKey != null && aesKey.isNotEmpty) ? aesKey : state.aesKey;
    if (key == null || key.isEmpty) {
      state = state.copyWith(
        phase: DownloadPhase.failed,
        errorMessage:
            'Decryption key missing. Please scan the sender QR code again.',
      );
      return;
    }

    state = state.copyWith(
      phase: DownloadPhase.downloading,
      aesKey: key,
      currentFileIndex: 0,
      overallProgress: 0.0,
    );
    _cancelToken = CancelToken();

    final repo = ref.read(transferRepositoryProvider);
    final downloadService = ref.read(downloadServiceProvider);
    final decryptUseCase = ref.read(decryptFileUseCaseProvider);

    List<FileItem> downloadFiles = state.downloadFiles;
    if (downloadFiles.isEmpty) {
      final urlResult = await repo.getDownloadUrls(
        transferId: state.transfer!.id,
      );

      if (urlResult.isFailure) {
        state = state.copyWith(
          phase: DownloadPhase.failed,
          errorMessage: urlResult.failure?.message ?? 'Failed fetching URLs',
        );
        return;
      }
      downloadFiles = urlResult.value!;
      state = state.copyWith(downloadFiles: downloadFiles);
    }

    Directory? saveDir;
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        final lynkPublicDir = Directory('/storage/emulated/0/Download/Lynk');
        if (!await lynkPublicDir.exists()) {
          await lynkPublicDir.create(recursive: true);
        }
        saveDir = lynkPublicDir;
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }
    }

    final downloadedPaths = <String>[];
    int cumulativeBytes = 0;
    final totalSize = state.transfer!.totalSize;

    for (int i = 0; i < downloadFiles.length; i++) {
      if (_cancelToken?.isCancelled ?? false) return;

      final item = downloadFiles[i];
      state = state.copyWith(currentFileIndex: i, currentFileProgress: 0.0);

      try {
        if (kIsWeb) {
          final encBytes = await downloadService.downloadBytesFromR2(
            downloadUrl: item.downloadUrl!,
            cancelToken: _cancelToken,
            onProgress: (received, total) {
              final fileProgress = total > 0 ? received / total : 0.0;
              final overall = totalSize > 0
                  ? (cumulativeBytes + received) / totalSize
                  : 0.0;
              state = state.copyWith(
                currentFileProgress: fileProgress,
                overallProgress: overall.clamp(0.0, 1.0),
              );
            },
          );

          Uint8List finalBytes = encBytes;
          if (key.isNotEmpty) {
            finalBytes = decryptUseCase.executeBytes(
              encryptedBytes: encBytes,
              aesKey32Bytes: key,
            );
          }
          downloadedPaths.add('${item.name} (${finalBytes.length} bytes)');
        } else {
          final savePath = '${saveDir!.path}/${item.name}';
          final tempSavePath = '$savePath.enc';

          await downloadService.downloadFileFromR2(
            downloadUrl: item.downloadUrl!,
            savePath: tempSavePath,
            cancelToken: _cancelToken,
            onProgress: (received, total) {
              final fileProgress = total > 0 ? received / total : 0.0;
              final overall = totalSize > 0
                  ? (cumulativeBytes + received) / totalSize
                  : 0.0;
              state = state.copyWith(
                currentFileProgress: fileProgress,
                overallProgress: overall.clamp(0.0, 1.0),
              );
            },
          );

          // Decrypt the downloaded file using resolved key
          if (key.isNotEmpty) {
            await decryptUseCase.execute(
              encryptedFile: File(tempSavePath),
              aesKey32Bytes: key,
              outputPath: savePath,
            );
            final tempFile = File(tempSavePath);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } else {
            throw Exception(
              'Decryption key missing for file "${item.name}". Please scan QR code again.',
            );
          }

          downloadedPaths.add(savePath);
        }

        cumulativeBytes += item.size;
      } catch (e) {
        if (_cancelToken?.isCancelled ?? false) return;
        state = state.copyWith(
          phase: DownloadPhase.failed,
          errorMessage: 'Failed downloading ${item.name}: $e',
        );
        return;
      }
    }

    state = state.copyWith(
      phase: DownloadPhase.completed,
      overallProgress: 1.0,
      downloadedPaths: downloadedPaths,
    );

    ref
        .read(recentTransfersProvider.notifier)
        .addRecord(
          RecentTransferRecordModel(
            id: state.transfer?.id ?? '',
            type: RecentTransferType.received,
            fileNames: downloadFiles.map((f) => f.name).toList(),
            totalSize: totalSize,
            timestamp: DateTime.now(),
            status: 'completed',
            filePaths: downloadedPaths,
          ),
        );
  }

  Future<void> openFile(String path) async {
    if (!kIsWeb) {
      await OpenFilex.open(path);
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    state = state.copyWith(phase: DownloadPhase.cancelled);
  }
}
