import 'package:client/features/file_transfer/data/datasources/sender_session_remote_data_source.dart';
import 'package:dio/dio.dart';
import 'package:client/features/file_transfer/data/models/sender_session_model.dart';
import 'package:client/features/file_transfer/presentation/providers/sender_pairing.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataSource implements SenderSessionRemoteDataSource {
  _FakeDataSource();

  bool createFails = false;
  bool attachFails = false;
  SenderSessionModel nextSession = const SenderSessionModel(
    sessionId: 'session-1',
    code: '123456',
    status: 'waiting',
    expiresIn: 600,
    senderSecret: 'sender-secret',
  );
  String? attachedSecret;
  int polls = 0;
  String? attachedSession;
  String? attachedTransfer;
  String? attachedKey;
  String? attachedMode;

  @override
  Future<SenderSessionModel> createSession() async {
    if (createFails) throw Exception('boom');
    return nextSession;
  }

  @override
  Future<SenderSessionModel> getSession(String sessionId) async {
    polls++;
    return nextSession;
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
    if (attachFails) throw Exception('nope');
    attachedSession = sessionId;
    attachedTransfer = transferId;
    attachedKey = wrappedKey;
    attachedMode = mode;
    attachedSecret = senderSecret;
  }

  @override
  Future<void> cancelSession({
    required String sessionId,
    required String senderSecret,
  }) async {}
}

void main() {
  late _FakeDataSource data;
  late List<String> wrappedFor;
  late List<String?> wrappedTokens;

  SenderPairing build() => SenderPairing(
    dataSource: data,
    transferId: 'transfer-1',
    aesKey: 'key',
    accessToken: 'token-1',
    mode: 'p2p',
    wrapKey:
        ({
          required aesKey,
          required receiverPublicKeyB64,
          required sessionId,
          accessToken,
        }) async {
          wrappedFor.add(receiverPublicKeyB64);
          wrappedTokens.add(accessToken);
          return 'wrapped::$sessionId';
        },
  );

  setUp(() {
    data = _FakeDataSource();
    wrappedFor = [];
    wrappedTokens = [];
  });

  group('SenderPairing', () {
    test('mints the code and waits', () async {
      final pairing = build();

      expect(await pairing.start(), isTrue);
      expect(pairing.sessionId, 'session-1');
      expect(pairing.code, '123456');
      expect(pairing.status, SenderPairingStatus.waiting);
    });

    test('a failed create leaves nothing to show', () async {
      data.createFails = true;
      final pairing = build();

      expect(await pairing.start(), isFalse);
      expect(pairing.status, SenderPairingStatus.failed);
      expect(pairing.code, isNull);
    });

    test('polling without a receiver keeps waiting', () async {
      final pairing = build();
      await pairing.start();

      expect(await pairing.poll(), isTrue);
      expect(pairing.status, SenderPairingStatus.waiting);
      expect(data.polls, 1);
      expect(data.attachedKey, isNull);
    });

    test('a joined receiver gets the wrapped key and stops the poll', () async {
      final pairing = build();
      await pairing.start();
      data.nextSession = const SenderSessionModel(
        sessionId: 'session-1',
        status: 'joined',
        expiresIn: 500,
        receiverPk: 'pk-1',
      );

      expect(await pairing.poll(), isFalse);
      expect(pairing.isAttached, isTrue);
      expect(wrappedFor, ['pk-1']);
      expect(wrappedTokens, ['token-1']);
      expect(data.attachedSession, 'session-1');
      expect(data.attachedTransfer, 'transfer-1');
      expect(data.attachedKey, 'wrapped::session-1');
      expect(data.attachedMode, 'p2p');
      expect(data.attachedSecret, 'sender-secret');
      expect(pairing.receiverPublicKey, 'pk-1');
    });

    test('retiring during the wrap does not attach the key', () async {
      late SenderPairing pairing;
      pairing = SenderPairing(
        dataSource: data,
        transferId: 'transfer-1',
        aesKey: 'key',
        accessToken: 'token-1',
        mode: 'p2p',
        wrapKey:
            ({
              required aesKey,
              required receiverPublicKeyB64,
              required sessionId,
              accessToken,
            }) async {
              pairing.retire();
              return 'wrapped::$sessionId';
            },
      );
      await pairing.start();
      data.nextSession = const SenderSessionModel(
        sessionId: 'session-1',
        status: 'joined',
        expiresIn: 500,
        receiverPk: 'pk-1',
      );

      expect(await pairing.poll(), isFalse);
      expect(pairing.isAttached, isFalse);
      expect(data.attachedKey, isNull);
    });

    test('an attach that fails is reported', () async {
      final pairing = build();
      await pairing.start();
      data.attachFails = true;
      data.nextSession = const SenderSessionModel(
        sessionId: 'session-1',
        status: 'joined',
        expiresIn: 500,
        receiverPk: 'pk-1',
      );

      expect(await pairing.poll(), isFalse);
      expect(pairing.status, SenderPairingStatus.failed);
      expect(pairing.error, isNotNull);
    });

    test('polling after attaching does nothing', () async {
      final pairing = build();
      await pairing.start();
      data.nextSession = const SenderSessionModel(
        sessionId: 'session-1',
        status: 'joined',
        expiresIn: 500,
        receiverPk: 'pk-1',
      );
      await pairing.poll();

      expect(await pairing.poll(), isFalse);
      expect(data.polls, 1);
    });
  });
}
