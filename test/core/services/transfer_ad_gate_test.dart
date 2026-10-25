import 'package:client/core/services/ad_gate.dart';
import 'package:client/core/services/transfer_ad_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Recorder {
  _Recorder({this.autoReward = true});

  final bool autoReward;
  bool throwError = false;
  final List<String> calls = <String>[];

  Future<bool> cloud({required void Function() onRewardGranted}) async {
    calls.add('cloud');
    if (throwError) throw StateError('ad failed');
    if (autoReward) onRewardGranted();
    return true;
  }

  Future<bool> p2p({required void Function() onRewardGranted}) async {
    calls.add('p2p');
    if (throwError) throw StateError('ad failed');
    if (autoReward) onRewardGranted();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clock = DateTime(2026, 10, 23, 12);
  const key = 'ads_free_until_ms';
  const firstKey = 'ads_first_transfer_used';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  AdGate gate() => AdGate(now: () => clock);

  test('runs the action without an ad while the free window is open', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      key: clock.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    });
    final recorder = _Recorder();
    var allowed = false;

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: false, onAllowed: () => allowed = true);

    expect(allowed, isTrue);
    expect(recorder.calls, isEmpty);
  });

  test('the first transfer is free and opens the window', () async {
    final recorder = _Recorder();
    var allowed = false;

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: false, onAllowed: () => allowed = true);

    expect(recorder.calls, isEmpty);
    expect(allowed, isTrue);
    expect(await gate().isFreeWindowOpen(), isTrue);
  });

  test('shows the cloud ad when the window is closed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{firstKey: true});
    final recorder = _Recorder();
    var allowed = false;

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: false, onAllowed: () => allowed = true);

    expect(recorder.calls, <String>['cloud']);
    expect(allowed, isTrue);
    expect(await gate().isFreeWindowOpen(), isTrue);
  });

  test('uses the p2p ad on the direct button', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{firstKey: true});
    final recorder = _Recorder();

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: true, onAllowed: () {});

    expect(recorder.calls, <String>['p2p']);
    expect(await gate().isFreeWindowOpen(), isTrue);
  });

  test('waits for the reward before running the action', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{firstKey: true});
    final recorder = _Recorder(autoReward: false);
    var allowed = false;

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: false, onAllowed: () => allowed = true);

    expect(recorder.calls, <String>['cloud']);
    expect(allowed, isFalse);
    expect(await gate().isFreeWindowOpen(), isFalse);
  });

  test('shows the ad again once the window has passed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      firstKey: true,
      key: clock.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    });
    final recorder = _Recorder();

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: false, onAllowed: () {});

    expect(recorder.calls, <String>['cloud']);
  });

  test('a thrown ad still allows the send and opens the window', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{firstKey: true});
    final recorder = _Recorder()..throwError = true;
    var allowed = false;

    await TransferAdGate(
      gate: gate(),
      showCloudAd: recorder.cloud,
      showP2pAd: recorder.p2p,
    ).start(p2p: false, onAllowed: () => allowed = true);

    expect(recorder.calls, <String>['cloud']);
    expect(allowed, isTrue);
    expect(await gate().isFreeWindowOpen(), isTrue);
  });
}
