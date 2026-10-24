// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'code_receiver_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Types the sender's six-digit code into a paired transfer.
///
/// The code names the session. The receiver publishes an ephemeral public key,
/// then asks again and again until the sender has wrapped the AES key for it.
/// Nothing secret is ever recoverable from the code itself.

@ProviderFor(CodeReceiverNotifier)
final codeReceiverProvider = CodeReceiverNotifierProvider._();

/// Types the sender's six-digit code into a paired transfer.
///
/// The code names the session. The receiver publishes an ephemeral public key,
/// then asks again and again until the sender has wrapped the AES key for it.
/// Nothing secret is ever recoverable from the code itself.
final class CodeReceiverNotifierProvider
    extends $NotifierProvider<CodeReceiverNotifier, CodeReceiveState> {
  /// Types the sender's six-digit code into a paired transfer.
  ///
  /// The code names the session. The receiver publishes an ephemeral public key,
  /// then asks again and again until the sender has wrapped the AES key for it.
  /// Nothing secret is ever recoverable from the code itself.
  CodeReceiverNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'codeReceiverProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$codeReceiverNotifierHash();

  @$internal
  @override
  CodeReceiverNotifier create() => CodeReceiverNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CodeReceiveState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CodeReceiveState>(value),
    );
  }
}

String _$codeReceiverNotifierHash() =>
    r'5a70b6c52011c55d9b9bb2dcd368709b19c96a10';

/// Types the sender's six-digit code into a paired transfer.
///
/// The code names the session. The receiver publishes an ephemeral public key,
/// then asks again and again until the sender has wrapped the AES key for it.
/// Nothing secret is ever recoverable from the code itself.

abstract class _$CodeReceiverNotifier extends $Notifier<CodeReceiveState> {
  CodeReceiveState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CodeReceiveState, CodeReceiveState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CodeReceiveState, CodeReceiveState>,
              CodeReceiveState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
