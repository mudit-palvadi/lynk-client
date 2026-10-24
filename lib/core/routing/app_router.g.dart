// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Builds the app router.
///
/// This provider deliberately `watch`es [onboardingProvider] and therefore
/// *rebuilds the whole router* when onboarding flips. That rebuild is
/// load-bearing for deep links: `GoRouter` prefers the platform's default
/// route (the deep link) over `initialLocation`, but only while the router is
/// being constructed. A cold-start link is first redirected to `/onboarding`,
/// which overwrites the router's current location; finishing onboarding
/// recreates the router, which re-reads the platform default and lands on the
/// link. A long-lived router with `refreshListenable` would lose that link.

@ProviderFor(appRouter)
final appRouterProvider = AppRouterProvider._();

/// Builds the app router.
///
/// This provider deliberately `watch`es [onboardingProvider] and therefore
/// *rebuilds the whole router* when onboarding flips. That rebuild is
/// load-bearing for deep links: `GoRouter` prefers the platform's default
/// route (the deep link) over `initialLocation`, but only while the router is
/// being constructed. A cold-start link is first redirected to `/onboarding`,
/// which overwrites the router's current location; finishing onboarding
/// recreates the router, which re-reads the platform default and lands on the
/// link. A long-lived router with `refreshListenable` would lose that link.

final class AppRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// Builds the app router.
  ///
  /// This provider deliberately `watch`es [onboardingProvider] and therefore
  /// *rebuilds the whole router* when onboarding flips. That rebuild is
  /// load-bearing for deep links: `GoRouter` prefers the platform's default
  /// route (the deep link) over `initialLocation`, but only while the router is
  /// being constructed. A cold-start link is first redirected to `/onboarding`,
  /// which overwrites the router's current location; finishing onboarding
  /// recreates the router, which re-reads the platform default and lands on the
  /// link. A long-lived router with `refreshListenable` would lose that link.
  AppRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appRouterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return appRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$appRouterHash() => r'3ec04a9f87ae4169f4a7f806d42b597de8dbbe44';
