import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/presentation/pages/send_qr_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/sender_code_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUploadNotifier extends UploadNotifier {
  _FakeUploadNotifier(this._state);

  final UploadState _state;

  @override
  UploadState build() => _state;
}

class _FakeSenderCodeNotifier extends SenderCodeNotifier {
  @override
  SenderCodeState build() => const SenderCodeState(
    phase: SenderCodePhase.waiting,
    code: '123456',
    transferId: 'transfer-1',
  );

  @override
  Future<void> ensureStarted({
    required String transferId,
    required String aesKey,
    String? accessToken,
    required TransferMode mode,
  }) async {}

  @override
  void stop() {}
}

void main() {
  testWidgets('a short phone can scroll down to Cancel Session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final transfer = Transfer(
      id: 'transfer-1',
      status: TransferStatus.ready,
      totalFiles: 3,
      totalSize: 6 * 1024 * 1024,
      createdAt: DateTime.now(),
      files: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uploadProvider.overrideWith(
            () => _FakeUploadNotifier(UploadState(transfer: transfer)),
          ),
          senderCodeProvider.overrideWith(_FakeSenderCodeNotifier.new),
        ],
        child: MaterialApp(
          home: SendQrScreen(transfer: transfer, aesKey: 'k' * 32),
        ),
      ),
    );
    await tester.pump();

    // The QR, code, expiry and actions do not fit in a 640 dp phone, so the
    // screen has to scroll rather than clip the bottom button.
    expect(tester.takeException(), isNull);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(
      tester.getRect(find.text('Cancel Session')).bottom,
      greaterThan(640),
    );

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final cancel = tester.getRect(find.text('Cancel Session'));
    expect(cancel.top, greaterThanOrEqualTo(0));
    expect(cancel.bottom, lessThanOrEqualTo(640));

    // Let the screen's one-second timer be cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the extend button is hidden while a direct transfer is running', (
    tester,
  ) async {
    final transfer = Transfer(
      id: 'transfer-1',
      status: TransferStatus.ready,
      totalFiles: 1,
      totalSize: 1024,
      createdAt: DateTime.now(),
      files: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uploadProvider.overrideWith(
            () => _FakeUploadNotifier(
              UploadState(
                transfer: transfer,
                transferMode: TransferMode.p2p,
                p2pStage: P2PSendStage.transferring,
              ),
            ),
          ),
          senderCodeProvider.overrideWith(_FakeSenderCodeNotifier.new),
        ],
        child: MaterialApp(
          home: SendQrScreen(transfer: transfer, aesKey: 'k' * 32),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Extend Session to 30 Mins (Watch Ad)'),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the extend button is offered while waiting for the receiver', (
    tester,
  ) async {
    final transfer = Transfer(
      id: 'transfer-1',
      status: TransferStatus.ready,
      totalFiles: 1,
      totalSize: 1024,
      createdAt: DateTime.now(),
      files: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uploadProvider.overrideWith(
            () => _FakeUploadNotifier(
              UploadState(
                transfer: transfer,
                transferMode: TransferMode.p2p,
                p2pStage: P2PSendStage.waitingForReceiver,
              ),
            ),
          ),
          senderCodeProvider.overrideWith(_FakeSenderCodeNotifier.new),
        ],
        child: MaterialApp(
          home: SendQrScreen(transfer: transfer, aesKey: 'k' * 32),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Extend Session to 30 Mins (Watch Ad)'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
