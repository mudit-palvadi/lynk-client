import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/services/upload_service.dart';
import 'package:client/core/providers/receiver_providers.dart';
import 'package:client/core/services/key_wrap_service.dart';
import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/core/services/webrtc_peer.dart';
import 'package:client/core/utils/entropy_generator.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/services/file_picker_service.dart';
import '../../../recent_transfers/data/models/recent_transfer_record_model.dart';
import '../../../recent_transfers/domain/entities/recent_transfer_record.dart';
import '../../../recent_transfers/presentation/providers/recent_transfers_notifier.dart';
import 'upload_state.dart';

part 'upload_notifier.g.dart';

@riverpod
UploadService uploadService(Ref ref) => UploadService();

@Riverpod(keepAlive: true)
class UploadNotifier extends _$UploadNotifier {
  CancelToken? _cancelToken;

  @override
  UploadState build() => const UploadState();

  Future<void> pickFiles() async {
    final picker = ref.read(filePickerServiceProvider);
    final result = await picker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final files = result.files;
    if (files.length > 10) {
      state = state.copyWith(
        phase: UploadPhase.failed,
        errorMessage: 'Maximum 10 files per transfer',
      );
      return;
    }

    if (!_validateSizes(files)) return;

    state = state.copyWith(selectedFiles: files, phase: UploadPhase.selecting);
  }

  void unlockExtendedSizeLimit() {
    state = state.copyWith(isSizeLimitUnlocked: true);
  }

  /// Enforces the per-mode size tiers against the current unlocked state:
  /// - Cloud/R2: free 20 MB -> unlocked 50 MB
  /// - P2P: free 50 MB -> unlocked 100 MB
  bool _validateSizes(List<PlatformFile> files) {
    final totalSize = files.fold(0, (sum, f) => sum + f.size);
    final maxLimit = state.maxTotalSize;
    final maxMb = state.maxTotalSizeUnlockedMb;
    final freeMb = state.transferMode == TransferMode.p2p ? 50 : 20;

    if (totalSize > maxLimit) {
      final msg = state.isSizeLimitUnlocked
          ? 'Total transfer limit is $maxMb MB'
          : 'Free limit is $freeMb MB. Watch an ad to unlock up to $maxMb MB!';
      state = state.copyWith(phase: UploadPhase.failed, errorMessage: msg);
      return false;
    }

    for (var f in files) {
      if (f.size > maxLimit) {
        final msg = state.isSizeLimitUnlocked
            ? 'File "${f.name}" exceeds $maxMb MB limit'
            : 'File "${f.name}" exceeds the $freeMb MB free limit. Watch an ad to unlock up to $maxMb MB!';
        state = state.copyWith(phase: UploadPhase.failed, errorMessage: msg);
        return false;
      }
    }

    return true;
  }

  Future<void> pickMedia() async {
    final picker = ref.read(filePickerServiceProvider);
    final result = await picker.pickMedia(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final files = result.files;
    if (files.length > 10) {
      state = state.copyWith(
        phase: UploadPhase.failed,
        errorMessage: 'Maximum 10 files per transfer',
      );
      return;
    }

    if (!_validateSizes(files)) return;

    // Preserve tier unlock state and mode when committing the selection.
    state = state.copyWith(selectedFiles: files, phase: UploadPhase.selecting);
  }

  void setTransferMode(TransferMode mode) {
    state = state.copyWith(transferMode: mode);
  }

  void setFilesForTesting(List<PlatformFile> files) {
    state = UploadState(selectedFiles: files, phase: UploadPhase.selecting);
  }

  void removeFile(int index) {
    final updated = List<PlatformFile>.from(state.selectedFiles)
      ..removeAt(index);
    state = state.copyWith(
      selectedFiles: updated,
      phase: updated.isEmpty ? UploadPhase.idle : UploadPhase.selecting,
    );
  }

  Future<void> startUpload({
    String? attachToSessionId,
    String? receiverPk,
  }) async {
    if (state.selectedFiles.isEmpty) return;

    state = state.copyWith(
      phase: UploadPhase.uploading,
      currentFileIndex: 0,
      overallProgress: 0.0,
    );
    _cancelToken = CancelToken();

    final repo = ref.read(transferRepositoryProvider);
    final uploadService = ref.read(uploadServiceProvider);
    final encryptUseCase = ref.read(encryptFileUseCaseProvider);

    // 1. Generate the dynamic entropy key (UUID + Temp + Timestamp)
    final aesKey = await EntropyGenerator.generateKey();
    state = state.copyWith(aesKey: aesKey);

    // 2. Map file items with exact encrypted sizes
    final fileItems = state.selectedFiles.map((f) {
      final encSize = ((f.size ~/ 16) + 1) * 16 + 16;
      return FileItem(
        id: '',
        name: f.name,
        size: encSize,
        contentType: 'application/octet-stream',
        status: FileStatus.pending,
      );
    }).toList();

    final createResult = await repo.createTransfer(fileItems);

    createResult.fold(
      (transfer) async {
        final effectiveTotalSize = transfer.totalSize > 0
            ? transfer.totalSize
            : state.totalSize;
        final updatedTransfer = transfer.copyWith(
          totalSize: effectiveTotalSize,
          totalFiles: transfer.totalFiles > 0
              ? transfer.totalFiles
              : state.selectedFiles.length,
        );
        state = state.copyWith(transfer: updatedTransfer);

        // ⚡ P2P mode: attempt a direct WebRTC transfer first. If it cannot
        // connect within the 8s window (or dies mid-transfer), fall through
        // to the R2 cloud pipeline below — the receiver does the same.
        if (state.transferMode == TransferMode.p2p) {
          final p2pCompleted = await _runP2PSend(
            transferId: transfer.id,
            aesKey: aesKey,
          );
          if (p2pCompleted) return;
        }

        int cumulativeBytes = 0;

        for (int i = 0; i < state.selectedFiles.length; i++) {
          if (_cancelToken?.isCancelled ?? false) return;

          final pFile = state.selectedFiles[i];
          final item = transfer.files[i];

          state = state.copyWith(currentFileIndex: i, currentFileProgress: 0.0);

          try {
            File? encryptedFile;
            Uint8List? encryptedBytes;

            if (pFile.path != null) {
              encryptedFile = await encryptUseCase.execute(
                inputFile: File(pFile.path!),
                aesKey32Bytes: aesKey,
              );
            } else if (pFile.bytes != null) {
              encryptedBytes = encryptUseCase.executeBytes(
                inputBytes: pFile.bytes!,
                aesKey32Bytes: aesKey,
              );
            } else {
              throw ArgumentError('File has no valid path or bytes payload');
            }

            final int encSize =
                encryptedBytes?.length ?? await encryptedFile!.length();

            await uploadService.uploadFileToR2(
              name: pFile.name,
              size: encSize,
              contentType: item.contentType,
              uploadUrl: item.uploadUrl!,
              file: encryptedFile,
              bytes: encryptedBytes,
              cancelToken: _cancelToken,
              onProgress: (sent, total) {
                final fileProgress = sent / total;
                final currentOverall =
                    (cumulativeBytes + sent) / state.totalSize;
                state = state.copyWith(
                  currentFileProgress: fileProgress,
                  overallProgress: currentOverall.clamp(0.0, 1.0),
                );
              },
            );

            // Clean up temp file on native platforms
            if (encryptedFile != null && await encryptedFile.exists()) {
              await encryptedFile.delete();
            }

            await repo.completeFileUpload(
              transferId: transfer.id,
              fileId: item.id,
            );
            cumulativeBytes += encSize;
          } catch (e) {
            if (_cancelToken?.isCancelled ?? false) return;
            state = state.copyWith(
              phase: UploadPhase.failed,
              errorMessage: 'Failed uploading ${pFile.name}: $e',
            );
            return;
          }
        }

        if (attachToSessionId != null) {
          final receiverRepo = ref.read(receiverRepositoryProvider);

          // Zero-knowledge: wrap the AES key to the receiver's ephemeral
          // public key. Only opaque ciphertext is transmitted.
          String? wrappedKey;
          if (receiverPk != null && receiverPk.isNotEmpty) {
            try {
              wrappedKey = await KeyWrapService().wrapKey(
                aesKey: aesKey,
                receiverPublicKeyB64: receiverPk,
                sessionId: attachToSessionId,
              );
            } catch (_) {
              wrappedKey = null;
            }
          }

          await receiverRepo.attachTransfer(
            sessionId: attachToSessionId,
            transferId: transfer.id,
            wrappedKey: wrappedKey,
          );
        }

        state = state.copyWith(
          phase: UploadPhase.completed,
          overallProgress: 1.0,
        );

        ref
            .read(recentTransfersProvider.notifier)
            .addRecord(
              RecentTransferRecordModel(
                id: transfer.id,
                type: RecentTransferType.sent,
                fileNames: state.selectedFiles.map((f) => f.name).toList(),
                totalSize: state.totalSize,
                timestamp: DateTime.now(),
                status: 'completed',
                filePaths: state.selectedFiles
                    .where((f) => f.path != null)
                    .map((f) => f.path!)
                    .toList(),
              ),
            );
      },
      (failure) async {
        state = state.copyWith(
          phase: UploadPhase.failed,
          errorMessage: failure.message,
        );
      },
    );
  }

  void reset() {
    _cancelToken?.cancel();
    state = const UploadState();
  }

  /// Derives the signaling WebSocket URI for a session from `API_BASE_URL`.
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

  /// Attempts the direct WebRTC P2P transfer for the selected files.
  ///
  /// Returns `true` when every file reached the receiver over the
  /// DataChannel; `false` on connect-timeout / channel failure so the caller
  /// falls back to the R2 pipeline (Phases.md acceptance criteria).
  Future<bool> _runP2PSend({
    required String transferId,
    required String aesKey,
  }) async {
    if (kIsWeb) return false;

    P2PFileSession? session;
    final tempEncrypted = <File>[];
    try {
      // Encrypt everything up-front so channel-open time is spent sending.
      final encryptUseCase = ref.read(encryptFileUseCaseProvider);
      for (final pFile in state.selectedFiles) {
        if (pFile.path == null) return false; // bytes-only pickers: use R2
        final encrypted = await encryptUseCase.execute(
          inputFile: File(pFile.path!),
          aesKey32Bytes: aesKey,
        );
        tempEncrypted.add(encrypted);
      }

      session = await P2PFileSession.connect(
        signalingUrl: _signalingUri(transferId),
        role: PeerRole.sender,
      );

      final outcome = Completer<bool>();
      session.onFallbackToCloud = () {
        if (!outcome.isCompleted) outcome.complete(false);
      };
      unawaited(
        session
            .sendFiles(tempEncrypted)
            .then((_) {
              if (!outcome.isCompleted) outcome.complete(true);
            })
            .catchError((Object _) {
              if (!outcome.isCompleted) outcome.complete(false);
            }),
      );

      final delivered = await outcome.future;
      if (!delivered) return false;

      // Zero-knowledge guarantee still holds over P2P — nothing was uploaded.
      state = state.copyWith(
        phase: UploadPhase.completed,
        overallProgress: 1.0,
      );
      ref
          .read(recentTransfersProvider.notifier)
          .addRecord(
            RecentTransferRecordModel(
              id: transferId,
              type: RecentTransferType.sent,
              fileNames: state.selectedFiles.map((f) => f.name).toList(),
              totalSize: state.totalSize,
              timestamp: DateTime.now(),
              status: 'completed (p2p)',
              filePaths: state.selectedFiles
                  .where((f) => f.path != null)
                  .map((f) => f.path!)
                  .toList(),
            ),
          );
      return true;
    } catch (_) {
      return false;
    } finally {
      await session?.dispose();
      for (final f in tempEncrypted) {
        if (await f.exists()) await f.delete();
      }
    }
  }

  void cancelUpload() {
    _cancelToken?.cancel();
    if (state.transfer != null) {
      ref.read(transferRepositoryProvider).cancelTransfer(state.transfer!.id);
    }
    state = const UploadState(phase: UploadPhase.cancelled);
  }
}
