import 'package:client/core/errors/failures.dart';
import 'package:client/features/file_transfer/data/models/file_item_model.dart';
import 'package:dio/dio.dart';

import '../../../../core/errors/result.dart';
import '../../domain/entities/file_item.dart';
import '../../domain/entities/transfer.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../datasources/transfer_remote_data_source.dart';

class TransferRepositoryImpl implements TransferRepository {
  final TransferRemoteDataSource remoteDataSource;

  TransferRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Result<Transfer>> createTransfer(List<FileItem> files) async {
    try {
      final models = files.map((f) => FileItemModel.fromEntity(f)).toList();
      final result = await remoteDataSource.createTransfer(models);
      return Result.success(result);
    } on DioException catch (e) {
      return Result.failure(
        ServerFailure(
          e.response?.data['detail'] ?? 'Failed to create transfer',
          statusCode: e.response?.statusCode,
        ),
      );
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  }) async {
    try {
      await remoteDataSource.completeFileUpload(
        transferId: transferId,
        fileId: fileId,
        senderSecret: senderSecret,
      );
      return Result.success(null);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<Transfer>> getTransferMetadata(
    String transferId, {
    String? accessToken,
  }) async {
    try {
      final result = await remoteDataSource.getTransferMetadata(
        transferId,
        accessToken: accessToken,
      );
      return Result.success(result);
    } on DioException catch (e) {
      return Result.failure(
        ServerFailure(
          e.response?.data['detail'] ?? 'Transfer not found',
          statusCode: e.response?.statusCode,
        ),
      );
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<List<FileItem>>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  }) async {
    try {
      final result = await remoteDataSource.getDownloadUrls(
        transferId: transferId,
        fileIds: fileIds,
        accessToken: accessToken,
      );
      return Result.success(result);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> cancelTransfer(
    String transferId, {
    String? senderSecret,
  }) async {
    try {
      await remoteDataSource.cancelTransfer(
        transferId,
        senderSecret: senderSecret,
      );
      return Result.success(null);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }
}
