import 'dart:typed_data';

import 'package:client/core/providers/code_receiver_notifier.dart';
import 'package:client/core/providers/receiver_providers.dart';
import 'package:client/core/services/key_wrap_service.dart';
import 'package:client/features/file_receive/data/datasources/code_session_remote_data_source.dart';
import 'package:client/features/file_receive/data/models/code_session_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataSource implements CodeSessionRemoteDataSource {
  _FakeDataSource();

  Object? joinError;
  ReceiverCodeJoinModel joinResponse = const ReceiverCodeJoinModel(
    sessionId: 'session-1',
    status: 'joined',
    expiresIn: 600,
  );

  /// One entry per poll; a null entry means "not wrapped yet".
  List<ReceiverCodeKeyModel?> polls = <ReceiverCodeKeyModel?>[];

  int joinCalls = 0;
  int collectCalls = 0;

  @override
  Future<ReceiverCodeJoinModel> join({
    required String code,
    required String receiverPk,
  }) async {
    joinCalls++;
    if (joinError != null) throw joinError!;
    return joinResponse;
  }

  @override
  Future<ReceiverCodeKeyModel?> collectKey(String sessionId) async {
    collectCalls++;
    if (polls.isEmpty) return null;
    return polls.removeAt(0);
  }
}

class _FakeKeyWrap extends KeyWrapService {
  _FakeKeyWrap();

  String? unwrappedFor;

  @override
  Future<ReceiverKeyPair> generateReceiverKeyPair() async {
    return ReceiverKeyPair(publicKeyB64: 'pk-1', privateKeySeed: Uint8List(32));
  }

  @override
  Future<UnwrappedDelivery> unwrapDelivery({
    required String wrappedBase64,
    required List<int> privateKeySeed,
    required String sessionId,
  }) async {
    unwrappedFor = wrappedBase64;
    return const UnwrappedDelivery(aesKey: 'aes-1', accessToken: 'token-1');
  }
}

void main() {
  late _FakeDataSource data;
  late _FakeKeyWrap wrap;
  late ProviderContainer container;

  CodeReceiveState read() => container.read(codeReceiverProvider);
  CodeReceiverNotifier notifier() =>
      container.read(codeReceiverProvider.notifier);

  setUp(() {
    data = _FakeDataSource();
    wrap = _FakeKeyWrap();
    container = ProviderContainer(
      overrides: [
        codeSessionRemoteDataSourceProvider.overrideWith((ref) => data),
        keyWrapServiceProvider.overrideWith((ref) => wrap),
      ],
    );
    container.listen(codeReceiverProvider, (_, _) {});
    notifier().pollInterval = Duration.zero;
  });

  tearDown(() => container.dispose());

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 50 && !condition(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(condition(), isTrue, reason: 'state never reached the expectation');
  }

  test('a code is joined with a fresh receiver key', () async {
    await notifier().joinWithCode(' 123456 ');

    expect(data.joinCalls, 1);
    expect(read().sessionId, 'session-1');
    expect(read().isWaiting, isTrue);
    expect(read().errorMessage, isNull);
  });

  test('a wrapped cloud key arrives as a server download', () async {
    data.polls = [
      const ReceiverCodeKeyModel(
        transferId: 'transfer-1',
        wrappedKey: 'wrapped-1',
        mode: 'cloud',
        expiresIn: 500,
      ),
    ];

    await notifier().joinWithCode('123456');
    await waitFor(() => read().isReady);

    expect(wrap.unwrappedFor, 'wrapped-1');
    expect(read().transferId, 'transfer-1');
    expect(read().aesKey, 'aes-1');
    expect(read().accessToken, 'token-1');
    expect(read().viaPairing, isTrue);
    expect(read().isWaiting, isFalse);
  });

  test('a p2p key keeps the direct channel open first', () async {
    data.polls = [
      const ReceiverCodeKeyModel(
        transferId: 'transfer-1',
        wrappedKey: 'wrapped-1',
        mode: 'p2p',
        expiresIn: 500,
      ),
    ];

    await notifier().joinWithCode('123456');
    await waitFor(() => read().isReady);

    expect(read().viaPairing, isFalse);
  });

  test('polling continues until the sender wraps the key', () async {
    data.polls = [
      null,
      null,
      const ReceiverCodeKeyModel(
        transferId: 'transfer-1',
        wrappedKey: 'wrapped-1',
        expiresIn: 500,
      ),
    ];

    await notifier().joinWithCode('123456');
    await waitFor(() => read().isReady);

    expect(data.collectCalls, 3);
    expect(read().transferId, 'transfer-1');
  });

  test('an unknown code is reported and stops the wait', () async {
    data.joinError = DioException(
      requestOptions: RequestOptions(path: 'sender-sessions/join'),
      response: Response(
        requestOptions: RequestOptions(path: 'sender-sessions/join'),
        statusCode: 404,
      ),
    );

    await notifier().joinWithCode('000000');

    expect(read().isJoining, isFalse);
    expect(read().isWaiting, isFalse);
    expect(read().errorMessage, 'That code is not valid or has expired.');
  });

  test('a code that is already paired is reported', () async {
    data.joinError = DioException(
      requestOptions: RequestOptions(path: 'sender-sessions/join'),
      response: Response(
        requestOptions: RequestOptions(path: 'sender-sessions/join'),
        statusCode: 409,
      ),
    );

    await notifier().joinWithCode('123456');

    expect(
      read().errorMessage,
      'That code is already paired with another device.',
    );
  });

  test('an expired code never starts polling', () async {
    data.joinResponse = const ReceiverCodeJoinModel(
      sessionId: 'session-1',
      status: 'joined',
      expiresIn: 0,
    );

    await notifier().joinWithCode('123456');

    expect(read().transferId, isNull);
    expect(read().errorMessage, contains('expired'));
    expect(data.collectCalls, 0);
  });

  test('cancelling forgets the session', () async {
    await notifier().joinWithCode('123456');
    notifier().cancel();

    expect(read().sessionId, isNull);
    expect(read().isWaiting, isFalse);
  });
}
