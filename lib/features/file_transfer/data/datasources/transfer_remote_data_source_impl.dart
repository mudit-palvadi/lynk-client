import 'package:client/features/file_transfer/data/datasources/transfer_remote_data_source.dart';
import 'package:client/features/file_transfer/data/models/file_item_model.dart';
import 'package:client/features/file_transfer/data/models/transfer_model.dart';
import 'package:dio/dio.dart';

class TransferRemoteDataSourceImpl implements TransferRemoteDataSource {
  final Dio dio;

  TransferRemoteDataSourceImpl({required this.dio});

  @override
  Future<TransferModel> createTransfer(List<FileItemModel> files) async {
    final response = await dio.post(
      'transfers',
      data: {'files': files.map((f) => f.toJson()).toList()},
    );
    return TransferModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  }) async {
    await dio.post(
      'transfers/$transferId/files/$fileId/complete',
      options: Options(headers: _secretHeader('X-Lynk-Sender-Secret', senderSecret)),
    );
  }

  @override
  Future<TransferModel> getTransferMetadata(
    String transferId, {
    String? accessToken,
  }) async {
    final response = await dio.get(
      'transfers/$transferId',
      options: Options(headers: _secretHeader('X-Lynk-Access-Token', accessToken)),
    );
    return TransferModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<FileItemModel>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  }) async {
    final response = await dio.post(
      'transfers/$transferId/downloads',
      data: fileIds != null && fileIds.isNotEmpty ? {'file_ids': fileIds} : {},
      options: Options(headers: _secretHeader('X-Lynk-Access-Token', accessToken)),
    );
    final list = response.data['files'] as List<dynamic>;
    return list
        .map((item) => FileItemModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> cancelTransfer(String transferId, {String? senderSecret}) async {
    await dio.delete(
      'transfers/$transferId',
      options: Options(headers: _secretHeader('X-Lynk-Sender-Secret', senderSecret)),
    );
  }

  @override
  Future<void> extendTransfer(String transferId, {String? senderSecret}) async {
    await dio.post(
      'transfers/$transferId/extend',
      options: Options(headers: _secretHeader('X-Lynk-Sender-Secret', senderSecret)),
    );
  }
}

Map<String, String>? _secretHeader(String name, String? value) {
  if (value == null || value.isEmpty) return null;
  return {name: value};
}
