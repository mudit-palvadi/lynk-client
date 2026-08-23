import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/download_service.dart';
import '../services/flutter_webrtc_p2p_session.dart';
import '../services/webrtc_peer.dart';
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

  /// Receiver entry point: try a direct WebRTC P2P reception first; if the
  /// sender fell back to R2 (or the channel never opens), fall back to the
  /// normal R2 download pipeline automatically.
  Future<void> startReception({String? aesKey}) async {
    if (state.transfer == null) return;
    if (kIsWeb) {
      await startDownload(aesKey: aesKey);
      return;
    }

    final received = await _tryP2PReceive(aesKey: aesKey);
    if (!received) {
      await startDownload(aesKey: aesKey);
    }
  }

  static Uri _signalingUri(String sessionId) {
    final base =
        dotenv.env['API_BASE_URL'] ?? 'http://140.245.220.117:8000/api/v1/';
    final parsed = Uri.parse(base);
    final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: parsed.host,
      port: parsed.port,
      path: '/ws/signaling/$sessionId',
    );
  }

  /// Listens on the signaling room as the WebRTC receiver, decrypts each
  /// inbound encrypted file and returns `true` when the whole transfer
  /// arrived over the DataChannel.
  Future<bool> _tryP2PReceive({String? aesKey}) async {
    String? key = (aesKey != null && aesKey.isNotEmpty) ? aesKey : state.aesKey;
    if (key == null || key.isEmpty || state.transfer == null) return false;

    P2PFileSession? session;
    final decryptedPaths = <String>[];
    Directory? saveDir;
    try {
      if (Platform.isAndroid) {
        final lynkPublicDir = Directory('/storage/emulated/0/Download/Lynk');
        if (!await lynkPublicDir.exists()) {
          await lynkPublicDir.create(recursive: true);
        }
        saveDir = lynkPublicDir;
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }

      session = await P2PFileSession.connect(
        signalingUrl: _signalingUri(state.transfer!.id),
        role: PeerRole.receiver,
      );

      state = state.copyWith(
        phase: DownloadPhase.downloading,
        aesKey: key,
        overallProgress: 0.0,
      );

      final outcome = Completer<bool>();
      session.onFallbackToCloud = () {
        if (!outcome.isCompleted) outcome.complete(false);
      };

      int filesDone = 0;
      final expectedFiles = state.transfer!.totalFiles > 0
          ? state.transfer!.totalFiles
          : 1;
      final sub = session.onFileReceived.listen((encTempFile) async {
        try {
          final originalName = encTempFile.path
              .split('/')
              .last
              .split(Platform.pathSeparator)
              .last
              .replaceFirst(RegExp(r'^\d+_'), '');
          final savePath = '${saveDir!.path}/$originalName';
          await ref
              .read(decryptFileUseCaseProvider)
              .execute(
                encryptedFile: encTempFile,
                aesKey32Bytes: key,
                outputPath: savePath,
              );
          await encTempFile.delete();
          decryptedPaths.add(savePath);
          filesDone++;
          state = state.copyWith(
            currentFileIndex: filesDone - 1,
            currentFileProgress: 1.0,
            overallProgress: (filesDone / expectedFiles).clamp(0.0, 1.0),
          );
          if (filesDone >= expectedFiles && !outcome.isCompleted) {
            // Wait for the sender's `done` frame; complete via transferDone.
          }
        } catch (_) {
          if (!outcome.isCompleted) outcome.complete(false);
        }
      });

      unawaited(
        session.transferDone
            .then((_) {
              if (!outcome.isCompleted && decryptedPaths.isNotEmpty) {
                outcome.complete(true);
              }
            })
            .catchError((Object _) {
              if (!outcome.isCompleted) outcome.complete(false);
            }),
      );

      final ok = await outcome.future;
      await sub.cancel();
      if (!ok || decryptedPaths.isEmpty) return false;

      state = state.copyWith(
        phase: DownloadPhase.completed,
        overallProgress: 1.0,
        downloadedPaths: decryptedPaths,
      );
      ref
          .read(recentTransfersProvider.notifier)
          .addRecord(
            RecentTransferRecordModel(
              id: state.transfer?.id ?? '',
              type: RecentTransferType.received,
              fileNames: decryptedPaths
                  .map((p) => p.split(Platform.pathSeparator).last)
                  .toList(),
              totalSize: state.transfer!.totalSize,
              timestamp: DateTime.now(),
              status: 'completed (p2p)',
              filePaths: decryptedPaths,
            ),
          );
      return true;
    } catch (_) {
      return false;
    } finally {
      await session?.dispose();
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    state = state.copyWith(phase: DownloadPhase.cancelled);
  }
}
