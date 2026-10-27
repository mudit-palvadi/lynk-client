import 'package:client/core/services/file_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_notifier.dart';
import 'package:client/features/file_transfer/presentation/providers/upload_state.dart';

class FakeFilePickerService implements FilePickerService {
  FilePickerResult? nextResult;

  @override
  Future<FilePickerResult?> pickFiles({bool allowMultiple = true}) async =>
      nextResult;

  @override
  Future<FilePickerResult?> pickMedia({bool allowMultiple = true}) async =>
      nextResult;
}

const int mb = 1024 * 1024;

PlatformFile fileOf(String name, int bytes) =>
    PlatformFile(name: name, size: bytes);

void main() {
  group('UploadState', () {
    test('initial state has empty selectedFiles and idle phase', () {
      const state = UploadState();
      expect(state.selectedFiles, isEmpty);
      expect(state.phase, UploadPhase.idle);
      expect(state.totalSize, 0);
    });

    test('totalSize calculates total byte size correctly', () {
      final state = UploadState(
        selectedFiles: [
          PlatformFile(name: 'a.txt', size: 100),
          PlatformFile(name: 'b.jpg', size: 250),
        ],
      );
      expect(state.totalSize, 400);
    });

    test('cloud mode free tier max total is 15 MB', () {
      const state = UploadState();
      expect(state.maxTotalSize, 15 * mb);
    });

    test('cloud mode unlocked tier max total is 30 MB', () {
      const state = UploadState(isSizeLimitUnlocked: true);
      expect(state.maxTotalSize, 30 * mb);
    });

    test('p2p mode free tier max total is 20 MB', () {
      const state = UploadState(transferMode: TransferMode.p2p);
      expect(state.maxTotalSize, 20 * mb);
    });

    test('p2p mode unlocked tier max total is 50 MB', () {
      const state = UploadState(
        transferMode: TransferMode.p2p,
        isSizeLimitUnlocked: true,
      );
      expect(state.maxTotalSize, 50 * mb);
    });

    test('the unlock hint advertises the unlocked tier, not the free tier', () {
      // The hint shown next to the "watch an ad" button has to name the tier
      // the ad buys, otherwise it would say "unlock up to 15 MB" while the
      // unlocked limit is 30 MB.
      const cloud = UploadState();
      expect(cloud.maxTotalSizeMb, 15);
      expect(cloud.maxTotalSizeFreeMb, 15);
      expect(cloud.maxTotalSizeUnlockedMb, 30);

      const p2p = UploadState(transferMode: TransferMode.p2p);
      expect(p2p.maxTotalSizeMb, 20);
      expect(p2p.maxTotalSizeFreeMb, 20);
      expect(p2p.maxTotalSizeUnlockedMb, 50);
    });
  });

  group('UploadNotifier', () {
    test('removeFile removes file at index and updates phase', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([
        PlatformFile(name: 'a.txt', size: 100),
        PlatformFile(name: 'b.jpg', size: 200),
      ]);

      expect(container.read(uploadProvider).selectedFiles.length, 2);

      notifier.removeFile(0);

      final state = container.read(uploadProvider);
      expect(state.selectedFiles.length, 1);
      expect(state.selectedFiles.first.name, 'b.jpg');
      expect(state.phase, UploadPhase.selecting);
    });

    test('removeFile resets phase to idle when all files are removed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([PlatformFile(name: 'a.txt', size: 100)]);

      notifier.removeFile(0);

      final state = container.read(uploadProvider);
      expect(state.selectedFiles, isEmpty);
      expect(state.phase, UploadPhase.idle);
    });

    test('cancelUpload returns to the file selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(uploadProvider.notifier);
      notifier.setFilesForTesting([PlatformFile(name: 'a.txt', size: 100)]);
      notifier.cancelUpload();

      final state = container.read(uploadProvider);
      expect(state.phase, UploadPhase.selecting);
      expect(state.selectedFiles.single.name, 'a.txt');
      expect(state.overallProgress, 0);
      expect(state.transfer, isNull);
      expect(state.errorMessage, isNull);
    });
  });

  group(
    'UploadNotifier size tier enforcement (cloud 20->50MB, p2p 10->200MB)',
    () {
      late FakeFilePickerService fakePicker;

      ProviderContainer makeContainer() {
        fakePicker = FakeFilePickerService();
        return ProviderContainer(
          overrides: [filePickerServiceProvider.overrideWithValue(fakePicker)],
        );
      }

      test(
        'cloud free tier: total over 15 MB is rejected with unlock hint',
        () async {
          final container = makeContainer();
          addTearDown(container.dispose);

          fakePicker.nextResult = FilePickerResult([
            fileOf('a.bin', 15 * mb),
            fileOf('b.bin', 10 * mb),
          ]);

          final notifier = container.read(uploadProvider.notifier);
          await notifier.pickFiles();

          final state = container.read(uploadProvider);
          expect(state.phase, UploadPhase.failed);
          expect(state.errorMessage, contains('15 MB'));
          // The hint must name the unlocked tier the ad buys.
          expect(state.errorMessage, contains('30 MB'));
        },
      );

      test('cloud unlocked tier: up to 30 MB total is accepted', () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(uploadProvider.notifier);
        notifier.unlockExtendedSizeLimit();
        fakePicker.nextResult = FilePickerResult([fileOf('big.bin', 25 * mb)]);
        await notifier.pickFiles();

        expect(container.read(uploadProvider).phase, UploadPhase.selecting);
      });

      test(
        'p2p unlocked tier: 40 MB total accepted (above cloud ceiling)',
        () async {
          final container = makeContainer();
          addTearDown(container.dispose);

          final notifier = container.read(uploadProvider.notifier);
          notifier.setTransferMode(TransferMode.p2p);
          notifier.unlockExtendedSizeLimit();
          fakePicker.nextResult = FilePickerResult([fileOf('v.mp4', 40 * mb)]);
          await notifier.pickFiles();

          expect(container.read(uploadProvider).phase, UploadPhase.selecting);
        },
      );

      test('p2p free tier rejects 30 MB (above the 20 MB p2p limit)', () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(uploadProvider.notifier);
        notifier.setTransferMode(TransferMode.p2p);
        fakePicker.nextResult = FilePickerResult([fileOf('v.mp4', 30 * mb)]);
        await notifier.pickFiles();

        expect(container.read(uploadProvider).phase, UploadPhase.failed);
        expect(container.read(uploadProvider).errorMessage, contains('20 MB'));
      });

      test(
        'pickMedia respects the free-tier gate (no ad-unlock bypass)',
        () async {
          final container = makeContainer();
          addTearDown(container.dispose);

          fakePicker.nextResult = FilePickerResult([
            fileOf('movie.mp4', 30 * mb),
          ]);

          final notifier = container.read(uploadProvider.notifier);
          await notifier.pickMedia(); // locked state -> cloud free tier 15 MB

          final state = container.read(uploadProvider);
          expect(state.phase, UploadPhase.failed);
          expect(state.errorMessage, contains('15 MB'));
        },
      );

      test(
        'pickMedia preserves size-limit unlocked state after picking',
        () async {
          final container = makeContainer();
          addTearDown(container.dispose);

          final notifier = container.read(uploadProvider.notifier);
          notifier.unlockExtendedSizeLimit();
          fakePicker.nextResult = FilePickerResult([
            fileOf('clip.mp4', 5 * mb),
          ]);
          await notifier.pickMedia();

          final state = container.read(uploadProvider);
          expect(state.isSizeLimitUnlocked, isTrue);
          expect(state.phase, UploadPhase.selecting);
        },
      );
    },
  );

  group('UploadNotifier appends picks instead of replacing the selection', () {
    late FakeFilePickerService fakePicker;

    ProviderContainer makeContainer() {
      fakePicker = FakeFilePickerService();
      return ProviderContainer(
        overrides: [filePickerServiceProvider.overrideWithValue(fakePicker)],
      );
    }

    test('a fifth file is added to the four already selected', () async {
      // The reported bug: four files picked, then one more, and the four
      // disappeared because the picker result replaced the selection.
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(uploadProvider.notifier);

      fakePicker.nextResult = FilePickerResult([
        fileOf('a.txt', 10),
        fileOf('b.txt', 10),
        fileOf('c.txt', 10),
        fileOf('d.txt', 10),
      ]);
      await notifier.pickFiles();

      fakePicker.nextResult = FilePickerResult([fileOf('e.txt', 10)]);
      await notifier.pickFiles();

      final state = container.read(uploadProvider);
      expect(state.selectedFiles.map((f) => f.name).toList(), [
        'a.txt',
        'b.txt',
        'c.txt',
        'd.txt',
        'e.txt',
      ]);
      expect(state.phase, UploadPhase.selecting);
    });

    test('pickMedia appends to what pickFiles staged', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(uploadProvider.notifier);

      fakePicker.nextResult = FilePickerResult([fileOf('doc.pdf', 10)]);
      await notifier.pickFiles();

      fakePicker.nextResult = FilePickerResult([fileOf('clip.mp4', 10)]);
      await notifier.pickMedia();

      expect(
        container
            .read(uploadProvider)
            .selectedFiles
            .map((f) => f.name)
            .toList(),
        ['doc.pdf', 'clip.mp4'],
      );
    });

    test('eleven files are refused whole and the staged six stay', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(uploadProvider.notifier);

      fakePicker.nextResult = FilePickerResult([
        for (var i = 0; i < 6; i++) fileOf('f$i.txt', 10),
      ]);
      await notifier.pickFiles();

      fakePicker.nextResult = FilePickerResult([
        for (var i = 0; i < 5; i++) fileOf('g$i.txt', 10),
      ]);
      await notifier.pickFiles();

      final state = container.read(uploadProvider);
      expect(state.selectedFiles.length, 6);
      expect(state.selectedFiles.first.name, 'f0.txt');
      expect(state.phase, UploadPhase.selecting);
      expect(state.notice, contains('10 files'));
      expect(state.noticeSeq, 1);
      expect(state.errorMessage, isNull);
    });

    test('exactly ten files are accepted', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(uploadProvider.notifier);

      fakePicker.nextResult = FilePickerResult([
        for (var i = 0; i < 10; i++) fileOf('f$i.txt', 10),
      ]);
      await notifier.pickFiles();

      final state = container.read(uploadProvider);
      expect(state.selectedFiles.length, 10);
      expect(state.phase, UploadPhase.selecting);
      expect(state.notice, isNull);
    });

    test('the byte budget covers the combined selection', () async {
      // 8 MB + 8 MB is over the 15 MB cloud free tier even though each pick
      // fits on its own, so the second batch is refused and the first stays.
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(uploadProvider.notifier);

      fakePicker.nextResult = FilePickerResult([fileOf('a.bin', 8 * mb)]);
      await notifier.pickFiles();

      fakePicker.nextResult = FilePickerResult([fileOf('b.bin', 8 * mb)]);
      await notifier.pickFiles();

      final state = container.read(uploadProvider);
      expect(state.selectedFiles.map((f) => f.name).toList(), ['a.bin']);
      expect(state.phase, UploadPhase.selecting);
      expect(state.notice, contains('15 MB'));
    });

    test(
      'an empty selection still raises the failed view and its dialog',
      () async {
        // The first pick cannot keep anything, so the unlock flow needs the
        // failed phase exactly as before.
        final container = makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(uploadProvider.notifier);

        fakePicker.nextResult = FilePickerResult([fileOf('big.bin', 16 * mb)]);
        await notifier.pickFiles();

        final state = container.read(uploadProvider);
        expect(state.phase, UploadPhase.failed);
        expect(state.errorMessage, contains('Watch an ad to unlock'));
        expect(notifier.hasRejectedFiles, isTrue);
      },
    );

    test('the refused batch is re-run after the unlock', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(uploadProvider.notifier);

      fakePicker.nextResult = FilePickerResult([fileOf('big.bin', 16 * mb)]);
      await notifier.pickFiles();
      expect(container.read(uploadProvider).phase, UploadPhase.failed);

      notifier.unlockExtendedSizeLimit();
      expect(notifier.retryRejectedSelection(), isTrue);

      final state = container.read(uploadProvider);
      expect(state.selectedFiles.map((f) => f.name).toList(), ['big.bin']);
      expect(state.phase, UploadPhase.selecting);
      expect(notifier.hasRejectedFiles, isFalse);
    });
  });
}
