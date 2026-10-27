import 'package:client/core/errors/result.dart';
import 'package:client/core/providers/transfer_providers.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/domain/repositories/transfer_repository.dart';
import 'package:client/features/file_transfer/presentation/pages/send_qr_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/sender_code_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _transfer = Transfer(
  id: 'cancel-room',
  status: TransferStatus.ready,
  totalFiles: 1,
  totalSize: 32,
  files: [],
  senderSecret: 'test-sender-secret',
);

void main() {
  group('QR session cancellation', () {
    for (final scenario in [
      (
        'waiting Direct',
        TransferMode.p2p,
        UploadPhase.uploading,
        P2PSendStage.waitingForReceiver,
      ),
      (
        'streaming Direct',
        TransferMode.p2p,
        UploadPhase.uploading,
        P2PSendStage.transferring,
      ),
      (
        'active Cloud',
        TransferMode.cloud,
        UploadPhase.uploading,
        P2PSendStage.none,
      ),
      (
        'completed Cloud',
        TransferMode.cloud,
        UploadPhase.completed,
        P2PSendStage.none,
      ),
    ]) {
      testWidgets('${scenario.$1} cancels once with sender credentials', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({'ads_enabled': false});
        final prefs = await SharedPreferences.getInstance();
        final repository = _Repository();
        final upload = _Upload(
          UploadState(
            phase: scenario.$3,
            transferMode: scenario.$2,
            p2pStage: scenario.$4,
            transfer: _transfer,
            aesKey: '0123456789abcdef0123456789abcdef',
          ),
        );
        final router = GoRouter(
          initialLocation: '/send',
          routes: [
            GoRoute(
              path: '/send',
              builder: (_, _) => const SendQrScreen(transfer: _transfer),
            ),
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home restored')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              transferRepositoryProvider.overrideWithValue(repository),
              uploadProvider.overrideWith(() => upload),
              senderCodeProvider.overrideWith(_Code.new),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.ensureVisible(find.text('Cancel Session'));
        await tester.tap(find.text('Cancel Session'));
        await tester.pumpAndSettle();
        expect(repository.cancellations, [
          (id: 'cancel-room', secret: 'test-sender-secret'),
        ]);
        expect(find.text('Home restored'), findsOneWidget);
        expect(upload.current.phase, UploadPhase.idle);
        expect(upload.current.transfer, isNull);
        expect(upload.current.aesKey, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}

class _Upload extends UploadNotifier {
  _Upload(this.initial);
  final UploadState initial;
  UploadState get current => state;
  @override
  UploadState build() => initial;
}

class _Repository implements TransferRepository {
  final cancellations = <({String id, String? secret})>[];
  @override
  Future<Result<void>> cancelTransfer(
    String transferId, {
    String? senderSecret,
  }) async {
    cancellations.add((id: transferId, secret: senderSecret));
    return Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Code extends SenderCodeNotifier {
  @override
  SenderCodeState build() => const SenderCodeState();
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
