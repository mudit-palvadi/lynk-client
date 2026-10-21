import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:client/features/recent_transfers/data/models/recent_transfer_record_model.dart';
import 'package:client/features/recent_transfers/domain/entities/recent_transfer_record.dart';
import 'package:client/features/recent_transfers/presentation/providers/recent_transfers_notifier.dart';
import 'package:client/features/recent_transfers/presentation/widgets/recent_transfers_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(recentTransferTitle(['a.bin', 'b.bin', 'c.bin']), 'a.bin + 2 files');
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
    }) => RecentTransferRecordModel(
      id: id,
      type: type,
      fileNames: fileNames,
      totalSize: 2048,
      timestamp: DateTime.now(),
      status: 'completed',
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RecentTransfersWidget()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
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
      await pumpWith(tester, [record('tx-1', ['only.jpg'])]);

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
  });
}
