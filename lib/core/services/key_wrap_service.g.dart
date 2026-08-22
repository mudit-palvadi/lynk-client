// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'key_wrap_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(keyWrapService)
final keyWrapServiceProvider = KeyWrapServiceProvider._();

final class KeyWrapServiceProvider
    extends $FunctionalProvider<KeyWrapService, KeyWrapService, KeyWrapService>
    with $Provider<KeyWrapService> {
  KeyWrapServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keyWrapServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keyWrapServiceHash();

  @$internal
  @override
  $ProviderElement<KeyWrapService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  KeyWrapService create(Ref ref) {
    return keyWrapService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeyWrapService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeyWrapService>(value),
    );
  }
}

String _$keyWrapServiceHash() => r'aac7ff3a969b1a552a13d0465f7c593cfed802e8';
