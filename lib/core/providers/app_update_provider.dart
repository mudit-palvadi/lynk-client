import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../features/file_transfer/presentation/providers/upload_notifier.dart';
import '../../features/file_transfer/presentation/providers/upload_state.dart';
import '../../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../routing/app_router.dart';
import '../routing/pending_deep_link.dart';
import '../services/play_update_service.dart';
import 'download_notifier.dart';
import 'download_state.dart';

final appUpdateEnabledProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      kReleaseMode &&
      defaultTargetPlatform == TargetPlatform.android,
);

final playUpdateServiceProvider = Provider<PlayUpdateService>(
  (ref) => PlayUpdateService(),
);

final transferBusyProvider = Provider<bool>((ref) {
  final upload = ref.watch(uploadProvider.select((value) => value.phase));
  final download = ref.watch(downloadProvider.select((value) => value.phase));
  return upload == UploadPhase.uploading ||
      download == DownloadPhase.waiting ||
      download == DownloadPhase.downloading;
});

enum AppUpdatePhase { checking, allowed, required, failed, updating }

class AppUpdateState extends Equatable {
  const AppUpdateState({
    this.phase = AppUpdatePhase.checking,
    this.hasEnteredApp = false,
    this.requiredVersion = 0,
  });

  final AppUpdatePhase phase;
  final bool hasEnteredApp;
  final int requiredVersion;

  bool get isBlocked => phase != AppUpdatePhase.allowed;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    bool? hasEnteredApp,
    int? requiredVersion,
  }) => AppUpdateState(
    phase: phase ?? this.phase,
    hasEnteredApp: hasEnteredApp ?? this.hasEnteredApp,
    requiredVersion: requiredVersion ?? this.requiredVersion,
  );

  @override
  List<Object> get props => [phase, hasEnteredApp, requiredVersion];
}

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, AppUpdateState>(
  AppUpdateNotifier.new,
);

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  static const requiredVersionKey = 'play_required_version_code';
  static const checkTimeout = Duration(seconds: 15);

  bool _operation = false;
  bool _pendingCheck = false;
  bool _storeOperation = false;

  void _deferUntilIdle() {
    _pendingCheck = true;
    state = state.copyWith(
      phase: state.hasEnteredApp
          ? AppUpdatePhase.allowed
          : AppUpdatePhase.checking,
    );
  }

  @override
  AppUpdateState build() {
    if (!ref.read(appUpdateEnabledProvider)) {
      return const AppUpdateState(
        phase: AppUpdatePhase.allowed,
        hasEnteredApp: true,
      );
    }
    ref.listen(transferBusyProvider, (previous, busy) {
      if (!busy && _pendingCheck) {
        _pendingCheck = false;
        unawaited(check());
      }
    });
    scheduleMicrotask(check);
    return const AppUpdateState();
  }

  /// A blocked link stays in memory, never in preferences or diagnostic output.
  bool deferLink(Uri uri) {
    if (!state.isBlocked) return false;
    final normalized = normalizeCustomSchemeLink(uri);
    final target = normalized == null ? uri : Uri.parse(normalized);
    if (isTransferDeepLink(target)) {
      PendingDeepLink.remember(canonicalDeepLinkLocation(target));
    }
    return true;
  }

  Future<void> check({bool prompt = true}) async {
    if (!ref.mounted || !ref.read(appUpdateEnabledProvider) || _operation) {
      return;
    }
    if (ref.read(transferBusyProvider)) {
      _deferUntilIdle();
      return;
    }
    _operation = true;
    state = state.copyWith(phase: AppUpdatePhase.checking);
    try {
      final service = ref.read(playUpdateServiceProvider);
      final installed = await service.installedVersion().timeout(checkTimeout);
      final info = await service.check().timeout(checkTimeout);
      if (!ref.mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      var required = prefs.getInt(requiredVersionKey) ?? 0;
      if (installed >= required && required > 0) {
        await prefs.remove(requiredVersionKey);
        required = 0;
      }
      final offered =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress;
      if (offered) {
        final available = info.availableVersionCode;
        if (info.packageName != 'app.xynix.lynk' ||
            available == null ||
            available <= installed) {
          throw StateError('Play returned an invalid update');
        }
        if (available > required) {
          required = available;
          if (!await prefs.setInt(requiredVersionKey, required)) {
            throw StateError('Required version could not be saved');
          }
        }
      }
      if (!ref.mounted) return;
      if (ref.read(transferBusyProvider)) {
        _deferUntilIdle();
        return;
      }
      if (info.updateAvailability == UpdateAvailability.unknown) {
        throw StateError('Play update availability is unknown');
      }
      if (!offered && required == 0) {
        state = state.copyWith(
          phase: AppUpdatePhase.allowed,
          hasEnteredApp: true,
          requiredVersion: 0,
        );
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.required,
        requiredVersion: required,
      );
      if (offered && info.immediateUpdateAllowed && prompt) {
        state = state.copyWith(phase: AppUpdatePhase.updating);
        final result = await service.updateImmediately();
        if (!ref.mounted) return;
        state = state.copyWith(phase: AppUpdatePhase.required);
        // A success callback does not prove that the new binary is running.
        // Recheck without recursively opening another native update flow.
        if (result == AppUpdateResult.success) {
          _operation = false;
          await check(prompt: false);
        }
      }
    } catch (_) {
      if (ref.mounted) {
        if (ref.read(transferBusyProvider)) {
          _deferUntilIdle();
        } else {
          state = state.copyWith(phase: AppUpdatePhase.failed);
        }
      }
    } finally {
      _operation = false;
    }
  }

  Future<void> openStore() async {
    if (_operation || _storeOperation || !state.isBlocked) return;
    _storeOperation = true;
    try {
      if (!await ref.read(playUpdateServiceProvider).openStore() &&
          ref.mounted) {
        state = state.copyWith(phase: AppUpdatePhase.failed);
      }
    } catch (_) {
      if (ref.mounted) state = state.copyWith(phase: AppUpdatePhase.failed);
    } finally {
      _storeOperation = false;
    }
  }
}
