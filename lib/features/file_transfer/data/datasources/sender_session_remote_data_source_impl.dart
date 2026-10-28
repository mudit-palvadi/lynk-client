import 'package:client/features/file_transfer/data/datasources/sender_session_remote_data_source.dart';
import 'package:client/features/file_transfer/data/models/sender_session_model.dart';
import 'package:dio/dio.dart';

class SenderSessionRemoteDataSourceImpl
    implements SenderSessionRemoteDataSource {
  final Dio dio;
  SenderSessionRemoteDataSourceImpl({required this.dio});

  @override
  Future<SenderSessionModel> createSession() async {
    final response = await dio.post('sender-sessions');
    return SenderSessionModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<SenderSessionModel> getSession(String sessionId) async {
    final response = await dio.get('sender-sessions/$sessionId');
    return SenderSessionModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> attachKey({
    required String sessionId,
    required String transferId,
    required String wrappedKey,
    required String mode,
    required String senderSecret,
    CancelToken? cancelToken,
  }) async {
    await dio.post(
      'sender-sessions/$sessionId/attach',
      data: {
        'transfer_id': transferId,
        'wrapped_key': wrappedKey,
        'mode': mode,
      },
      cancelToken: cancelToken,
      options: Options(headers: {'X-Lynk-Sender-Secret': senderSecret}),
    );
  }

  @override
  Future<void> cancelSession({
    required String sessionId,
    required String senderSecret,
  }) async {
    try {
      await dio.delete(
        'sender-sessions/$sessionId',
        options: Options(headers: {'X-Lynk-Sender-Secret': senderSecret}),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return;
      rethrow;
    }
  }
}
