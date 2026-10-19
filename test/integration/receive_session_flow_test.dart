import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/network_providers.dart';
import 'package:client/core/providers/receiver_notifier.dart';
import 'package:client/core/providers/receiver_providers.dart';
import 'package:client/core/services/key_wrap_service.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

/// The reverse-pairing flow, end to end through the client's own layers.
///
/// A receiver creates a session, the sender wraps the AES key for the
/// receiver's public key and attaches it, and the receiver's poller picks it up
/// and unwraps the key locally.
///
/// The backend never sees the AES key - only the opaque wrapped blob - so this
/// test also proves the zero-knowledge property survives the whole round trip.
///
/// These are plain `test()` cases, not `testWidgets`: the receiver polls on a
/// real `Timer` and the key derivation is real async work, and `testWidgets`
/// would freeze both inside its fake clock.
void main() {
  const aesKey = '0123456789abcdef0123456789abcdef';

  // The receiver registers itself as a WidgetsBindingObserver, so a binding
  // must exist even though no widget tree is pumped.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=https://api.test.local/api/v1/',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'ads_enabled': false});
  });

  test('the receiver recovers the key the sender wrapped for it', () async {
    final backend = FakeBackend();
    final container = await _container(backend);
    addTearDown(container.dispose);

    // 1. The receiver creates a session and keeps the key pair in memory.
    final notifier = container.read(receiverProvider.notifier);
    await notifier.createSession();

    final created = container.read(receiverProvider);
    expect(created.session, isNotNull);
    expect(created.errorMessage, isNull);
    expect(created.receiverPublicKeyB64, isNotNull);
    expect(created.receiverPrivateKeySeed, isNotNull);
    expect(created.session!.status, ReceiverSessionStatus.waiting);

    // 2. The sender wraps the AES key for the receiver's public key and
    // attaches it to the session. This is the client's own code path.
    final wrapped = await KeyWrapService().wrapKey(
      aesKey: aesKey,
      receiverPublicKeyB64: created.receiverPublicKeyB64!,
      sessionId: created.session!.id,
    );

    final attached = await container.read(receiverRepositoryProvider).attachTransfer(
      sessionId: created.session!.id,
      transferId: 'transfer-under-test',
      wrappedKey: wrapped,
    );
    expect(attached.isSuccess, isTrue);

    // 3. The backend now reports the session as attached.
    final attachRequest = backend.adapter!.requests.last;
    expect(attachRequest.method, 'POST');
    expect(
      attachRequest.path,
      'receiver-sessions/${created.session!.id}/attach-transfer',
    );
    final body = (attachRequest.body as Map).cast<String, dynamic>();
    expect(body['transfer_id'], 'transfer-under-test');
    expect(body['wrapped_key'], isNotNull);
    // The plaintext key is never sent.
    expect(attachRequest.rawBody, isNot(contains(aesKey)));

    // 4. The poller notices and unwraps the key locally.
    await _waitUntil(
      () => container.read(receiverProvider).attachedAesKey != null,
      description: 'the receiver to unwrap the attached key',
    );

    final attachedState = container.read(receiverProvider);
    expect(attachedState.attachedTransferId, 'transfer-under-test');
    expect(attachedState.attachedAesKey, aesKey);
  });

  test('a session that is never attached keeps polling', () async {
    final backend = FakeBackend();
    final container = await _container(backend);
    addTearDown(container.dispose);

    await container.read(receiverProvider.notifier).createSession();
    expect(container.read(receiverProvider).session, isNotNull);

    // The first poll happens two seconds after the session is created.
    await _waitUntil(
      () => backend.adapter!.requestsTo('receiver-sessions/').isNotEmpty,
      description: 'the receiver to poll the session over HTTP',
    );

    final state = container.read(receiverProvider);
    expect(state.attachedAesKey, isNull);
    expect(state.errorMessage, isNull);
    expect(state.isPolling, isTrue);
  });
}

/// Waits for [condition] to become true, polling on the real clock.
///
/// The receiver's poll timer fires every two seconds, so the test cannot know
/// exactly when the state changes; it has to wait for it.
Future<void> _waitUntil(
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $description.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _container(FakeBackend backend) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(dio: backend.createDio()),
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  // `receiverProvider` is auto-dispose: without a listener it would be torn
  // down the moment the first await in `createSession` yields, and the
  // notifier could no longer write its result. Listening keeps it alive for
  // the lifetime of the container, exactly like a mounted screen would.
  container.listen<void>(receiverProvider, (_, _) {});

  return container;
}
