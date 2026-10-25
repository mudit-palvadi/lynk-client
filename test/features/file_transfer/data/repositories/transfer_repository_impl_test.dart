import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:client/core/errors/failures.dart';
import 'package:client/features/file_transfer/data/datasources/transfer_remote_data_source.dart';
import 'package:client/features/file_transfer/data/models/file_item_model.dart';
import 'package:client/features/file_transfer/data/models/transfer_model.dart';
import 'package:client/features/file_transfer/data/repositories/transfer_repository_impl.dart';
import 'package:client/features/file_transfer/domain/entities/file_item.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';

class MockTransferRemoteDataSource implements TransferRemoteDataSource {
  bool shouldThrowDioException = false;
  int statusCode = 500;
  String errorMessage = 'Server error';

  /// When set, `getDownloadUrls` answers with this status and detail
  /// instead of the file list.
  int? downloadUrlsStatusCode;
  String downloadUrlsError = 'Transfer is not ready';

  /// When set, `cancelTransfer` answers with this status and detail.
  int? cancelStatusCode;
  String cancelError = 'Transfer not found';

  /// When set, `extendTransfer` answers with this status and detail.
  int? extendStatusCode;
  String extendError = 'Transfer not found';

  @override
  Future<TransferModel> createTransfer(List<FileItemModel> files) async {
    if (shouldThrowDioException) {
      throw DioException(
        requestOptions: RequestOptions(path: '/transfers'),
        response: Response(
          requestOptions: RequestOptions(path: '/transfers'),
          statusCode: statusCode,
          data: {'detail': errorMessage},
        ),
      );
    }
    return TransferModel(
      id: 'tx_mock_123',
      status: TransferStatus.uploading,
      totalFiles: files.length,
      totalSize: files.fold(0, (sum, f) => sum + f.size),
      files: files,
    );
  }

  @override
  Future<void> completeFileUpload({
    required String transferId,
    required String fileId,
    String? senderSecret,
  }) async {
    if (shouldThrowDioException) {
      throw DioException(requestOptions: RequestOptions(path: '/complete'));
    }
  }

  @override
  Future<TransferModel> getTransferMetadata(
    String transferId, {
    String? accessToken,
  }) async {
    if (shouldThrowDioException) {
      throw DioException(
        requestOptions: RequestOptions(path: '/transfers/$transferId'),
        response: Response(
          requestOptions: RequestOptions(path: '/transfers/$transferId'),
          statusCode: 404,
          data: {'detail': 'Transfer not found'},
        ),
      );
    }
    return const TransferModel(
      id: 'tx_mock_123',
      status: TransferStatus.ready,
      totalFiles: 1,
      totalSize: 100,
      files: [],
    );
  }

  @override
  Future<List<FileItemModel>> getDownloadUrls({
    required String transferId,
    List<String>? fileIds,
    String? accessToken,
  }) async {
    if (downloadUrlsStatusCode != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/downloads'),
        response: Response(
          requestOptions: RequestOptions(path: '/downloads'),
          statusCode: downloadUrlsStatusCode!,
          data: {'detail': downloadUrlsError},
        ),
      );
    }
    if (shouldThrowDioException) {
      throw DioException(requestOptions: RequestOptions(path: '/downloads'));
    }
    return const [
      FileItemModel(
        id: 'f1',
        name: 'a.txt',
        size: 100,
        contentType: 'text/plain',
        status: FileStatus.uploaded,
        downloadUrl: 'https://r2.mock/download',
      ),
    ];
  }

  @override
  Future<void> cancelTransfer(String transferId, {String? senderSecret}) async {
    if (cancelStatusCode != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/cancel'),
        response: Response(
          requestOptions: RequestOptions(path: '/cancel'),
          statusCode: cancelStatusCode!,
          data: {'detail': cancelError},
        ),
      );
    }
    if (shouldThrowDioException) {
      throw DioException(requestOptions: RequestOptions(path: '/cancel'));
    }
  }

  @override
  Future<void> extendTransfer(String transferId, {String? senderSecret}) async {
    if (extendStatusCode != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/extend'),
        response: Response(
          requestOptions: RequestOptions(path: '/extend'),
          statusCode: extendStatusCode!,
          data: {'detail': extendError},
        ),
      );
    }
    if (shouldThrowDioException) {
      throw DioException(requestOptions: RequestOptions(path: '/extend'));
    }
  }
}

void main() {
  group('TransferRepositoryImpl', () {
    late MockTransferRemoteDataSource mockDataSource;
    late TransferRepositoryImpl repository;

    setUp(() {
      mockDataSource = MockTransferRemoteDataSource();
      repository = TransferRepositoryImpl(remoteDataSource: mockDataSource);
    });

    test(
      'createTransfer returns Result.success on successful response',
      () async {
        const file = FileItem(
          id: '',
          name: 'test.png',
          size: 500,
          contentType: 'image/png',
          status: FileStatus.pending,
        );
        final result = await repository.createTransfer([file]);

        expect(result.isSuccess, isTrue);
        expect(result.value?.id, 'tx_mock_123');
      },
    );

    test(
      'createTransfer returns Result.failure with ServerFailure on DioException',
      () async {
        mockDataSource.shouldThrowDioException = true;
        mockDataSource.statusCode = 413;
        mockDataSource.errorMessage = 'Active storage capacity limit reached';

        const file = FileItem(
          id: '',
          name: 'test.png',
          size: 500,
          contentType: 'image/png',
          status: FileStatus.pending,
        );
        final result = await repository.createTransfer([file]);

        expect(result.isFailure, isTrue);
        expect(
          result.failure?.message,
          'Active storage capacity limit reached',
        );
      },
    );

    test(
      'getTransferMetadata returns Result.failure when transfer is not found',
      () async {
        mockDataSource.shouldThrowDioException = true;
        final result = await repository.getTransferMetadata('non_existent_id');

        expect(result.isFailure, isTrue);
        expect(result.failure?.message, 'Transfer not found');
      },
    );

    test(
      'getDownloadUrls reports the server message and the status code',
      () async {
        // The server answers 409 while the sender is still uploading. The
        // message has to be the server's own, not the raw exception text.
        mockDataSource.downloadUrlsStatusCode = 409;

        final result = await repository.getDownloadUrls(
          transferId: 'tx_mock_123',
        );

        expect(result.isFailure, isTrue);
        expect(result.failure?.message, 'Transfer is not ready');
        expect((result.failure! as ServerFailure).statusCode, 409);
        expect(result.failure?.message, isNot(contains('DioException')));
      },
    );

    test(
      'cancelTransfer reports the server message and the status code',
      () async {
        mockDataSource.cancelStatusCode = 404;
        mockDataSource.cancelError = 'Transfer not found';

        final result = await repository.cancelTransfer('tx_mock_123');
        expect(result.isFailure, isTrue);
        expect(result.failure?.message, 'Transfer not found');
        expect((result.failure! as ServerFailure).statusCode, 404);
        expect(result.failure?.message, isNot(contains('DioException')));
      },
    );

    test('extendTransfer succeeds', () async {
      final result = await repository.extendTransfer('tx_mock_123');

      expect(result.isSuccess, isTrue);
    });

    test(
      'extendTransfer reports the server message and the status code',
      () async {
        mockDataSource.extendStatusCode = 404;
        mockDataSource.extendError = 'Transfer not found';

        final result = await repository.extendTransfer('tx_mock_123');
        expect(result.isFailure, isTrue);
        expect(result.failure?.message, 'Transfer not found');
        expect((result.failure! as ServerFailure).statusCode, 404);
        expect(result.failure?.message, isNot(contains('DioException')));
      },
    );
  });
}
