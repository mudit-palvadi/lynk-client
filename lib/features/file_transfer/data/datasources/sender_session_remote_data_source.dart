import 'package:client/features/file_transfer/data/models/sender_session_model.dart';
import 'package:dio/dio.dart';

/// The sender side of code pairing: mint a session, watch it for a receiver,
/// and hand over the wrapped key once one joins.
///
/// The receiver's half (joining with the code, collecting the key) lives with
/// the receive feature.
abstract class SenderSessionRemoteDataSource {
  Future<SenderSessionModel> createSession();

  Future<SenderSessionModel> getSession(String sessionId);

  Future<void> attachKey({
    required String sessionId,
    required String transferId,
    required String wrappedKey,
    required String mode,
    required String senderSecret,
    CancelToken? cancelToken,
  });

  Future<void> cancelSession({
    required String sessionId,
    required String senderSecret,
  });
}
