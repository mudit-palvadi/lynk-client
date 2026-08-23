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
}
