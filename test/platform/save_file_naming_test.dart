import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Saving into the folder the user picked goes through the native `publish`
/// method, which used to hand the sender's name straight to
/// `DocumentsContract.createDocument`. Two files with the same name then
/// landed on one document and the first was lost (#74).
///
/// A Kotlin unit test needs the Android test runtime, which this project does
/// not run in CI, so the contract is asserted against the source: the names of
/// the parent's existing children are read before a document is created.
void main() {
  final activity = File(
    'android/app/src/main/kotlin/app/xynix/lynk/MainActivity.kt',
  ).readAsStringSync();

  /// The body of `fun <name>(...)`, braces included.
  String functionBody(String name) {
    final start = activity.indexOf('fun $name(');
    expect(start, isNot(-1), reason: 'MainActivity.kt no longer defines $name');
    final open = activity.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < activity.length; i++) {
      if (activity[i] == '{') depth++;
      if (activity[i] == '}') {
        depth--;
        if (depth == 0) return activity.substring(open, i + 1);
      }
    }
    fail('$name has no closing brace');
  }

  test('publish picks a unique name before it creates the document', () {
    final publish = functionBody('publish');
    final checked = publish.indexOf('uniqueChildName(');
    final created = publish.indexOf('createDocument(');

    expect(checked, isNot(-1), reason: 'publish must check the folder first');
    expect(created, isNot(-1));
    expect(
      checked,
      lessThan(created),
      reason: 'the existing children must be read before createDocument',
    );
    expect(
      publish,
      contains('uniqueName,'),
      reason: 'the checked name must be the one createDocument receives',
    );
  });

  test('the existing child display names are queried from the parent', () {
    final lookup = functionBody('existingChildNames');

    expect(lookup, contains('buildChildDocumentsUriUsingTree('));
    expect(lookup, contains('DocumentsContract.Document.COLUMN_DISPLAY_NAME'));
    expect(
      lookup,
      contains('parentId'),
      reason: 'the children of the parent document are the ones that matter',
    );
  });

  test('a null cursor or a failed query falls back to the original name', () {
    final lookup = functionBody('existingChildNames');
    final unique = functionBody('uniqueChildName');

    expect(
      unique,
      contains('?: return desired'),
      reason: 'a folder that cannot be listed must still receive the file',
    );
    expect(lookup, contains('catch'));
    expect(lookup, contains('return null'));
  });

  test('a repeated name gets a counter before the extension', () {
    final unique = functionBody('uniqueChildName');

    expect(unique, contains(r'" ($index)$extension"'));
    expect(
      unique,
      contains('ignoreCase = true'),
      reason: 'the shared folder may not tell names apart by case',
    );
  });
}
