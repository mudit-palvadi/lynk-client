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

    test('a query key is ignored when the fragment already has one', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/id1#frag-key?aesKey=query-key'),
      );

      expect(target.transferId, 'id1');
      expect(target.aesKey, 'frag-key');
      expect(target.accessToken, '');
    });

    test('a key in the query string is ignored', () {
      final target = parseSendDeepLink(
        Uri.parse(
          'https://lynkshare.app/send/id2?aesKey=query-key&a=query-token',
        ),
      );

      expect(target.transferId, 'id2');
      expect(target.aesKey, '');
      expect(target.accessToken, '');
    });

    test('missing fragment and query yields empty aesKey, never throws', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/id3'),
      );

      expect(target.transferId, 'id3');
      expect(target.aesKey, '');
    });

    test('splits the access token out of the fragment and leaves the AES key', () {
      final target = parseSendDeepLink(
        Uri.parse('https://lynkshare.app/send/abc123#deadbeef&a=access-token'),
      );

      expect(target.aesKey, 'deadbeef');
      expect(target.accessToken, 'access-token');
      expect(target.transferId, 'abc123');
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

  group('normalizeCustomSchemeLink (offline lynk:// links)', () {
    test('rewrites lynk://send/{id} to the canonical path', () {
      expect(
        normalizeCustomSchemeLink(Uri.parse('lynk://send/abc#key')),
        '/send/abc#key',
      );
    });

    test('rewrites lynk://receive/{id} to the canonical path', () {
      expect(
        normalizeCustomSchemeLink(Uri.parse('lynk://receive/s1#pk=k1')),
        '/receive/s1#pk=k1',
      );
    });

    test('keeps the fragment byte-for-byte, including base64 padding', () {
      // The key is opaque ciphertext material: decoding and re-encoding it
      // would corrupt any `+`, `/` or `=` it contains.
      expect(
        normalizeCustomSchemeLink(
          Uri.parse('lynk://receive/s2#pk=AbC%2B%2F%3D'),
        ),
        '/receive/s2#pk=AbC%2B%2F%3D',
      );
    });

    test('preserves query parameters', () {
      expect(
        normalizeCustomSchemeLink(Uri.parse('lynk://send/abc?aesKey=legacy')),
        '/send/abc?aesKey=legacy',
      );
    });

    test('accepts the empty-host form lynk:///send/{id}', () {
      expect(
        normalizeCustomSchemeLink(Uri.parse('lynk:///send/abc#k')),
        '/send/abc#k',
      );
    });

    test('ignores https links, which already have a canonical path', () {
      expect(
        normalizeCustomSchemeLink(
          Uri.parse('https://lynkshare.app/send/abc#key'),
        ),
        isNull,
      );
    });

    test('ignores in-app locations', () {
      expect(normalizeCustomSchemeLink(Uri.parse('/home')), isNull);
      expect(normalizeCustomSchemeLink(Uri.parse('/send/abc')), isNull);
    });

    test('ignores unknown lynk:// hosts', () {
      expect(normalizeCustomSchemeLink(Uri.parse('lynk://settings')), isNull);
      expect(normalizeCustomSchemeLink(Uri.parse('lynk://home/x')), isNull);
    });

    test('ignores a lynk:// link with no id segment', () {
      expect(normalizeCustomSchemeLink(Uri.parse('lynk://send')), isNull);
      expect(normalizeCustomSchemeLink(Uri.parse('lynk://receive')), isNull);
    });
  });

  group('isTransferDeepLink (what survives the onboarding gate)', () {
    test('recognises send and receive paths, with or without a fragment', () {
      expect(isTransferDeepLink(Uri.parse('/send/abc#k')), isTrue);
      expect(isTransferDeepLink(Uri.parse('/receive/s#pk=k')), isTrue);
      expect(isTransferDeepLink(Uri.parse('/send/abc')), isTrue);
    });

    test('rejects ordinary app chrome', () {
      expect(isTransferDeepLink(Uri.parse('/home')), isFalse);
      expect(isTransferDeepLink(Uri.parse('/upload')), isFalse);
      expect(isTransferDeepLink(Uri.parse('/onboarding')), isFalse);
      expect(isTransferDeepLink(Uri.parse('/')), isFalse);
    });
  });

  group('canonicalDeepLinkLocation (replayable form)', () {
    test('drops scheme and host but keeps path, query and fragment', () {
      expect(
        canonicalDeepLinkLocation(
          Uri.parse('https://lynkshare.app/receive/s1?x=1#pk=k1'),
        ),
        '/receive/s1?x=1#pk=k1',
      );
    });

    test('round-trips a custom-scheme link after normalization', () {
      final normalized = Uri.parse(
        normalizeCustomSchemeLink(Uri.parse('lynk://send/abc#k1'))!,
      );

      expect(canonicalDeepLinkLocation(normalized), '/send/abc#k1');
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
