import 'package:client/core/widgets/scrollable_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpFill(
    WidgetTester tester, {
    required Size size,
    required List<Widget> children,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScrollableFill(children: children)),
      ),
    );
  }

  testWidgets('fills the viewport so the spacers still centre the content', (
    tester,
  ) async {
    await pumpFill(
      tester,
      size: const Size(360, 800),
      children: const [
        SizedBox(height: 40, child: Text('top')),
        Spacer(),
        SizedBox(height: 40, child: Text('bottom')),
      ],
    );

    expect(tester.takeException(), isNull);
    // 24 dp of padding, then the first block.
    expect(tester.getTopLeft(find.text('top')).dy, 24.0);
    // The last block sits on the bottom padding instead of following the
    // first one, which is what the spacers are there for.
    expect(tester.getTopLeft(find.text('bottom')).dy, 736.0);
  });

  testWidgets('scrolls instead of overflowing when the content is taller', (
    tester,
  ) async {
    await pumpFill(
      tester,
      size: const Size(360, 480),
      children: const [
        SizedBox(height: 400, child: Text('top')),
        Spacer(),
        SizedBox(height: 100, child: Text('bottom')),
      ],
    );

    expect(tester.takeException(), isNull);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // 400 + 100 + 48 of padding in a 480 dp body.
    expect(position.maxScrollExtent, 68.0);

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    // The last block is reachable, which a clipped Column did not allow.
    expect(tester.getRect(find.text('bottom')).bottom, 456.0);
  });
}
