import 'package:client/features/file_receive/data/models/code_session_models.dart';

/// The receiver side of code pairing: publish a public key for the code, then
/// collect the wrapped transfer key once the sender attaches it.
abstract class CodeSessionRemoteDataSource {
  Future<ReceiverCodeJoinModel> join({
    required String code,
    required String receiverPk,
  });

  Future<ReceiverCodeKeyModel> collectKey(String sessionId);
}
