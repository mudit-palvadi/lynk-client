import 'package:client/core/routing/app_router.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class MockOnboardingNotifier extends OnboardingNotifier {
  @override
  bool build() => true;
}

void main() {
  group('parseSendDeepLink (#fragment AES key extraction)', () {
    test('extracts transferId and aesKey from the canonical deep link', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/abc123#my-secret-key'),
      );

      expect(target.transferId, 'abc123');
      expect(target.aesKey, 'my-secret-key');
    });

    test('fragment takes priority over an aesKey query parameter', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/id1#frag-key?aesKey=query-key'),
      );

      expect(target.transferId, 'id1');
      expect(target.aesKey, 'frag-key');
    });

    test('falls back to aesKey query parameter when fragment is absent', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/id2?aesKey=query-key'),
      );

      expect(target.transferId, 'id2');
      expect(target.aesKey, 'query-key');
    });

    test('missing fragment and query yields empty aesKey, never throws', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/id3'),
      );

      expect(target.transferId, 'id3');
      expect(target.aesKey, '');
    });

    test('AES key in fragment never leaks into query parameters', () {
      final uri = Uri.parse('https://lynkshare.app/send/id4#client-only-key');

      // The #fragment must not appear as a query param — it stays client-side
      // and is never sent to any server (Memory.md Rule 4).
      expect(uri.queryParameters.containsKey('aesKey'), isFalse);
      expect(uri.toString().contains(RegExp(r'[?#]key|aesKey=')), isFalse);

      final target = parseSendDeepLink(uri);
      expect(target.aesKey, 'client-only-key');
    });
  });

  group('parseReceiveDeepLink (#pk fragment and session id extraction)', () {
    test('extracts sessionId and receiverPk from the canonical deep link', () {
      final target = parseReceiveDeepLink(
        Uri.parse('https://lynkshare.app/receive/sess-1#pk=AbC-_x9='),
      );

      expect(target.sessionId, 'sess-1');
      expect(target.receiverPk, 'AbC-_x9=');
    });

    test('missing fragment yields empty receiverPk, never throws', () {
      final target = parseReceiveDeepLink(
        Uri.parse('https://lynkshare.app/receive/sess-2'),
      );

      expect(target.sessionId, 'sess-2');
      expect(target.receiverPk, '');
    });

    test('fragment without pk prefix yields empty receiverPk', () {
      final target = parseReceiveDeepLink(
        Uri.parse('https://lynkshare.app/receive/sess-3#other=value'),
      );

      expect(target.sessionId, 'sess-3');
      expect(target.receiverPk, '');
    });

    test('custom scheme lynk://receive/{id} is parsed the same way', () {
      final target = parseReceiveDeepLink(
        Uri.parse('lynk://receive/sess-4#pk=key4'),
      );

      expect(target.sessionId, 'sess-4');
      expect(target.receiverPk, 'key4');
    });

    test(
      'receiver public key in fragment never leaks into query parameters',
      () {
        final uri = Uri.parse(
          'https://lynkshare.app/receive/sess-5#pk=client-only',
        );

        // The #fragment must not appear as a query param — it stays client-side
        // and is never sent to any server (Memory.md Rule 4).
        expect(uri.queryParameters.containsKey('pk'), isFalse);

        final target = parseReceiveDeepLink(uri);
        expect(target.receiverPk, 'client-only');
      },
    );
  });

  group('receiveUploadLocation (/receive pairing target)', () {
    test('builds the upload location with session id and encoded pk', () {
      final location = receiveUploadLocation(
        const ReceiveDeepLinkTarget(sessionId: 'sess-1', receiverPk: 'AbC+/='),
      );

      expect(location, '/upload?attachToSessionId=sess-1&pk=AbC%2B%2F%3D');
    });

    test('omits the pk parameter when the fragment had none', () {
      final location = receiveUploadLocation(
        const ReceiveDeepLinkTarget(sessionId: 'sess-2', receiverPk: ''),
      );

      expect(location, '/upload?attachToSessionId=sess-2');
    });
  });

  group('deep link route matching (/send/:transferId)', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith(() => MockOnboardingNotifier()),
        ],
      );
      router = container.read(appRouterProvider);
    });

    tearDown(() => container.dispose());

    test('canonical deep link matches the /send/:transferId route', () {
      final matchList = router.configuration.findMatch(
        Uri.parse('https://lynkshare.app/send/abc123#my-secret-key'),
      );

      expect(matchList.last.matchedLocation, '/send/abc123');
      expect(matchList.last.route.path, '/send/:transferId');
    });

    test('transferId segment is matched by the /send/:transferId pattern', () {
      final matchList = router.configuration.findMatch(
        Uri.parse('/send/xyz-789#k'),
      );

      expect(matchList.last.matchedLocation, '/send/xyz-789');
      expect(matchList.uri.fragment, 'k');
    });

    test('unrelated paths do not match the deep-link route', () {
      final matchList = router.configuration.findMatch(Uri.parse('/home'));

      expect(matchList.last.matchedLocation, '/home');
    });
  });

  group('deep link route matching (/receive/:sessionId)', () {
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith(() => MockOnboardingNotifier()),
        ],
      );
      router = container.read(appRouterProvider);
    });

    tearDown(() => container.dispose());

    test('canonical deep link matches the /receive/:sessionId route', () {
      final matchList = router.configuration.findMatch(
        Uri.parse('https://lynkshare.app/receive/sess-1#pk=AbC-_x9='),
      );

      expect(matchList.last.matchedLocation, '/receive/sess-1');
      expect(matchList.last.route.path, '/receive/:sessionId');
      expect(matchList.uri.fragment, 'pk=AbC-_x9=');
    });

    test('sessionId segment is matched and the fragment survives matching', () {
      final matchList = router.configuration.findMatch(
        Uri.parse('/receive/xyz-789#pk=k'),
      );

      expect(matchList.last.matchedLocation, '/receive/xyz-789');
      expect(matchList.uri.fragment, 'pk=k');
    });

    test('unrelated paths do not match the receive deep-link route', () {
      final matchList = router.configuration.findMatch(Uri.parse('/home'));

      expect(matchList.last.matchedLocation, '/home');
    });
  });
}
