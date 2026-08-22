import '../models/receiver_session_model.dart';

abstract class ReceiverRemoteDataSource {
  Future<ReceiverSessionModel> createReceiverSession();

  Future<ReceiverSessionModel> getReceiverSession(String sessionId);

  Future<void> attachTransfer({
    required String sessionId,
    required String transferId,
    String? wrappedKey,
  });

  Future<void> cancelReceiverSession(String sessionId);
}
