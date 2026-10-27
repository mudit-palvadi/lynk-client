import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_update_provider.dart';
import '../routing/app_router.dart';
import '../routing/pending_deep_link.dart';
import '../theme/app_theme.dart';

class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(appUpdateProvider.notifier).check());
    }
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation information) async =>
      ref.read(appUpdateProvider.notifier).deferLink(information.uri);

  @override
  Future<bool> didPushRoute(String route) async =>
      ref.read(appUpdateProvider.notifier).deferLink(Uri.parse(route));

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider);
    ref.listen(appUpdateProvider, (previous, next) {
      if (previous?.hasEnteredApp == true &&
          previous?.isBlocked == true &&
          !next.isBlocked) {
        final pending = PendingDeepLink.take();
        if (pending != null) ref.read(appRouterProvider).go(pending);
      }
    });
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        // Keep an existing router (and its memory-only route arguments) alive.
        if (update.hasEnteredApp)
          Offstage(offstage: update.isBlocked, child: widget.child),
        if (update.isBlocked)
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: PopScope(
              canPop: false,
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _UpdateMessage(update: update),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UpdateMessage extends ConsumerWidget {
  const _UpdateMessage({required this.update});

  final AppUpdateState update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appUpdateProvider.notifier);
    final busy =
        update.phase == AppUpdatePhase.checking ||
        update.phase == AppUpdatePhase.updating;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          update.phase == AppUpdatePhase.updating
              ? 'Updating LynkShare'
              : busy
              ? 'Checking for updates'
              : 'Update required',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          update.phase == AppUpdatePhase.failed
              ? 'Unable to verify the latest version. Check the connection and retry, or update from Google Play.'
              : 'Install the latest LynkShare version to continue.',
          textAlign: TextAlign.center,
        ),
        if (!busy) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: notifier.check, child: const Text('Retry')),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: notifier.openStore,
            child: const Text('Open Google Play'),
          ),
        ],
      ],
    );
  }
}
