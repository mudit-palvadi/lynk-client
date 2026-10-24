// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receiver_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(receiverRemoteDataSource)
final receiverRemoteDataSourceProvider = ReceiverRemoteDataSourceProvider._();

final class ReceiverRemoteDataSourceProvider
    extends
        $FunctionalProvider<
          ReceiverRemoteDataSource,
          ReceiverRemoteDataSource,
          ReceiverRemoteDataSource
        >
    with $Provider<ReceiverRemoteDataSource> {
  ReceiverRemoteDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiverRemoteDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiverRemoteDataSourceHash();

  @$internal
  @override
  $ProviderElement<ReceiverRemoteDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiverRemoteDataSource create(Ref ref) {
    return receiverRemoteDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiverRemoteDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiverRemoteDataSource>(value),
    );
  }
}

String _$receiverRemoteDataSourceHash() =>
    r'fcce86b3200f736a204c74ad61349932454e0b2b';

@ProviderFor(codeSessionRemoteDataSource)
final codeSessionRemoteDataSourceProvider =
    CodeSessionRemoteDataSourceProvider._();

final class CodeSessionRemoteDataSourceProvider
    extends
        $FunctionalProvider<
          CodeSessionRemoteDataSource,
          CodeSessionRemoteDataSource,
          CodeSessionRemoteDataSource
        >
    with $Provider<CodeSessionRemoteDataSource> {
  CodeSessionRemoteDataSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'codeSessionRemoteDataSourceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$codeSessionRemoteDataSourceHash();

  @$internal
  @override
  $ProviderElement<CodeSessionRemoteDataSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CodeSessionRemoteDataSource create(Ref ref) {
    return codeSessionRemoteDataSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CodeSessionRemoteDataSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CodeSessionRemoteDataSource>(value),
    );
  }
}

String _$codeSessionRemoteDataSourceHash() =>
    r'5b2c4adbef169f1e9444d06aa5d0350e0d576f30';

@ProviderFor(receiverRepository)
final receiverRepositoryProvider = ReceiverRepositoryProvider._();

final class ReceiverRepositoryProvider
    extends
        $FunctionalProvider<
          ReceiverRepository,
          ReceiverRepository,
          ReceiverRepository
        >
    with $Provider<ReceiverRepository> {
  ReceiverRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiverRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiverRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReceiverRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiverRepository create(Ref ref) {
    return receiverRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiverRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiverRepository>(value),
    );
  }
}

String _$receiverRepositoryHash() =>
    r'c9faabf64e0c349feef1fb94599fe648551ab40b';
