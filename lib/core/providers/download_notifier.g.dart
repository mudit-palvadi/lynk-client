// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(downloadService)
final downloadServiceProvider = DownloadServiceProvider._();

final class DownloadServiceProvider
    extends
        $FunctionalProvider<DownloadService, DownloadService, DownloadService>
    with $Provider<DownloadService> {
  DownloadServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadServiceHash();

  @$internal
  @override
  $ProviderElement<DownloadService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DownloadService create(Ref ref) {
    return downloadService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadService>(value),
    );
  }
}

String _$downloadServiceHash() => r'a1930802bcd8cd2cdfc4b544a9275d75ee647997';

@ProviderFor(p2pReceiverSessionFactory)
final p2pReceiverSessionFactoryProvider = P2pReceiverSessionFactoryProvider._();

final class P2pReceiverSessionFactoryProvider
    extends
        $FunctionalProvider<
          P2PReceiverSessionFactory,
          P2PReceiverSessionFactory,
          P2PReceiverSessionFactory
        >
    with $Provider<P2PReceiverSessionFactory> {
  P2pReceiverSessionFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'p2pReceiverSessionFactoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$p2pReceiverSessionFactoryHash();

  @$internal
  @override
  $ProviderElement<P2PReceiverSessionFactory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  P2PReceiverSessionFactory create(Ref ref) {
    return p2pReceiverSessionFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(P2PReceiverSessionFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<P2PReceiverSessionFactory>(value),
    );
  }
}

String _$p2pReceiverSessionFactoryHash() =>
    r'7360bbd00b30992d73ec35d97854c4a9698873af';

@ProviderFor(DownloadNotifier)
final downloadProvider = DownloadNotifierProvider._();

final class DownloadNotifierProvider
    extends $NotifierProvider<DownloadNotifier, DownloadState> {
  DownloadNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadNotifierHash();

  @$internal
  @override
  DownloadNotifier create() => DownloadNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadState>(value),
    );
  }
}

String _$downloadNotifierHash() => r'b4a394e4f28e0a70e395ea8b0b36886f85f27aa7';

abstract class _$DownloadNotifier extends $Notifier<DownloadState> {
  DownloadState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DownloadState, DownloadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DownloadState, DownloadState>,
              DownloadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
