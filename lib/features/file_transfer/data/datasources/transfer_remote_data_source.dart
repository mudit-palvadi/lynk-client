import 'package:client/features/file_transfer/data/models/file_item_model.dart';
import 'package:client/features/file_transfer/data/models/transfer_model.dart';

abstract class TransferRemoteDataSource {
  Future<TransferModel> createTransfer(List<FileItemModel> files);

  Future<void> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  });

  Future<TransferModel> getTransferMetadata(
    String transferId, {
    String? accessToken,
  });

  Future<List<FileItemModel>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  });

  Future<void> cancelTransfer(String transferId, {String? senderSecret});
}
