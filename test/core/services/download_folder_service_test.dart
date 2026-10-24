import 'package:client/core/services/download_folder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DownloadFolderService.channelName);
  const tree =
      'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FLynk';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a tree uri reads as a folder path', () {
    expect(DownloadFolderService.displayName(tree), 'Download / Lynk');
  });

  test('a child document uri still names its folder', () {
    expect(
      DownloadFolderService.displayName('$tree/document/primary%3ADownload%2FLynk'),
      'Download / Lynk',
    );
  });

  test('an unfamiliar uri is not shown as a broken path', () {
    expect(DownloadFolderService.displayName('content://example'), 'Chosen folder');
  });

  test('common file types get a mime type the system can open', () {
    expect(DownloadFolderService.mimeTypeFor('report.pdf'), 'application/pdf');
    expect(DownloadFolderService.mimeTypeFor('Photo.JPG'), 'image/jpeg');
    expect(DownloadFolderService.mimeTypeFor('archive.zip'), 'application/zip');
    expect(
      DownloadFolderService.mimeTypeFor('mystery.bin'),
      'application/octet-stream',
    );
  });

  test('choosing a folder remembers it', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickFolder') return tree;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = DownloadFolderService();
    expect(await service.treeUri(), isNull);

    final picked = await service.choose();

    expect(picked, tree);
    expect(await service.treeUri(), tree);
  });

  test('cancelling the picker keeps the old folder', () async {
    SharedPreferences.setMockInitialValues({
      'lynk_download_tree_uri': tree,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(await DownloadFolderService().choose(), isNull);
    expect(await DownloadFolderService().treeUri(), tree);
  });

  test('publishing sends the folder, the file and its mime type', () async {
    SharedPreferences.setMockInitialValues({
      'lynk_download_tree_uri': tree,
    });
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return '$tree/document/primary%3ADownload%2FLynk%2Freport.pdf';
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final published = await DownloadFolderService().publish(
      sourcePath: '/cache/report.pdf',
      fileName: 'report.pdf',
    );

    expect(published, contains('report.pdf'));
    expect(seen?.method, 'publish');
    final args = seen!.arguments as Map<Object?, Object?>;
    expect(args['treeUri'], tree);
    expect(args['sourcePath'], '/cache/report.pdf');
    expect(args['mimeType'], 'application/pdf');
  });

  test('a download without a chosen folder is not published', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await DownloadFolderService().publish(
        sourcePath: '/cache/a.txt',
        fileName: 'a.txt',
      ),
      isNull,
    );
    expect(calls, 0);
  });
}
