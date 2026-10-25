import 'dart:async';

import 'package:client/core/providers/app_update_provider.dart';
import 'package:client/core/routing/pending_deep_link.dart';
import 'package:client/core/services/play_update_service.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _busyProvider = NotifierProvider<_BusyNotifier, bool>(_BusyNotifier.new);

class _BusyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void change(bool busy) => state = busy;
}

class _Play extends PlayUpdateService {
  int installed = 4;
  int checks = 0;
  int prompts = 0;
  int stores = 0;
  bool storeAvailable = true;
  Object? failure;
  Completer<AppUpdateInfo>? pending;
  AppUpdateResult result = AppUpdateResult.userDeniedUpdate;
  AppUpdateInfo info = _info(UpdateAvailability.updateNotAvailable);

  @override
  Future<int> installedVersion() async => installed;

  @override
  Future<AppUpdateInfo> check() async {
    checks++;
    if (failure != null) throw failure!;
    return pending == null ? info : await pending!.future;
  }

  @override
  Future<AppUpdateResult> updateImmediately() async {
    prompts++;
    return result;
  }

  @override
  Future<bool> openStore() async {
    stores++;
    return storeAvailable;
  }
}

AppUpdateInfo _info(
  UpdateAvailability availability, {
  int? version = 10,
  bool immediate = true,
  String packageName = 'app.xynix.lynk',
}) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: immediate,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: true,
  flexibleAllowedPreconditions: null,
  availableVersionCode: version,
  installStatus: InstallStatus.unknown,
  packageName: packageName,
  clientVersionStalenessDays: null,
  updatePriority: 0,
);

void main() {
  late _Play play;
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> create({bool enabled = true, int requiredVersion = 0}) async {
    SharedPreferences.setMockInitialValues({
      if (requiredVersion > 0)
        AppUpdateNotifier.requiredVersionKey: requiredVersion,
    });
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appUpdateEnabledProvider.overrideWithValue(enabled),
        playUpdateServiceProvider.overrideWithValue(play),
        transferBusyProvider.overrideWith((ref) => ref.watch(_busyProvider)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appUpdateProvider, (_, _) {}, fireImmediately: true);
    await pumpEventQueue();
  }

  setUp(() {
    play = _Play();
    PendingDeepLink.clear();
  });
  tearDown(PendingDeepLink.clear);

  group('strict Play update policy', () {
    test('debug and non-Android bypass makes no native calls', () async {
      await create(enabled: false);
      await container.read(appUpdateProvider.notifier).check();
      expect(container.read(appUpdateProvider).isBlocked, false);
      expect(play.checks, 0);
    });

    test('no update is the only initial admission path', () async {
      await create();
      expect(container.read(appUpdateProvider).hasEnteredApp, true);
      expect(container.read(appUpdateProvider).isBlocked, false);
      expect(play.prompts, 0);
    });

    for (final availability in [
      UpdateAvailability.updateAvailable,
      UpdateAvailability.developerTriggeredUpdateInProgress,
    ]) {
      test(
        '$availability prompts once and cancellation stays locked',
        () async {
          play.info = _info(availability);
          await create();
          expect(play.prompts, 1);
          expect(
            container.read(appUpdateProvider).phase,
            AppUpdatePhase.required,
          );
          expect(prefs.getInt(AppUpdateNotifier.requiredVersionKey), 10);
        },
      );
    }

    test(
      'unavailable immediate flow leaves the Store fallback locked',
      () async {
        play.info = _info(UpdateAvailability.updateAvailable, immediate: false);
        await create();
        await container.read(appUpdateProvider.notifier).openStore();
        expect(play.prompts, 0);
        expect(play.stores, 1);
        expect(container.read(appUpdateProvider).isBlocked, true);
        play.storeAvailable = false;
        await container.read(appUpdateProvider.notifier).openStore();
        expect(container.read(appUpdateProvider).phase, AppUpdatePhase.failed);
      },
    );

    test('a successful native callback cannot admit the old binary', () async {
      play.info = _info(UpdateAvailability.updateAvailable);
      play.result = AppUpdateResult.success;
      await create();
      expect(play.checks, 2);
      expect(play.prompts, 1);
      expect(container.read(appUpdateProvider).isBlocked, true);
    });

    test(
      'remembered version survives no-offer until actually installed',
      () async {
        await create(requiredVersion: 10);
        expect(container.read(appUpdateProvider).isBlocked, true);
        play.installed = 10;
        await container.read(appUpdateProvider.notifier).check();
        expect(container.read(appUpdateProvider).isBlocked, false);
        expect(prefs.containsKey(AppUpdateNotifier.requiredVersionKey), false);
      },
    );

    test(
      'an older offer cannot lower the remembered required version',
      () async {
        play.info = _info(UpdateAvailability.updateAvailable, version: 9);
        await create(requiredVersion: 10);
        expect(container.read(appUpdateProvider).requiredVersion, 10);
        expect(prefs.getInt(AppUpdateNotifier.requiredVersionKey), 10);
      },
    );

    for (final info in [
      _info(UpdateAvailability.unknown),
      _info(UpdateAvailability.updateAvailable, version: null),
      _info(UpdateAvailability.updateAvailable, version: 4),
      _info(UpdateAvailability.updateAvailable, packageName: 'another.app'),
    ]) {
      test(
        'unknown or inconsistent native information fails closed: $info',
        () async {
          play.info = info;
          await create();
          expect(
            container.read(appUpdateProvider).phase,
            AppUpdatePhase.failed,
          );
          expect(play.prompts, 0);
        },
      );
    }

    test('a failed check retries without leaking the raw exception', () async {
      play.failure = StateError('sensitive native detail');
      await create();
      expect(container.read(appUpdateProvider).phase, AppUpdatePhase.failed);
      expect(
        container.read(appUpdateProvider).toString(),
        isNot(contains('sensitive')),
      );
      play.failure = null;
      await container.read(appUpdateProvider.notifier).check();
      expect(container.read(appUpdateProvider).isBlocked, false);
    });

    test(
      'resume checks wait for active transfers, then require the update',
      () async {
        await create();
        container.read(_busyProvider.notifier).change(true);
        play.info = _info(UpdateAvailability.updateAvailable);
        await container.read(appUpdateProvider.notifier).check();
        expect(play.checks, 1);
        expect(container.read(appUpdateProvider).isBlocked, false);
        container.read(_busyProvider.notifier).change(false);
        await pumpEventQueue();
        expect(play.checks, 2);
        expect(container.read(appUpdateProvider).hasEnteredApp, true);
        expect(container.read(appUpdateProvider).isBlocked, true);
      },
    );

    test(
      'concurrent resume or retry cannot open overlapping native flows',
      () async {
        play.pending = Completer<AppUpdateInfo>();
        await create();
        await container.read(appUpdateProvider.notifier).check();
        await container.read(appUpdateProvider.notifier).check();
        expect(play.checks, 1);
        play.pending!.complete(_info(UpdateAvailability.updateAvailable));
        await pumpEventQueue();
        expect(play.prompts, 1);
      },
    );

    test(
      'a transfer starting during a failed check is not interrupted',
      () async {
        await create();
        play.pending = Completer<AppUpdateInfo>();
        final check = container.read(appUpdateProvider.notifier).check();
        await pumpEventQueue();
        container.read(_busyProvider.notifier).change(true);
        play.pending!.completeError(StateError('offline'));
        await check;
        expect(container.read(appUpdateProvider).isBlocked, false);
        play.pending = null;
        play.info = _info(UpdateAvailability.updateAvailable);
        container.read(_busyProvider.notifier).change(false);
        await pumpEventQueue();
        expect(container.read(appUpdateProvider).isBlocked, true);
        expect(play.prompts, 1);
      },
    );

    test('blocked transfer links are retained only in memory', () async {
      play.info = _info(UpdateAvailability.updateAvailable);
      await create();
      final notifier = container.read(appUpdateProvider.notifier);
      expect(notifier.deferLink(Uri.parse('lynk://send/id#key&a=token')), true);
      expect(PendingDeepLink.take(), '/send/id#key&a=token');
      expect(prefs.getKeys(), {AppUpdateNotifier.requiredVersionKey});
    });
  });
}
