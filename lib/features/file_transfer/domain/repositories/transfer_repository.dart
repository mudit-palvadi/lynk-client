import '../../../../core/errors/result.dart';
import '../entities/file_item.dart';
import '../entities/transfer.dart';

abstract class TransferRepository {
  Future<Result<Transfer>> createTransfer(List<FileItem> files);

  Future<Result<void>> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  });

  Future<Result<Transfer>> getTransferMetadata(
    String transferId, {
    String? accessToken,
  });

  Future<Result<List<FileItem>>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  });

  Future<Result<void>> cancelTransfer(
    String transferId, {
    String? senderSecret,
  });

  /// Moves the transfer's server-side expiry to the extended lifetime.
  Future<Result<void>> extendTransfer(
    String transferId, {
    String? senderSecret,
  });
}
