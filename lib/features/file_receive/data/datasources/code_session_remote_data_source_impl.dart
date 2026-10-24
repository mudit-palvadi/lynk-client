import 'package:client/features/file_receive/data/models/code_session_models.dart';
import 'package:dio/dio.dart';
import 'code_session_remote_data_source.dart';

class CodeSessionRemoteDataSourceImpl implements CodeSessionRemoteDataSource {
  final Dio dio;
  CodeSessionRemoteDataSourceImpl({required this.dio});

  @override
  Future<ReceiverCodeJoinModel> join({
    required String code,
    required String receiverPk,
  }) async {
    final response = await dio.post(
      'sender-sessions/join',
      data: {'code': code, 'receiver_pk': receiverPk},
    );
    return ReceiverCodeJoinModel.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  @override
  Future<ReceiverCodeKeyModel?> collectKey(String sessionId) async {
    try {
      final response = await dio.get('sender-sessions/$sessionId/key');
      return ReceiverCodeKeyModel.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      // 409 means the sender has not wrapped the key yet, which is the normal
      // state while the receiver is still waiting. Any other status is a real
      // failure and belongs to the caller.
      if (e.response?.statusCode == 409) return null;
      rethrow;
    }
  }
}
