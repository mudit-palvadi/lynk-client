import '../../../../core/errors/result.dart';
import '../entities/receiver_session.dart';

abstract class ReceiverRepository {
  Future<Result<ReceiverSession>> createReceiverSession();

  Future<Result<ReceiverSession>> getReceiverSession(String sessionId);

  Future<Result<void>> attachTransfer({
    required String sessionId,
    required String transferId,
    String? wrappedKey,
  });

  Future<Result<void>> cancelReceiverSession(String sessionId);
}
