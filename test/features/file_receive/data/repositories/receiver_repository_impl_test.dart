import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:client/features/file_receive/data/datasources/receiver_remote_data_source.dart';
import 'package:client/features/file_receive/data/models/receiver_session_model.dart';
import 'package:client/features/file_receive/data/repositories/receiver_repository_impl.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';

class MockReceiverRemoteDataSource implements ReceiverRemoteDataSource {
  bool shouldThrowDioException = false;
  String? capturedWrappedKey;

  @override
  Future<ReceiverSessionModel> createReceiverSession() async {
    if (shouldThrowDioException) {
      throw DioException(
        requestOptions: RequestOptions(path: '/receiver-sessions'),
      );
    }
    return const ReceiverSessionModel(
      id: 'sess_123',
      status: ReceiverSessionStatus.waiting,
      expiresMultiplier: 600,
    );
  }

  @override
  Future<ReceiverSessionModel> getReceiverSession(String sessionId) async {
    if (shouldThrowDioException) {
      throw DioException(
        requestOptions: RequestOptions(path: '/receiver-sessions/$sessionId'),
      );
    }
    return const ReceiverSessionModel(
      id: 'sess_123',
      status: ReceiverSessionStatus.attached,
      transferId: 'tx_555',
      wrappedKey: 'x25519-sealed-blob-base64==',
    );
  }

  @override
  Future<void> attachTransfer({
    required String sessionId,
    required String transferId,
    String? wrappedKey,
  }) async {
    if (shouldThrowDioException) {
      throw DioException(requestOptions: RequestOptions(path: '/attach'));
    }
    capturedWrappedKey = wrappedKey;
  }

  @override
  Future<void> cancelReceiverSession(String sessionId) async {
    if (shouldThrowDioException) {
      throw DioException(requestOptions: RequestOptions(path: '/cancel'));
    }
  }
}

void main() {
  group('ReceiverRepositoryImpl', () {
    late MockReceiverRemoteDataSource mockDataSource;
    late ReceiverRepositoryImpl repository;

    setUp(() {
      mockDataSource = MockReceiverRemoteDataSource();
      repository = ReceiverRepositoryImpl(remoteDataSource: mockDataSource);
    });

    test('createReceiverSession returns Result.success', () async {
      final result = await repository.createReceiverSession();
      expect(result.isSuccess, isTrue);
      expect(result.value?.id, 'sess_123');
      expect(result.value?.status, ReceiverSessionStatus.waiting);
    });

    test(
      'getReceiverSession returns attached status with wrapped_key',
      () async {
        final result = await repository.getReceiverSession('sess_123');
        expect(result.isSuccess, isTrue);
        expect(result.value?.status, ReceiverSessionStatus.attached);
        expect(result.value?.transferId, 'tx_555');
        expect(result.value?.wrappedKey, 'x25519-sealed-blob-base64==');
      },
    );

    test('attachTransfer passes wrappedKey to data source', () async {
      final result = await repository.attachTransfer(
        sessionId: 'sess_123',
        transferId: 'tx_555',
        wrappedKey: 'sealed-blob',
      );
      expect(result.isSuccess, isTrue);
      expect(mockDataSource.capturedWrappedKey, 'sealed-blob');
    });

    test(
      'createReceiverSession returns Result.failure on DioException',
      () async {
        mockDataSource.shouldThrowDioException = true;
        final result = await repository.createReceiverSession();
        expect(result.isFailure, isTrue);
      },
    );
  });
}
