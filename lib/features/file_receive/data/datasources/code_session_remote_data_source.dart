import 'package:client/features/file_receive/data/models/code_session_models.dart';

/// The receiver side of code pairing: publish a public key for the code, then
/// collect the wrapped transfer key once the sender attaches it.
abstract class CodeSessionRemoteDataSource {
  Future<ReceiverCodeJoinModel> join({
    required String code,
    required String receiverPk,
  });

  /// The wrapped key, or null while the sender has not attached it yet.
  /// [receiverSecret] is the value join returned for this session.
  Future<ReceiverCodeKeyModel?> collectKey(
    String sessionId, {
    required String receiverSecret,
  });
}
