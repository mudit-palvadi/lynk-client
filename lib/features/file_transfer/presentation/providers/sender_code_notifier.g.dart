// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sender_code_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Keeps the sender's code session alive while the app moves on.
///
/// A cloud sender may leave the share screen right after uploading: the code
/// is still good, and the receiver must be able to collect the wrapped key.
/// That is why this provider is kept alive instead of tied to the screen.

@ProviderFor(SenderCodeNotifier)
final senderCodeProvider = SenderCodeNotifierProvider._();

/// Keeps the sender's code session alive while the app moves on.
///
/// A cloud sender may leave the share screen right after uploading: the code
/// is still good, and the receiver must be able to collect the wrapped key.
/// That is why this provider is kept alive instead of tied to the screen.
final class SenderCodeNotifierProvider
    extends $NotifierProvider<SenderCodeNotifier, SenderCodeState> {
  /// Keeps the sender's code session alive while the app moves on.
  ///
  /// A cloud sender may leave the share screen right after uploading: the code
  /// is still good, and the receiver must be able to collect the wrapped key.
  /// That is why this provider is kept alive instead of tied to the screen.
  SenderCodeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'senderCodeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$senderCodeNotifierHash();

  @$internal
  @override
  SenderCodeNotifier create() => SenderCodeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SenderCodeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SenderCodeState>(value),
    );
  }
}

String _$senderCodeNotifierHash() =>
    r'454a2c940b42a6ab1c1066a1ab3606793fb90321';

/// Keeps the sender's code session alive while the app moves on.
///
/// A cloud sender may leave the share screen right after uploading: the code
/// is still good, and the receiver must be able to collect the wrapped key.
/// That is why this provider is kept alive instead of tied to the screen.

abstract class _$SenderCodeNotifier extends $Notifier<SenderCodeState> {
  SenderCodeState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SenderCodeState, SenderCodeState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SenderCodeState, SenderCodeState>,
              SenderCodeState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
