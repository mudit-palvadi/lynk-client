import 'dart:async';

import 'package:client/core/errors/failures.dart';
import 'package:client/core/errors/result.dart';
import 'package:client/core/providers/receiver_notifier.dart';
import 'package:client/core/providers/receiver_providers.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';
import 'package:client/features/file_receive/domain/repositories/receiver_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements ReceiverRepository {
  Completer<Result<ReceiverSession>>? pendingGet;

  @override
  Future<Result<ReceiverSession>> createReceiverSession() async {
    return Result.success(
      const ReceiverSession(
        id: 'session-1',
        status: ReceiverSessionStatus.waiting,
      ),
    );
  }

  @override
  Future<Result<ReceiverSession>> getReceiverSession(String sessionId) {
    final pending = Completer<Result<ReceiverSession>>();
    pendingGet = pending;
    return pending.future;
  }

  @override
  Future<Result<void>> attachTransfer({
    required String sessionId,
    required String transferId,
    String? wrappedKey,
  }) async {
    return Result.failure(const ServerFailure('unused'));
  }

  @override
  Future<Result<void>> cancelReceiverSession(String sessionId) async {
    return Result.failure(const ServerFailure('unused'));
  }
}

void main() {
  test('a poll that finishes after cancel does not open the download', () async {
    final repo = _Repo();
    final container = ProviderContainer(
      overrides: [receiverRepositoryProvider.overrideWith((ref) => repo)],
    );
    addTearDown(container.dispose);
    container.listen(receiverProvider, (_, _) {});
    final notifier = container.read(receiverProvider.notifier);
    notifier.pollDelayOverride = Duration.zero;

    await notifier.createSession();
    for (var i = 0; i < 20 && repo.pendingGet == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(repo.pendingGet, isNotNull);

    notifier.cancelSession();
    repo.pendingGet!.complete(
      Result.success(
        const ReceiverSession(
          id: 'session-1',
          status: ReceiverSessionStatus.attached,
          transferId: 'transfer-1',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(receiverProvider).attachedTransferId, isNull);
    expect(container.read(receiverProvider).session, isNull);
  });
}
