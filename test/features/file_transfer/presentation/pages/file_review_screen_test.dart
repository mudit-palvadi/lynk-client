import 'package:client/core/widgets/ad_banner_widget.dart';
import 'package:client/features/file_transfer/presentation/pages/file_upload_screen.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

UploadState _selection() => UploadState(
  phase: UploadPhase.selecting,
  selectedFiles: [PlatformFile(name: 'notes.txt', size: 24)],
);

void main() {
  group('file review', () {
    Future<_Upload> pump(
      WidgetTester tester, {
      UploadState upload = const UploadState(),
      double textScale = 1,
      String? receiverId,
      String? receiverPk,
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
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: FileUploadScreen(
              attachToSessionId: receiverId,
              receiverPk: receiverPk,
            ),
          ),
        ),
      );
      await tester.pump();
      return notifier;
    }

    testWidgets('choose files before explaining transport choices', (
      tester,
    ) async {
      final upload = await pump(tester);
      expect(find.text('Choose what to send'), findsOneWidget);
      expect(
        find.text('Pick files first. Next, choose how to share them.'),
        findsOneWidget,
      );
      expect(find.text('Send directly'), findsNothing);
      await tester.tap(find.text('Choose Files & Media'));
      expect(upload.pickCalls, 1);
      expect(find.byType(AdBannerWidget), findsOneWidget);
    });

    testWidgets('review names and remove a file before choosing how to send', (
      tester,
    ) async {
      final upload = await pump(tester, upload: _selection());
      expect(find.text('Review your files'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('How would you like to send?'), findsOneWidget);
      expect(find.text('Share a code'), findsOneWidget);
      expect(find.text('Send directly'), findsOneWidget);
      expect(find.text('Cloud • 10-minute session'), findsOneWidget);
      expect(
        find.text('Both devices stay open • Cloud fallback'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Add More Files'));
      await tester.tap(find.text('Add More Files'));
      expect(upload.pickCalls, 1);
      await tester.ensureVisible(find.byTooltip('Remove notes.txt'));
      await tester.tap(find.byTooltip('Remove notes.txt'));
      await tester.pump();
      expect(find.text('Choose what to send'), findsOneWidget);
    });

    testWidgets('a scanned receiver QR is explained without a direct promise', (
      tester,
    ) async {
      await pump(
        tester,
        receiverId: 'receiver-1',
        receiverPk: 'public-key',
        upload: _selection(),
      );
      expect(find.text('Receiver linked'), findsOneWidget);
      expect(
        find.text(
          'You scanned their receiving QR. Choose files to send to them.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Delivered'), findsNothing);
    });

    for (final mode in TransferMode.values) {
      testWidgets('$mode action keeps mode and paired receiver arguments', (
        tester,
      ) async {
        final upload = await pump(
          tester,
          upload: _selection(),
          receiverId: 'receiver-1',
          receiverPk: 'public-key',
        );
        final label = mode == TransferMode.cloud
            ? 'Share a code'
            : 'Send directly';
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(upload.starts, 1);
        expect(upload.current.transferMode, mode);
        expect(upload.sessionId, 'receiver-1');
        expect(upload.receiverPk, 'public-key');
        expect(upload.current.selectedFiles.single.name, 'notes.txt');
      });
    }

    testWidgets('file review remains usable on a small phone at 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, upload: _selection(), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Send directly'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Add More Files'));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'upload progress and failure retain recovery actions without banners',
      (tester) async {
        await pump(
          tester,
          upload: _selection().copyWith(
            phase: UploadPhase.uploading,
            overallProgress: 0.5,
          ),
        );
        expect(find.text('50.0%'), findsOneWidget);
        expect(find.text('Cancel Transfer'), findsOneWidget);
        expect(find.byType(AdBannerWidget), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await pump(
          tester,
          upload: _selection().copyWith(
            phase: UploadPhase.failed,
            errorMessage: 'Test failure',
          ),
        );
        expect(find.text('Test failure'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.byType(AdBannerWidget), findsNothing);
      },
    );
  });
}

class _Upload extends UploadNotifier {
  _Upload(this.initial);
  final UploadState initial;
  int pickCalls = 0;
  int starts = 0;
  String? sessionId;
  String? receiverPk;
  UploadState get current => state;
  @override
  UploadState build() => initial;
  @override
  Future<void> pickFiles() async => pickCalls++;
  @override
  Future<void> startUpload({
    String? attachToSessionId,
    String? receiverPk,
  }) async {
    starts++;
    sessionId = attachToSessionId;
    this.receiverPk = receiverPk;
  }
}
