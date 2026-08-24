import 'package:client/features/file_receive/data/models/receiver_session_model.dart';
import 'package:dio/dio.dart';
import 'receiver_remote_data_source.dart';

class ReceiverRemoteDataSourceImpl implements ReceiverRemoteDataSource {
  final Dio dio;
  ReceiverRemoteDataSourceImpl({required this.dio});

  @override
  Future<ReceiverSessionModel> createReceiverSession() async {
    final response = await dio.post('receiver-sessions');
    return ReceiverSessionModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ReceiverSessionModel> getReceiverSession(String sessionId) async {
    final response = await dio.get('receiver-sessions/$sessionId');
    return ReceiverSessionModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> attachTransfer({
    required String sessionId,
    required String transferId,
    String? wrappedKey,
  }) async {
    await dio.post(
      'receiver-sessions/$sessionId/attach-transfer',
      data: {
        'transfer_id': transferId,
        if (wrappedKey != null && wrappedKey.isNotEmpty)
          'wrapped_key': wrappedKey,
      },
    );
  }

  @override
  Future<void> cancelReceiverSession(String sessionId) async {
    await dio.delete('receiver-sessions/$sessionId');
  }
}
