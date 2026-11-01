import 'dart:io';

import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/features/recent_transfers/data/models/recent_transfer_record_model.dart';
import 'package:client/features/recent_transfers/domain/entities/recent_transfer_record.dart';
import 'package:client/features/recent_transfers/presentation/providers/recent_transfers_notifier.dart';
import 'package:client/features/recent_transfers/presentation/widgets/recent_transfers_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int mb = 1024 * 1024;

/// A transfer that was cancelled or interrupted can end up in the history with
/// no file names at all. The card used to read the first name without checking
/// it, so one such record threw while the card was being built. Because the
/// cards live in a list, the failed one was drawn in place as an error panel
/// while its neighbours kept rendering - which looked like a broken screen
/// rather than one bad entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recentTransferTitle', () {
    test('a single file shows just its name', () {
      expect(recentTransferTitle(['photo.jpg']), 'photo.jpg');
    });

    test('several files show the first name and a count', () {
      expect(
        recentTransferTitle(['a.bin', 'b.bin', 'c.bin']),
        'a.bin + 2 files',
      );
    });

    test('no file names fall back to a safe label', () {
      expect(recentTransferTitle([]), 'No files');
    });
  });

  group('RecentTransfersWidget', () {
    late SharedPreferences mockPrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockPrefs = await SharedPreferences.getInstance();
    });

    RecentTransferRecordModel record(
      String id,
      List<String> fileNames, {
      RecentTransferType type = RecentTransferType.sent,
      List<String>? filePaths,
    }) => RecentTransferRecordModel(
      id: id,
      type: type,
      fileNames: fileNames,
      totalSize: 2048,
      timestamp: DateTime.now(),
      status: 'completed',
      filePaths: filePaths,
    );

    Future<ProviderContainer> pumpWith(
      WidgetTester tester,
      List<RecentTransferRecord> records,
    ) async {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );
      addTearDown(container.dispose);

      for (final item in records) {
        await container.read(recentTransfersProvider.notifier).addRecord(item);
      }

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: RecentTransfersWidget()),
          ),
          GoRoute(
            path: '/upload',
            builder: (_, _) => const Scaffold(body: Text('Upload route')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// Taps Re-send and waits for the real file checks to stage or refuse the
    /// batch before the test's temporary files are cleaned up.
    Future<void> tapResend(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.runAsync(() async {
        await tester.tap(find.text('Re-send'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (container.read(uploadProvider).phase == UploadPhase.idle &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
    }

    testWidgets('a record with no file names does not break the list', (
      tester,
    ) async {
      await pumpWith(tester, [
        record('tx-1', ['first.jpg']),
        record('tx-2', []),
        record('tx-3', ['last.jpg']),
      ]);

      // The card is built while the list is laid out, so a throw here would
      // be reported against the whole widget.
      expect(tester.takeException(), isNull);

      // The broken entry gets a label instead of taking the list down.
      expect(find.text('No files'), findsOneWidget);
      // And its neighbours are still on screen.
      expect(find.text('first.jpg'), findsOneWidget);
      expect(find.text('last.jpg'), findsOneWidget);
    });

    testWidgets('a single file shows its name and a file count', (
      tester,
    ) async {
      await pumpWith(tester, [
        record('tx-1', ['only.jpg']),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('only.jpg'), findsOneWidget);
      expect(find.textContaining('Sent'), findsOneWidget);
    });

    testWidgets('several files show the first name and a count', (
      tester,
    ) async {
      await pumpWith(tester, [
        record('tx-1', ['a.bin', 'b.bin', 'c.bin']),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('a.bin + 2 files'), findsOneWidget);
    });

    testWidgets('re-send over the total-size tier is refused like a pick', (
      tester,
    ) async {
      final directory = await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('lynk-resend-size-');
        await File(
          '${dir.path}/big.bin',
        ).writeAsBytes(List<int>.filled(16 * mb, 0));
        return dir;
      });
      addTearDown(() => directory!.delete(recursive: true));

      final container = await pumpWith(tester, [
        record('tx-1', ['big.bin'], filePaths: ['${directory!.path}/big.bin']),
      ]);

      await tapResend(tester, container);

      final state = container.read(uploadProvider);
      expect(state.selectedFiles, isEmpty);
      expect(state.phase, UploadPhase.failed);
      expect(state.errorMessage, contains('15 MB'));
      expect(state.errorMessage, contains('Watch an ad to unlock'));
    });

    testWidgets('re-send with more than ten files is refused like a pick', (
      tester,
    ) async {
      final paths = await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('lynk-resend-count-');
        return [
          for (var i = 0; i < 11; i++)
            (await File('${dir.path}/f$i.txt').writeAsString('x')).path,
        ];
      });
      addTearDown(() async {
        await Directory(File(paths!.first).parent.path).delete(recursive: true);
      });

      final container = await pumpWith(tester, [
        record('tx-1', [
          for (var i = 0; i < 11; i++) 'f$i.txt',
        ], filePaths: paths),
      ]);

      await tapResend(tester, container);

      final state = container.read(uploadProvider);
      expect(state.selectedFiles, isEmpty);
      expect(state.phase, UploadPhase.failed);
      expect(state.errorMessage, contains('10 files'));
    });

    testWidgets('a valid re-send stages the original files', (tester) async {
      final path = await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('lynk-resend-valid-');
        final file = File('${dir.path}${Platform.pathSeparator}note.txt');
        await file.writeAsString('hello');
        return file.path;
      });
      addTearDown(() => File(path!).parent.delete(recursive: true));

      final container = await pumpWith(tester, [
        record('tx-1', ['note.txt'], filePaths: [path!]),
      ]);

      await tapResend(tester, container);

      final state = container.read(uploadProvider);
      expect(state.phase, UploadPhase.selecting);
      expect(state.selectedFiles.single.name, 'note.txt');
      expect(state.selectedFiles.single.path, path);
      expect(find.text('Upload route'), findsOneWidget);
    });
  });
}
