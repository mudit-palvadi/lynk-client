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

  /// Reads the server's error message out of a response body.
  ///
  /// The API answers with `{"detail": "..."}`, but a schema-validation
  /// failure answers with a list of error objects instead. Both have to end
  /// up as a string: the message is shown to the user, and a list would
  /// crash the failure rather than explain it.
  static String _errorMessage(dynamic body, String fallback) {
    final detail = body is Map ? body['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        return first['msg'] as String;
      }
    }
    return fallback;
  }

  @override
  Future<Result<Transfer>> createTransfer(List<FileItem> files) async {
    try {
      final models = files.map((f) => FileItemModel.fromEntity(f)).toList();
      final result = await remoteDataSource.createTransfer(models);
      return Result.success(result);
    } on DioException catch (e) {
      return Result.failure(
        ServerFailure(
          _errorMessage(e.response?.data, 'Failed to create transfer'),
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
          _errorMessage(e.response?.data, 'Transfer not found'),
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
    } on DioException catch (e) {
      return Result.failure(
        ServerFailure(
          _errorMessage(e.response?.data, 'Failed fetching URLs'),
          statusCode: e.response?.statusCode,
        ),
      );
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
    } on DioException catch (e) {
      return Result.failure(
        ServerFailure(
          _errorMessage(e.response?.data, 'Failed cancelling transfer'),
          statusCode: e.response?.statusCode,
        ),
      );
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }
}
