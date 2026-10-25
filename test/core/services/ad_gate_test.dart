import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/core/services/ad_gate.dart';

void main() {
  test('the default window is fifteen minutes', () {
    expect(AdGate().window, const Duration(minutes: 15));
  });
  late DateTime clock;

  AdGate gate() => AdGate(now: () => clock);

  setUp(() {
    clock = DateTime(2026, 10, 23, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AdGate free window', () {
    test('starts closed', () async {
      expect(await gate().isFreeWindowOpen(), isFalse);
    });

    test('opens for fifteen minutes after an automatic ad', () async {
      final g = gate();
      await g.openFreeWindow();

      expect(await g.isFreeWindowOpen(), isTrue);

      clock = clock.add(const Duration(minutes: 14, seconds: 59));
      expect(await g.isFreeWindowOpen(), isTrue);

      clock = clock.add(const Duration(seconds: 1));
      expect(await g.isFreeWindowOpen(), isFalse);
    });

    test('survives a restart', () async {
      await gate().openFreeWindow();

      expect(await gate().isFreeWindowOpen(), isTrue);
    });

    test('opens again after a second ad', () async {
      final g = gate();
      await g.openFreeWindow();
      clock = clock.add(const Duration(minutes: 20));
      expect(await g.isFreeWindowOpen(), isFalse);

      await g.openFreeWindow();
      expect(await g.isFreeWindowOpen(), isTrue);
    });
  });

  group('AdGate credits', () {
    test('start at zero and spend nothing', () async {
      final g = gate();

      expect(await g.sizeCredits(), 0);
      expect(await g.consumeSizeCredit(), isFalse);
      expect(await g.extendCredits(), 0);
      expect(await g.consumeExtendCredit(), isFalse);
    });

    test('one view grants two size unlocks', () async {
      final g = gate();
      await g.grantSizeCredits();

      expect(await g.consumeSizeCredit(), isTrue);
      expect(await g.consumeSizeCredit(), isTrue);
      expect(await g.consumeSizeCredit(), isFalse);
      expect(await g.sizeCredits(), 0);
    });

    test('size and extension credits are independent', () async {
      final g = gate();
      await g.grantSizeCredits();

      expect(await g.extendCredits(), 0);
      expect(await g.consumeExtendCredit(), isFalse);
      expect(await g.consumeSizeCredit(), isTrue);
    });

    test('credits survive a restart', () async {
      await gate().grantExtendCredits();

      expect(await gate().consumeExtendCredit(), isTrue);
      expect(await gate().consumeExtendCredit(), isTrue);
      expect(await gate().consumeExtendCredit(), isFalse);
    });

    test('a second view refills to two, never beyond', () async {
      final g = gate();
      await g.grantSizeCredits();
      await g.consumeSizeCredit();
      expect(await g.sizeCredits(), 1);

      await g.grantSizeCredits();
      expect(await g.sizeCredits(), AdGate.creditsPerView);
    });
  });

  group('AdGate first transfer', () {
    test('is free once per install', () async {
      final g = gate();

      expect(await g.consumeFirstTransfer(), isTrue);
      expect(await g.consumeFirstTransfer(), isFalse);
    });

    test('survives a restart', () async {
      await gate().consumeFirstTransfer();

      expect(await gate().consumeFirstTransfer(), isFalse);
    });
  });
}
