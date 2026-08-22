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

String _$uploadNotifierHash() => r'f8cbaeb9d3276c3f48e50bb293f7af214c9c1083';

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
