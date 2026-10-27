import 'package:client/features/file_receive/data/datasources/code_session_remote_data_source_impl.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collect sends the secret join returned', () async {
    final dio = Dio();
    Map<String, dynamic>? headers;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          headers = options.headers;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'transfer_id': 't',
                'wrapped_key': 'w',
                'mode': 'cloud',
                'expires_in': 1,
              },
            ),
          );
        },
      ),
    );

    final source = CodeSessionRemoteDataSourceImpl(dio: dio);
    final key = await source.collectKey('s1', receiverSecret: 'receiver-secret');

    expect(key?.transferId, 't');
    expect(headers?['X-Lynk-Receiver-Secret'], 'receiver-secret');
  });

  test('join keeps the receiver secret from the response', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'session_id': 's1',
                'status': 'joined',
                'expires_in': 600,
                'receiver_secret': 'receiver-secret',
              },
            ),
          );
        },
      ),
    );

    final source = CodeSessionRemoteDataSourceImpl(dio: dio);
    final joined = await source.join(code: '123456', receiverPk: 'pk');

    expect(joined.receiverSecret, 'receiver-secret');
  });
}
