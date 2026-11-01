import 'package:client/core/services/config_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(dotenv.clean);

  group('ConfigService.apiBase', () {
    test('fails fast when no environment has been loaded', () {
      expect(() => ConfigService.apiBase, throwsStateError);
    });

    test('fails fast when API_BASE_URL is blank', () {
      dotenv.loadFromString(envString: 'API_BASE_URL=\n');

      expect(() => ConfigService.apiBase, throwsStateError);
    });

    test('normalizes a configured backend', () {
      dotenv.loadFromString(
        envString: 'API_BASE_URL=http://localhost:8000/api/v1',
      );

      expect(ConfigService.apiBase, 'http://localhost:8000/api/v1/');
    });
  });

  group('ConfigService.resolveApiBase', () {
    test('rejects null, empty and whitespace-only values', () {
      for (final value in [null, '', '   ']) {
        expect(
          () => ConfigService.resolveApiBase(value),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('API_BASE_URL'),
            ),
          ),
        );
      }
    });

    test('trims whitespace and keeps exactly one trailing slash', () {
      expect(
        ConfigService.resolveApiBase('  https://api.test.local/api/v1  '),
        'https://api.test.local/api/v1/',
      );
      expect(
        ConfigService.resolveApiBase('https://api.test.local/api/v1/'),
        'https://api.test.local/api/v1/',
      );
    });
  });

  group('ConfigService.signalingUri', () {
    test('uses ws for a plain-http backend and keeps the port', () {
      dotenv.loadFromString(
        envString: 'API_BASE_URL=http://10.0.2.2:8000/api/v1/',
      );

      final uri = ConfigService.signalingUri('session-1');

      expect(uri.scheme, 'ws');
      expect(uri.host, '10.0.2.2');
      expect(uri.port, 8000);
      expect(uri.path, '/ws/signaling/session-1');
    });

    test('uses wss for an https backend', () {
      dotenv.loadFromString(
        envString: 'API_BASE_URL=https://api.test.local/api/v1/',
      );

      final uri = ConfigService.signalingUri('session-2');

      expect(uri.scheme, 'wss');
      expect(uri.host, 'api.test.local');
      expect(uri.port, 443);
      expect(uri.path, '/ws/signaling/session-2');
    });
  });
}
