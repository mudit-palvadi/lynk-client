import 'package:client/features/file_receive/presentation/pages/enter_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the code field scrolls clear of the keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    // The field autofocuses, so the keyboard takes the bottom of the body.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EnterCodeScreen())),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    // The body ends at 320 dp; the action has to fit above that.
    final receive = tester.getRect(
      find.widgetWithText(ElevatedButton, 'Receive Files'),
    );
    expect(receive.bottom, lessThanOrEqualTo(320));

    // The blinking cursor keeps a timer alive, so unmount before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
