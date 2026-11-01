import 'dart:io';

import 'package:client/core/providers/download_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app-storage fallback keeps every received file in one `Lynk` folder.
/// A second file with the same name used to replace the first one, so the
/// naming decision is exercised here on a real directory instead of through
/// the Android platform channels the notifier normally uses.
void main() {
  late Directory sandbox;
  late Directory folder;
  late Directory sources;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('lynk-delivery-test');
    folder = Directory('${sandbox.path}/Lynk');
    sources = Directory('${sandbox.path}/staging');
    await sources.create();
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<String> source(String name, String contents) async {
    final file = File('${sources.path}/$name');
    await file.writeAsString(contents);
    return file.path;
  }

  Future<File> deliver(String name, String contents) async {
    final path = await source(name, contents);
    return deliverFileToFolder(
      folder: folder,
      sourcePath: path,
      fileName: name,
    );
  }

  test('the first file keeps its name', () async {
    final delivered = await deliver('note.txt', 'first');

    expect(delivered.path, '${folder.path}/note.txt');
    expect(delivered.readAsStringSync(), 'first');
  });

  test('the folder is created when it does not exist yet', () async {
    expect(folder.existsSync(), isFalse);

    await deliver('note.txt', 'first');

    expect(folder.existsSync(), isTrue);
  });

  test('a second file with the same name is kept beside the first', () async {
    final first = await deliver('note.txt', 'first');
    final second = await deliver('note.txt', 'second');

    expect(second.path, '${folder.path}/note (1).txt');
    expect(first.readAsStringSync(), 'first');
    expect(second.readAsStringSync(), 'second');
  });

  test('further files count up and none is lost', () async {
    final delivered = <File>[
      await deliver('note.txt', 'first'),
      await deliver('note.txt', 'second'),
      await deliver('note.txt', 'third'),
    ];

    expect(delivered.map((file) => file.path), [
      '${folder.path}/note.txt',
      '${folder.path}/note (1).txt',
      '${folder.path}/note (2).txt',
    ]);
    expect(delivered.map((file) => file.readAsStringSync()), [
      'first',
      'second',
      'third',
    ]);
  });

  test('the staged source is removed once the copy is delivered', () async {
    final path = await source('note.txt', 'first');

    final delivered = await deliverFileToFolder(
      folder: folder,
      sourcePath: path,
      fileName: 'note.txt',
    );

    expect(delivered.existsSync(), isTrue);
    expect(File(path).existsSync(), isFalse);
  });

  test('a different case is the same file on the folder', () async {
    await folder.create(recursive: true);
    await File('${folder.path}/Report.PDF').writeAsString('first');

    final delivered = await deliver('report.pdf', 'second');

    expect(delivered.path, '${folder.path}/report (1).pdf');
    expect(
      File('${folder.path}/Report.PDF').readAsStringSync(),
      'first',
      reason: 'the first file was replaced',
    );
  });

  test('unrelated files are left alone', () async {
    await folder.create(recursive: true);
    await File('${folder.path}/keep.txt').writeAsString('keep');

    final delivered = await deliver('note.txt', 'first');

    expect(delivered.path, '${folder.path}/note.txt');
    expect(File('${folder.path}/keep.txt').readAsStringSync(), 'keep');
  });
}
