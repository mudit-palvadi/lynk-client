import 'package:client/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(dotenv.clean);

  test('refuses to build without API_BASE_URL', () {
    expect(() => ApiClient(), throwsStateError);
  });

  test('uses the configured backend and normalizes the slash', () {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=http://localhost:8000/api/v1',
    );

    final client = ApiClient();

    expect(client.dio.options.baseUrl, 'http://localhost:8000/api/v1/');
  });

  test('keeps an injected Dio wired to its own adapter', () {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
    final dio = Dio();

    final client = ApiClient(dio: dio);

    expect(client.dio, same(dio));
    expect(client.dio.options.baseUrl, 'https://api.test.local/api/v1/');
  });
}
