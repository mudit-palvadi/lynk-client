// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(uploadService)
final uploadServiceProvider = UploadServiceProvider._();

final class UploadServiceProvider
    extends $FunctionalProvider<UploadService, UploadService, UploadService>
    with $Provider<UploadService> {
  UploadServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'uploadServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$uploadServiceHash();

  @$internal
  @override
  $ProviderElement<UploadService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UploadService create(Ref ref) {
    return uploadService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UploadService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UploadService>(value),
    );
  }
}

String _$uploadServiceHash() => r'ec08572f17c9833ac7097aab021d029fc65615ef';

@ProviderFor(p2pSessionFactory)
final p2pSessionFactoryProvider = P2pSessionFactoryProvider._();

final class P2pSessionFactoryProvider
    extends
        $FunctionalProvider<
          P2PSenderSessionFactory,
          P2PSenderSessionFactory,
          P2PSenderSessionFactory
        >
    with $Provider<P2PSenderSessionFactory> {
  P2pSessionFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'p2pSessionFactoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$p2pSessionFactoryHash();

  @$internal
  @override
  $ProviderElement<P2PSenderSessionFactory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  P2PSenderSessionFactory create(Ref ref) {
    return p2pSessionFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(P2PSenderSessionFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<P2PSenderSessionFactory>(value),
    );
  }
}

String _$p2pSessionFactoryHash() => r'416f24776f689e8485d224b668ae3bfe5821e792';

/// How long the sender waits (QR visible) for a receiver before silently
/// switching to the R2 cloud pipeline.

@ProviderFor(p2pAutoFallbackDuration)
final p2pAutoFallbackDurationProvider = P2pAutoFallbackDurationProvider._();

/// How long the sender waits (QR visible) for a receiver before silently
/// switching to the R2 cloud pipeline.

final class P2pAutoFallbackDurationProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// How long the sender waits (QR visible) for a receiver before silently
  /// switching to the R2 cloud pipeline.
  P2pAutoFallbackDurationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'p2pAutoFallbackDurationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$p2pAutoFallbackDurationHash();

  @$internal
  @override
  $ProviderElement<Duration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration create(Ref ref) {
    return p2pAutoFallbackDuration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$p2pAutoFallbackDurationHash() =>
    r'5060edbe79fd32dd1a8585aa9a30c1c4149088bf';

@ProviderFor(UploadNotifier)
final uploadProvider = UploadNotifierProvider._();

final class UploadNotifierProvider
    extends $NotifierProvider<UploadNotifier, UploadState> {
  UploadNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'uploadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$uploadNotifierHash();

  @$internal
  @override
  UploadNotifier create() => UploadNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UploadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UploadState>(value),
    );
  }
}

String _$uploadNotifierHash() => r'f78dd1fe567db238508e2b91ad041042e6e7018d';

abstract class _$UploadNotifier extends $Notifier<UploadState> {
  UploadState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UploadState, UploadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UploadState, UploadState>,
              UploadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
