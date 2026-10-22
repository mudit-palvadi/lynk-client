import 'package:client/core/services/ad_gate.dart';
import 'package:client/core/services/post_send_ad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final clock = DateTime(2026, 10, 23, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  PostSendAd build(List<int> shown) => PostSendAd(
        gate: AdGate(now: () => clock),
        showInterstitial: () async => shown.add(1),
      );

  group('PostSendAd', () {
    test('shows the interstitial and opens the window while it is closed',
        () async {
      final shown = <int>[];
      final gate = AdGate(now: () => clock);
      await build(shown).run();

      expect(shown, hasLength(1));
      expect(await gate.isFreeWindowOpen(), isTrue);
    });

    test('stays quiet while the window is already open', () async {
      final shown = <int>[];
      await AdGate(now: () => clock).openFreeWindow();

      final didShow = await build(shown).run();

      expect(shown, isEmpty);
      expect(didShow, isFalse);
    });

    test('reports that an ad was shown', () async {
      final shown = <int>[];
      expect(await build(shown).run(), isTrue);
    });

    test('the window it opens skips the next automatic ad', () async {
      final shown = <int>[];
      await build(shown).run();

      // A second send inside the window shows nothing.
      await build(shown).run();
      expect(shown, hasLength(1));
    });
  });
}
