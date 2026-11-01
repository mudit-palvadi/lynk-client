import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../services/config_service.dart';

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

  static String _getBaseUrl() => ConfigService.apiBase;

  Dio get dio => _dio;
}
