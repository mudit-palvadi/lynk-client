import 'package:client/core/services/ice_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildIceServers (STUN -> TURN ladder)', () {
    test('returns STUN-only when TURN is disabled or creds missing', () {
      expect(buildIceServers(turnEnabled: false).length, 3);
      expect(
        buildIceServers(
          turnEnabled: true,
          urls: const [],
          username: 'u',
          credential: 'c',
        ).length,
        3,
      );
      final noCred = buildIceServers(
        turnEnabled: true,
        urls: const ['turn:x:3478'],
        username: '',
        credential: '',
      );
      expect(noCred.length, 3);
      expect(
        noCred.every((s) => !s['urls'].toString().contains('turn:')),
        isTrue,
      );
    });

    test('appends TURN (and TURN over TCP) after the STUN servers', () {
      final servers = buildIceServers(
        turnEnabled: true,
        urls: const ['turn:turn.lynkshare.app:3478'],
        username: '1700:sess',
        credential: 'hmac-b64',
      );

      expect(servers.length, 4);
      final turn = servers.last;
      expect(turn['username'], '1700:sess');
      expect(turn['credential'], 'hmac-b64');
      expect(
        (turn['urls'] as List).contains('turn:turn.lynkshare.app:3478'),
        isTrue,
      );
      expect(
        (turn['urls'] as List).contains(
          'turn:turn.lynkshare.app:3478?transport=tcp',
        ),
        isTrue,
      );
    });

    test('multiple TURN urls are all included in one entry', () {
      final servers = buildIceServers(
        turnEnabled: true,
        urls: const ['turn:a:3478', 'turns:b:5349'],
        username: 'u',
        credential: 'c',
      );
      expect((servers.last['urls'] as List).length, 4); // 2 udp + 2 tcp
    });
  });
}
