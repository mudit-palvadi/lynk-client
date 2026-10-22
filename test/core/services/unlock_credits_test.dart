import 'package:client/core/services/ad_gate.dart';
import 'package:client/core/services/unlock_credits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final clock = DateTime(2026, 10, 23, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A rewarded view that always pays out, recording how often it was shown.
  ({UnlockCredits credits, List<int> shown, List<String> unlocked}) build() {
    final shown = <int>[];
    final unlocked = <String>[];
    final credits = UnlockCredits(
      gate: AdGate(now: () => clock),
      showRewardedAd: ({required onRewardGranted}) async {
        shown.add(1);
        onRewardGranted();
        return true;
      },
    );
    return (credits: credits, shown: shown, unlocked: unlocked);
  }

  group('UnlockCredits size', () {
    test('the first use shows the ad and keeps one credit', () async {
      final h = build();
      final didShow = await h.credits.spendSize(() => h.unlocked.add('size'));

      expect(didShow, isTrue);
      expect(h.shown, hasLength(1));
      expect(h.unlocked, ['size']);
      expect(await AdGate().sizeCredits(), 1);
    });

    test('the second use skips the ad', () async {
      final h = build();
      await h.credits.spendSize(() => h.unlocked.add('size'));
      final didShow = await h.credits.spendSize(() => h.unlocked.add('size'));

      expect(didShow, isFalse);
      expect(h.shown, hasLength(1));
      expect(h.unlocked, ['size', 'size']);
      expect(await AdGate().sizeCredits(), 0);
    });

    test('the third use asks for a view again', () async {
      final h = build();
      await h.credits.spendSize(() => h.unlocked.add('size'));
      await h.credits.spendSize(() => h.unlocked.add('size'));
      final didShow = await h.credits.spendSize(() => h.unlocked.add('size'));

      expect(didShow, isTrue);
      expect(h.shown, hasLength(2));
      expect(h.unlocked, hasLength(3));
    });

    test('an ad that never pays out leaves the unlock undone', () async {
      final unlocked = <String>[];
      final credits = UnlockCredits(
        gate: AdGate(now: () => clock),
        showRewardedAd: ({required onRewardGranted}) async => false,
      );

      await credits.spendSize(() => unlocked.add('size'));

      expect(unlocked, isEmpty);
      expect(await AdGate().sizeCredits(), 0);
    });
  });

  group('UnlockCredits extension', () {
    test('the first extension shows the ad and keeps one credit', () async {
      final h = build();
      final didShow =
          await h.credits.spendExtend(() => h.unlocked.add('extend'));

      expect(didShow, isTrue);
      expect(h.shown, hasLength(1));
      expect(await AdGate().extendCredits(), 1);
    });

    test('the second extension skips the ad', () async {
      final h = build();
      await h.credits.spendExtend(() => h.unlocked.add('extend'));
      final didShow =
          await h.credits.spendExtend(() => h.unlocked.add('extend'));

      expect(didShow, isFalse);
      expect(h.shown, hasLength(1));
      expect(await AdGate().extendCredits(), 0);
    });

    test('a size credit is not an extension credit', () async {
      final h = build();
      await h.credits.spendSize(() => h.unlocked.add('size'));

      final didShow =
          await h.credits.spendExtend(() => h.unlocked.add('extend'));

      expect(didShow, isTrue);
      expect(h.shown, hasLength(2));
      expect(await AdGate().sizeCredits(), 1);
      expect(await AdGate().extendCredits(), 1);
    });
  });
}
