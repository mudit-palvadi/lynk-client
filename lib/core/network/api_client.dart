import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  final Dio _dio;

  ApiClient({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _getBaseUrl();
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.startsWith('/')) {
            options.path = options.path.substring(1);
          }
          return handler.next(options);
        },
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('DioRequest: ${options.method} ${options.uri.path}');
            return handler.next(options);
          },
        ),
      );
    }
  }

  static String _getBaseUrl() {
    String url =
        dotenv.env['API_BASE_URL'] ?? 'http://140.245.220.117:8000/api/v1/';
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    return url;
  }

  Dio get dio => _dio;
}
