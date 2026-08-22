import 'package:client/core/errors/failures.dart';
import 'package:client/core/errors/result.dart';
import 'package:client/features/file_receive/data/datasources/receiver_remote_data_source.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';
import 'package:client/features/file_receive/domain/repositories/receiver_repository.dart';

class ReceiverRepositoryImpl implements ReceiverRepository {
  final ReceiverRemoteDataSource remoteDataSource;
  ReceiverRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Result<ReceiverSession>> createReceiverSession() async {
    try {
      final session = await remoteDataSource.createReceiverSession();
      return Result.success(session);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<ReceiverSession>> getReceiverSession(String sessionId) async {
    try {
      final session = await remoteDataSource.getReceiverSession(sessionId);
      return Result.success(session);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> attachTransfer({
    required String sessionId,
    required String transferId,
    String? wrappedKey,
  }) async {
    try {
      await remoteDataSource.attachTransfer(
        sessionId: sessionId,
        transferId: transferId,
        wrappedKey: wrappedKey,
      );
      return Result.success(null);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> cancelReceiverSession(String sessionId) async {
    try {
      await remoteDataSource.cancelReceiverSession(sessionId);
      return Result.success(null);
    } catch (e) {
      return Result.failure(ServerFailure(e.toString()));
    }
  }
}
