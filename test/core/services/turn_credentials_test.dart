import 'package:client/core/services/flutter_webrtc_p2p_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration/support/fake_http_adapter.dart';

void main() {
  group('fetchTurnCredentials (#47)', () {
    setUp(() {
      // The function reads its base url from dotenv, which throws until a
      // source is loaded.
      dotenv.loadFromString(
        envString: 'API_BASE_URL=https://api.lynkshare.app/api/v1/',
      );
    });

    test('presents the transfer access token', () async {
      final adapter = FakeHttpAdapter(
        (_) => jsonResponse(200, {
          'enabled': true,
          'urls': ['turn:turn.example:3478'],
          'username': 'user',
          'credential': 'secret',
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      final turn = await fetchTurnCredentials(
        'transfer-1',
        accessToken: 'transfer-token',
        dio: dio,
      );

      expect(turn?.username, 'user');
      expect(
        adapter.requests.single.path,
        endsWith('transfers/transfer-1/turn-credentials'),
      );
      final headers = adapter.requests.single.headers;
      final tokenHeader = headers.keys.firstWhere(
        (key) => key.toLowerCase() == 'x-lynk-access-token',
        orElse: () => '',
      );
      expect(headers[tokenHeader], 'transfer-token');
    });

    test('sends no token header when the caller has none', () async {
      final adapter = FakeHttpAdapter(
        (_) => jsonResponse(200, {'enabled': false}),
      );
      final dio = Dio()..httpClientAdapter = adapter;

      await fetchTurnCredentials('transfer-1', dio: dio);

      final headers = adapter.requests.single.headers;
      expect(
        headers.keys.where(
          (key) => key.toLowerCase() == 'x-lynk-access-token',
        ),
        isEmpty,
      );
    });
  });
}
