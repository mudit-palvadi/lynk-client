import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/core/services/config_service.dart';
import 'package:client/core/services/upload_service.dart';
import 'package:client/core/providers/receiver_providers.dart';
import 'package:client/core/services/key_wrap_service.dart';
import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:client/core/utils/entropy_generator.dart';
import 'package:client/core/utils/file_name_sanitizer.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/usecases/encrypt_file_use_case.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/services/file_picker_service.dart';
import '../../../recent_transfers/data/models/recent_transfer_record_model.dart';
import '../../../recent_transfers/domain/entities/recent_transfer_record.dart';
import '../../../recent_transfers/presentation/providers/recent_transfers_notifier.dart';
import 'upload_state.dart';

part 'upload_notifier.g.dart';

@riverpod
UploadService uploadService(Ref ref) => UploadService();

/// Creates the sender-side WebRTC session. Injectable so tests can supply a
/// fake without touching the native plugin.
typedef P2PSenderSessionFactory =
    Future<P2PSenderSession> Function({
      required Uri signalingUrl,
      required String sessionId,
      String? accessToken,
      required void Function() onFallbackToCloud,
    });

@riverpod
P2PSenderSessionFactory p2pSessionFactory(Ref ref) =>
    P2PFileSession.connectAsSender;

/// How long the sender waits (QR visible) for a receiver before silently
/// switching to the R2 cloud pipeline.
@riverpod
Duration p2pAutoFallbackDuration(Ref ref) => const Duration(seconds: 60);

@Riverpod(keepAlive: true)
class UploadNotifier extends _$UploadNotifier {
  CancelToken? _cancelToken;

  /// The last batch a picker handed over that the rules refused, so the
  /// rewarded-ad unlock can re-run it instead of asking for the files again.
  List<PlatformFile> _rejectedBatch = const [];

  @override
  UploadState build() => const UploadState();

  bool get hasRejectedFiles => _rejectedBatch.isNotEmpty;

  Future<void> pickFiles() async {
    final picker = ref.read(filePickerServiceProvider);
    final result = await picker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    _addPicked(result.files);
  }

  Future<void> pickMedia() async {
    final picker = ref.read(filePickerServiceProvider);
    final result = await picker.pickMedia(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    _addPicked(result.files);
  }

  /// Adds a freshly picked batch to whatever is already staged.
  ///
  /// Both rules are checked against the *combined* selection: the byte budget
  /// first (cloud 15/30 MB, P2P 20/50 MB), then the ten-file cap. A batch that
  /// breaks either rule is refused whole, so adding a fifth file can never
  /// throw away the four already on the list.
  void _addPicked(List<PlatformFile> picked) {
    final combined = <PlatformFile>[...state.selectedFiles, ...picked];

    final sizeError = _sizeError(combined);
    final outOfCount = combined.length > UploadState.maxFiles;
    final String? error =
        sizeError ??
        (outOfCount
            ? 'Maximum ${UploadState.maxFiles} files per transfer'
                  ' (${state.selectedFiles.length} already selected)'
            : null);

    if (error != null) {
      _rejectedBatch = picked;
      _rejectSelection(error);
      return;
    }

    _rejectedBatch = const [];
    state = state.copyWith(
      selectedFiles: combined,
      phase: UploadPhase.selecting,
    );
  }

  /// Re-runs the batch that was just refused, after the user unlocked the
  /// larger tier. Returns false when nothing is remembered.
  bool retryRejectedSelection() {
    final batch = _rejectedBatch;
    if (batch.isEmpty) return false;
    _rejectedBatch = const [];
    _addPicked(batch);
    return true;
  }

  /// A refusal must not wipe the list: with files already staged the message
  /// is a transient notice and the selection view stays, and only an empty
  /// selection falls back to the failed view, which is what raises the
  /// ad-unlock dialog.
  void _rejectSelection(String message) {
    if (state.selectedFiles.isEmpty) {
      state = state.copyWith(phase: UploadPhase.failed, errorMessage: message);
      return;
    }
    state = state.copyWith(
      phase: UploadPhase.selecting,
      notice: message,
      noticeSeq: state.noticeSeq + 1,
    );
  }

  void unlockExtendedSizeLimit() {
    state = state.copyWith(isSizeLimitUnlocked: true);
  }

  /// Enforces the per-mode size tiers against the current unlocked state:
  /// - Cloud/R2: free 15 MB -> unlocked 30 MB
  /// - P2P: free 20 MB -> unlocked 50 MB
  ///
  /// Returns the reason the selection is refused, or null when it fits.
  String? _sizeError(List<PlatformFile> files) {
    final totalSize = files.fold(0, (sum, f) => sum + f.size);
    final maxLimit = state.maxTotalSize;
    final maxMb = state.maxTotalSizeMb;
    final unlockedMb = state.maxTotalSizeUnlockedMb;
    final freeMb = state.maxTotalSizeFreeMb;

    if (totalSize > maxLimit) {
      return state.isSizeLimitUnlocked
          ? 'Total transfer limit is $maxMb MB'
          : 'Free limit is $freeMb MB. Watch an ad to unlock up to $unlockedMb MB!';
    }

    for (var f in files) {
      if (f.size > maxLimit) {
        return state.isSizeLimitUnlocked
            ? 'File "${f.name}" exceeds $maxMb MB limit'
            : 'File "${f.name}" exceeds the $freeMb MB free limit. Watch an ad to unlock up to $unlockedMb MB!';
      }
    }

    return null;
  }

  void setTransferMode(TransferMode mode) {
    state = state.copyWith(transferMode: mode);
  }

  void setFilesForTesting(List<PlatformFile> files) {
    // Preserve mode + unlock state so staged flows see the same config the
    // user picked (mirrors pickMedia/pickFiles behavior).
    state = state.copyWith(selectedFiles: files, phase: UploadPhase.selecting);
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

    // Snapshot the selection before the first await. `reset()` clears the
    // selected files, and a cancel during the upload would otherwise record a
    // transfer with no file names at all, which the history list cannot show.
    final selectedFiles = List<PlatformFile>.from(state.selectedFiles);
    final totalSize = state.totalSize;

    state = state.copyWith(
      phase: UploadPhase.uploading,
      currentFileIndex: 0,
      overallProgress: 0.0,
    );
    _cancelToken = CancelToken();

    final repo = ref.read(transferRepositoryProvider);
    final uploadService = ref.read(uploadServiceProvider);
    final encryptUseCase = ref.read(encryptFileUseCaseProvider);

    final aesKey = await EntropyGenerator.generateKey();
    state = state.copyWith(aesKey: aesKey);

    final fileItems = state.selectedFiles.map((f) {
      final encSize = ((f.size ~/ 16) + 1) * 16 + 16;
      return FileItem(
        id: '',
        // The name is sent to every receiver, who writes it to disk, so it
        // is reduced to a single safe path segment on the way out.
        name: FileNameSanitizer.safeFileName(f.name),
        size: encSize,
        contentType: 'application/octet-stream',
        status: FileStatus.pending,
      );
    }).toList();

    final createResult = await repo.createTransfer(fileItems);

    // Await the outcome directly: fold() discards async closures, which
    // previously let startUpload return before the transfer finished.
    if (createResult.isSuccess) {
      final transfer = createResult.value!;
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

      // P2P mode: show the QR first, wait patiently for a receiver, then
      // stream. Falls through to the R2 pipeline when nobody connects
      // within the window, on ICE failure after handshake, or on error.
      var useP2P = state.transferMode == TransferMode.p2p;

      // Flow B (reverse pairing): deliver the wrapped AES key to the paired
      // receiver BEFORE streaming so it can join the room already able to
      // decrypt. On attach failure, skip P2P and let R2 retry after upload.
      if (useP2P && attachToSessionId != null && receiverPk != null) {
        final attached = await _attachWrappedKey(
          sessionId: attachToSessionId,
          transferId: transfer.id,
          aesKey: aesKey,
          receiverPk: receiverPk,
        );
        if (!attached) useP2P = false;
      }

      if (useP2P) {
        final p2pCompleted = await runP2PSession(
          sessionId: transfer.id,
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
              final currentOverall = (cumulativeBytes + sent) / state.totalSize;
              state = state.copyWith(
                currentFileProgress: fileProgress,
                overallProgress: currentOverall.clamp(0.0, 1.0),
              );
            },
          );

          if (encryptedFile != null && await encryptedFile.exists()) {
            await encryptedFile.delete();
          }

          await repo.completeFileUpload(
            transferId: transfer.id,
            fileId: item.id,
            senderSecret: transfer.senderSecret,
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

        String? wrappedKey;
        if (receiverPk != null && receiverPk.isNotEmpty) {
          try {
            wrappedKey = await KeyWrapService().wrapKey(
              aesKey: aesKey,
              accessToken: transfer.accessToken,
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

      try {
        ref
            .read(recentTransfersProvider.notifier)
            .addRecord(
              RecentTransferRecordModel(
                id: transfer.id,
                type: RecentTransferType.sent,
                fileNames: selectedFiles.map((f) => f.name).toList(),
                totalSize: totalSize,
                timestamp: DateTime.now(),
                status: 'completed',
                filePaths: selectedFiles
                    .where((f) => f.path != null)
                    .map((f) => f.path!)
                    .toList(),
              ),
            );
      } catch (_) {
        // History is best-effort; never fail a finished transfer over it.
      }
    } else {
      state = state.copyWith(
        phase: UploadPhase.failed,
        errorMessage: createResult.failure!.message,
      );
    }
  }

  void reset() {
    _cancelToken?.cancel();
    _activeSession?.cancelWait();
    _rejectedBatch = const [];
    state = const UploadState();
  }

  /// Flow B: wraps [aesKey] to the receiver's ephemeral public key and
  /// attaches it to the receiver session. Returns false when either step
  /// fails so callers can degrade gracefully.
  Future<bool> _attachWrappedKey({
    required String sessionId,
    required String transferId,
    required String aesKey,
    required String receiverPk,
  }) async {
    try {
      final wrappedKey = await KeyWrapService().wrapKey(
        aesKey: aesKey,
        accessToken: state.transfer?.accessToken,
        receiverPublicKeyB64: receiverPk,
        sessionId: sessionId,
      );
      await ref
          .read(receiverRepositoryProvider)
          .attachTransfer(
            sessionId: sessionId,
            transferId: transferId,
            wrappedKey: wrappedKey,
          );
      return true;
    } catch (e) {
      debugPrint('_attachWrappedKey failed: $e');
      return false;
    }
  }

  /// User tapped "Send via Cloud instead" while waiting for a receiver.
  /// Breaks the P2P wait so the caller falls through to the R2 pipeline.
  void forceCloudFallback() => _activeSession?.cancelWait();

  P2PSenderSession? _activeSession;

  void _setStage(P2PSendStage stage) => state = state.copyWith(p2pStage: stage);

  /// Runs the staged direct-WebRTC transfer:
  ///
  /// preparing (encrypt) -> waitingForReceiver (QR visible, patient) ->
  /// transferring (real streamed %) -> completed
  ///
  /// Returns `true` when every file reached the receiver over the
  /// DataChannel. Returns `false` when the wait window expires with no
  /// receiver, the user forces cloud fallback, or anything fails -- in every
  /// such case the caller continues into the R2 pipeline.
  @visibleForTesting
  Future<bool> runP2PSession({
    required String sessionId,
    required String aesKey,
  }) async {
    if (kIsWeb) return false;

    // Snapshot the selection before the first await: the wait for a receiver
    // can last a minute, and a cancel in that window would otherwise record a
    // transfer with no file names.
    final selectedFiles = List<PlatformFile>.from(state.selectedFiles);
    final totalSize = state.totalSize;

    final factory = ref.read(p2pSessionFactoryProvider);
    final window = ref.read(p2pAutoFallbackDurationProvider);
    P2PSenderSession? session;
    final tempEncrypted = <File>[];
    var enteredTransfer = false;
    try {
      _setStage(P2PSendStage.preparing);

      // Encrypt up-front so channel-open time is spent sending, not hashing.
      var totalEncrypted = 0;
      final encryptUseCase = ref.read(encryptFileUseCaseProvider);
      for (final pFile in selectedFiles) {
        if (pFile.path == null) return false; // bytes-only pickers: use R2
        final encrypted = await encryptUseCase.execute(
          inputFile: File(pFile.path!),
          aesKey32Bytes: aesKey,
        );
        totalEncrypted += encrypted.lengthSync();
        tempEncrypted.add(encrypted);
      }

      session = await factory(
        signalingUrl: ConfigService.signalingUri(sessionId),
        sessionId: sessionId,
        accessToken: state.transfer?.accessToken,
        onFallbackToCloud: () {},
      );
      _activeSession = session;
      _setStage(P2PSendStage.waitingForReceiver);

      await session.waitUntilOpen(timeout: window);
      _setStage(P2PSendStage.transferring);
      enteredTransfer = true;

      await session.sendFiles(
        tempEncrypted,
        shouldAbort: () => _cancelToken?.isCancelled ?? false,
        onProgress: (sent) {
          final pct = totalEncrypted == 0
              ? 0.0
              : (sent / totalEncrypted).clamp(0.0, 1.0);
          state = state.copyWith(overallProgress: pct);
        },
      );

      _setStage(P2PSendStage.none);
      state = state.copyWith(
        phase: UploadPhase.completed,
        overallProgress: 1.0,
      );
      ref
          .read(recentTransfersProvider.notifier)
          .addRecord(
            RecentTransferRecordModel(
              id: sessionId,
              type: RecentTransferType.sent,
              fileNames: selectedFiles.map((f) => f.name).toList(),
              totalSize: totalSize,
              timestamp: DateTime.now(),
              status: 'completed (p2p)',
              filePaths: selectedFiles
                  .where((f) => f.path != null)
                  .map((f) => f.path!)
                  .toList(),
            ),
          );
      return true;
    } catch (e) {
      debugPrint('runP2PSession failed: $e');
      _setStage(P2PSendStage.none);
      if (enteredTransfer) {
        state = state.copyWith(phase: UploadPhase.failed);
      }
      return false;
    } finally {
      _activeSession = null;
      await session?.dispose();
      for (final f in tempEncrypted) {
        if (await f.exists()) await f.delete();
      }
    }
  }

  void cancelUpload() {
    _cancelToken?.cancel();
    forceCloudFallback();
    if (state.transfer != null) {
      ref
          .read(transferRepositoryProvider)
          .cancelTransfer(
            state.transfer!.id,
            senderSecret: state.transfer!.senderSecret,
          );
    }
    state = const UploadState(phase: UploadPhase.cancelled);
  }
}
