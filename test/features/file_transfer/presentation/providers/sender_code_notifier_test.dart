import 'dart:async';

import 'package:client/core/providers/transfer_providers.dart';
import 'package:dio/dio.dart';
import 'package:client/core/services/key_fingerprint.dart';
import 'package:client/core/services/key_wrap_service.dart';
import 'package:client/features/file_transfer/data/datasources/sender_session_remote_data_source.dart';
import 'package:client/features/file_transfer/data/models/sender_session_model.dart';
import 'package:client/features/file_transfer/presentation/providers/sender_code_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataSource implements SenderSessionRemoteDataSource {
  _FakeDataSource();

  bool createFails = false;
  SenderSessionModel nextSession = const SenderSessionModel(
    sessionId: 'session-1',
    code: '123456',
    status: 'waiting',
    expiresIn: 600,
  );

  int createCalls = 0;
  int cancelCalls = 0;
  int getCalls = 0;
  String? attachedKey;
  String? attachedMode;
  Completer<SenderSessionModel>? holdGet;

  @override
  Future<SenderSessionModel> createSession() async {
    createCalls++;
    if (createFails) throw Exception('boom');
    return nextSession;
  }

  @override
  Future<SenderSessionModel> getSession(String sessionId) {
    getCalls++;
    final hold = holdGet;
    if (hold != null) return hold.future;
    return Future.value(nextSession);
  }

  @override
  Future<void> attachKey({
    required String sessionId,
    required String transferId,
    required String wrappedKey,
    required String mode,
    required String senderSecret,
    CancelToken? cancelToken,
  }) async {
    attachedKey = wrappedKey;
    attachedMode = mode;
  }

  @override
  Future<void> cancelSession({
    required String sessionId,
    required String senderSecret,
  }) async {
    cancelCalls++;
  }
}

class _FakeKeyWrap extends KeyWrapService {
  _FakeKeyWrap();

  String? wrappedFor;
  String? tokenSeen;

  @override
  Future<String> wrapKey({
    required String aesKey,
    required String receiverPublicKeyB64,
    required String sessionId,
    String? accessToken,
  }) async {
    wrappedFor = receiverPublicKeyB64;
    tokenSeen = accessToken;
    return 'wrapped::$sessionId';
  }
}

void main() {
  late _FakeDataSource data;
  late _FakeKeyWrap wrap;
  late ProviderContainer container;

  SenderCodeState read() => container.read(senderCodeProvider);
  SenderCodeNotifier notifier() => container.read(senderCodeProvider.notifier);

  setUp(() {
    data = _FakeDataSource();
    wrap = _FakeKeyWrap();
    container = ProviderContainer(
      overrides: [
        senderSessionRemoteDataSourceProvider.overrideWith((ref) => data),
        keyWrapServiceProvider.overrideWith((ref) => wrap),
      ],
    );
    container.listen(senderCodeProvider, (_, _) {});
    notifier().pollInterval = Duration.zero;
  });

  tearDown(() => container.dispose());

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 50 && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(condition(), isTrue, reason: 'state never reached the expectation');
  }

  test('a code is minted and shown', () async {
    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      accessToken: 'token-1',
      mode: TransferMode.cloud,
    );

    expect(read().code, '123456');
    expect(read().phase, SenderCodePhase.waiting);
    expect(data.createCalls, 1);
  });

  test('returning to the same transfer reuses the waiting code', () async {
    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      accessToken: 'token-1',
      mode: TransferMode.cloud,
    );
    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      accessToken: 'token-1',
      mode: TransferMode.cloud,
    );

    expect(data.createCalls, 1);
    expect(read().code, '123456');
  });

  test('a joined receiver gets the key, the token and the mode', () async {
    data.nextSession = const SenderSessionModel(
      sessionId: 'session-1',
      status: 'joined',
      expiresIn: 500,
      receiverPk: 'pk-1',
    );

    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      accessToken: 'token-1',
      mode: TransferMode.p2p,
    );
    await waitFor(() => read().isAttached);

    expect(wrap.wrappedFor, 'pk-1');
    expect(wrap.tokenSeen, 'token-1');
    expect(data.attachedKey, 'wrapped::session-1');
    expect(data.attachedMode, 'p2p');
    expect(read().keyCheck, keyFingerprint('pk-1'));
  });

  test(
    'a cloud send keeps the same code for the next transfer only once',
    () async {
      await notifier().ensureStarted(
        transferId: 'transfer-1',
        aesKey: 'aes-1',
        accessToken: 'token-1',
        mode: TransferMode.cloud,
      );
      await notifier().ensureStarted(
        transferId: 'transfer-2',
        aesKey: 'aes-2',
        accessToken: 'token-2',
        mode: TransferMode.cloud,
      );

      expect(data.createCalls, 2);
      expect(read().transferId, 'transfer-2');
    },
  );

  test('a failed create is reported without a code', () async {
    data.createFails = true;

    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      mode: TransferMode.cloud,
    );

    expect(read().phase, SenderCodePhase.failed);
    expect(read().code, isNull);
    expect(read().errorMessage, isNotNull);
  });

  test('stopping clears the code', () async {
    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      mode: TransferMode.cloud,
    );

    notifier().stop();

    expect(read().phase, SenderCodePhase.idle);
    expect(read().code, isNull);
  });

  test('a poll that finishes after stop does not fail the next code', () async {
    data.nextSession = const SenderSessionModel(
      sessionId: 'session-1',
      code: '123456',
      status: 'waiting',
      expiresIn: 600,
      senderSecret: 'sender-secret',
    );
    data.holdGet = Completer<SenderSessionModel>();
    await notifier().ensureStarted(
      transferId: 'transfer-1',
      aesKey: 'aes-1',
      mode: TransferMode.cloud,
    );
    await waitFor(() => data.getCalls > 0);

    notifier().stop();
    data.holdGet!.complete(
      const SenderSessionModel(
        sessionId: 'session-1',
        status: 'joined',
        expiresIn: 500,
        receiverPk: 'pk-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(read().phase, SenderCodePhase.idle);
    expect(read().code, isNull);
    expect(data.attachedKey, isNull);
    expect(data.cancelCalls, 1);
  });
}
