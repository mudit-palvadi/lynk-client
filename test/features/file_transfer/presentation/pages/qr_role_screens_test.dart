import 'package:client/core/providers/receiver_notifier.dart';
import 'package:client/core/widgets/ad_banner_widget.dart';
import 'package:client/features/file_receive/domain/entities/receiver_session.dart';
import 'package:client/features/file_receive/presentation/pages/receive_qr_screen.dart';
import 'package:client/features/file_transfer/domain/entities/transfer.dart';
import 'package:client/features/file_transfer/presentation/pages/send_qr_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/sender_code_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = '0123456789abcdef0123456789abcdef';
const _transfer = Transfer(
  id: 'transfer-1',
  status: TransferStatus.ready,
  totalFiles: 1,
  totalSize: 48,
  files: [],
  accessToken: 'test-token',
);

void main() {
  group('role-aware QR screens', () {
    Future<_Upload> pump(
      WidgetTester tester,
      Widget screen, {
      UploadState upload = const UploadState(),
      double textScale = 1,
    }) async {
      SharedPreferences.setMockInitialValues({
        'ads_enabled': false,
        'ads_free_until_ms': DateTime.now()
            .add(const Duration(minutes: 15))
            .millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = _Upload(upload);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            uploadProvider.overrideWith(() => notifier),
            senderCodeProvider.overrideWith(_SenderCode.new),
            receiverProvider.overrideWith(_Receiver.new),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      );
      await tester.pump();
      return notifier;
    }

    testWidgets('the sender QR teaches the receiver action, not delivery', (
      tester,
    ) async {
      await pump(
        tester,
        const SendQrScreen(transfer: _transfer, aesKey: _key),
        upload: const UploadState(
          phase: UploadPhase.completed,
          transfer: _transfer,
          aesKey: _key,
        ),
      );
      expect(find.text('Let the receiver scan this'), findsOneWidget);
      expect(
        find.text('On their device: Receive → Scan sender’s QR.'),
        findsOneWidget,
      );
      expect(find.text('Or ask them to enter this code.'), findsOneWidget);
      expect(find.text('Ready to receive'), findsOneWidget);
      expect(find.textContaining('Delivered'), findsNothing);
      await _expectQrPayload(
        tester,
        'https://lynkshare.app/send/transfer-1#$_key&a=test-token',
      );
      expect(find.byType(AdBannerWidget), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the receiver QR explains both roles and automatic receiving', (
      tester,
    ) async {
      await pump(tester, const ReceiveQrScreen());
      expect(find.text('Your receiving QR'), findsOneWidget);
      expect(find.text('Ask the sender to scan this'), findsOneWidget);
      expect(find.text('Sender: scan this QR in LynkShare.'), findsOneWidget);
      expect(find.text('Sender: choose files and send.'), findsOneWidget);
      expect(
        find.text(
          'You: keep this screen open. Receiving starts automatically.',
        ),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveQrScreen)),
      );
      expect(
        (container.read(receiverProvider.notifier) as _Receiver).creates,
        1,
      );
      await _expectQrPayload(
        tester,
        'https://lynkshare.app/receive/receiver-1#pk=public-key',
      );
      expect(find.byType(AdBannerWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('direct waiting is not described as uploaded or delivered', (
      tester,
    ) async {
      await pump(
        tester,
        const SendQrScreen(transfer: _transfer, aesKey: _key),
        upload: const UploadState(
          phase: UploadPhase.uploading,
          transferMode: TransferMode.p2p,
          p2pStage: P2PSendStage.waitingForReceiver,
          transfer: _transfer,
          aesKey: _key,
        ),
      );
      expect(find.text('Waiting for receiver to scan...'), findsOneWidget);
      expect(find.text('Keep this screen open'), findsOneWidget);
      expect(find.text('Ready to receive'), findsNothing);
      expect(find.textContaining('Delivered'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'direct completion says sent without promising receiver storage',
      (tester) async {
        await pump(
          tester,
          const SendQrScreen(transfer: _transfer, aesKey: _key),
          upload: const UploadState(
            phase: UploadPhase.completed,
            transferMode: TransferMode.p2p,
            transfer: _transfer,
            aesKey: _key,
          ),
        );
        expect(find.text('Files sent'), findsOneWidget);
        expect(find.text('Ready to receive'), findsNothing);
        expect(find.textContaining('Delivered'), findsNothing);
        expect(find.textContaining('saved'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final size in [const Size(320, 568), const Size(640, 320)]) {
      for (final sender in [true, false]) {
        testWidgets(
          '${sender ? 'Sender' : 'Receiver'} QR at $size supports 2x text and reachable cancel',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await pump(
              tester,
              sender
                  ? const SendQrScreen(transfer: _transfer, aesKey: _key)
                  : const ReceiveQrScreen(),
              textScale: 2,
              upload: const UploadState(
                phase: UploadPhase.completed,
                transfer: _transfer,
                aesKey: _key,
              ),
            );
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Cancel Session'));
            expect(tester.takeException(), isNull);
            if (sender) {
              await tester.ensureVisible(find.text('Scan their receiving QR'));
            } else {
              await tester.pump(const Duration(seconds: 2));
              final container = ProviderScope.containerOf(
                tester.element(find.byType(ReceiveQrScreen)),
              );
              expect(
                (container.read(receiverProvider.notifier) as _Receiver)
                    .creates,
                1,
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  });
}

Future<void> _expectQrPayload(WidgetTester tester, String payload) async {
  // QrImageView keeps its input private. Compare the actual painter's output
  // with the expected payload rather than relying on private package fields.
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(QrImageView),
      matching: find.byType(CustomPaint),
    ),
  );
  await tester.runAsync(() async {
    final actual = await (paint.painter! as QrPainter).toImageData(220);
    final expected = await QrPainter(
      data: payload,
      version: QrVersions.auto,
      gapless: true,
    ).toImageData(220);
    expect(
      actual!.buffer.asUint8List(),
      orderedEquals(expected!.buffer.asUint8List()),
    );
  });
}

class _Upload extends UploadNotifier {
  _Upload(this.initial);
  final UploadState initial;
  @override
  UploadState build() => initial;
}

class _SenderCode extends SenderCodeNotifier {
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

class _Receiver extends ReceiverNotifier {
  int creates = 0;
  @override
  ReceiverState build() => const ReceiverState();
  @override
  Future<void> createSession() async {
    creates++;
    state = const ReceiverState(
      session: ReceiverSession(
        id: 'receiver-1',
        status: ReceiverSessionStatus.waiting,
      ),
      receiverPublicKeyB64: 'public-key',
    );
  }
}
