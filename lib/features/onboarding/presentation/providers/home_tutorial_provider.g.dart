// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_tutorial_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the home-screen walkthrough has already been shown.
///
/// It lives next to onboarding because it is the same idea: a one-time
/// introduction, remembered on the device so it does not come back on every
/// launch. Onboarding explains what the app is; this points at the four things
/// the home screen can do.

@ProviderFor(HomeTutorialNotifier)
final homeTutorialProvider = HomeTutorialNotifierProvider._();

/// Whether the home-screen walkthrough has already been shown.
///
/// It lives next to onboarding because it is the same idea: a one-time
/// introduction, remembered on the device so it does not come back on every
/// launch. Onboarding explains what the app is; this points at the four things
/// the home screen can do.
final class HomeTutorialNotifierProvider
    extends $NotifierProvider<HomeTutorialNotifier, bool> {
  /// Whether the home-screen walkthrough has already been shown.
  ///
  /// It lives next to onboarding because it is the same idea: a one-time
  /// introduction, remembered on the device so it does not come back on every
  /// launch. Onboarding explains what the app is; this points at the four things
  /// the home screen can do.
  HomeTutorialNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeTutorialProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeTutorialNotifierHash();

  @$internal
  @override
  HomeTutorialNotifier create() => HomeTutorialNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$homeTutorialNotifierHash() =>
    r'9915a974ee0dd489c783670a14a5c9e423bd7c90';

/// Whether the home-screen walkthrough has already been shown.
///
/// It lives next to onboarding because it is the same idea: a one-time
/// introduction, remembered on the device so it does not come back on every
/// launch. Onboarding explains what the app is; this points at the four things
/// the home screen can do.

abstract class _$HomeTutorialNotifier extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
