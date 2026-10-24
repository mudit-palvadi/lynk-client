import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/onboarding/presentation/widgets/home_coach_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GlobalKey firstKey;
  late GlobalKey secondKey;
  late int finished;

  setUp(() {
    firstKey = GlobalKey();
    secondKey = GlobalKey();
    finished = 0;
  });

  Future<void> pumpTour(
    WidgetTester tester, {
    List<HomeCoachMarkStep>? steps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // The app theme's full-width buttons are part of what this widget has
        // to survive, so the test uses the real theme.
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                children: [
                  const SizedBox(height: 80),
                  Container(
                    key: firstKey,
                    height: 90,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 40),
                  Container(
                    key: secondKey,
                    height: 90,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 400),
                ],
              ),
              Positioned.fill(
                child: HomeCoachMarks(
                  steps:
                      steps ??
                      [
                        HomeCoachMarkStep(
                          targetKey: firstKey,
                          title: 'Send a file',
                          description: 'Pick files and share them.',
                        ),
                        HomeCoachMarkStep(
                          targetKey: secondKey,
                          title: 'Scan to receive',
                          description: 'Point the camera at a QR code.',
                        ),
                      ],
                  onFinished: () => finished++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the first step explains the first control', (tester) async {
    await pumpTour(tester);

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Send a file'), findsOneWidget);
    expect(find.text('Scan to receive'), findsNothing);
  });

  testWidgets('Next walks forward and Back returns', (tester) async {
    await pumpTour(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Scan to receive'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Send a file'), findsOneWidget);
  });

  testWidgets('the last step finishes the tour', (tester) async {
    await pumpTour(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pump();

    expect(finished, 1);
  });

  testWidgets('Skip ends the tour without walking it', (tester) async {
    await pumpTour(tester);

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(finished, 1);
  });

  testWidgets('finishing twice does not report twice', (tester) async {
    await pumpTour(tester);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    // The overlay may still be on screen for one frame until the parent
    // rebuilds; a second tap must not call back again.
    await tester.tap(find.text('Skip'), warnIfMissed: false);
    await tester.pump();

    expect(finished, 1);
  });

  testWidgets('a tour with no steps draws nothing', (tester) async {
    await pumpTour(tester, steps: const []);

    expect(find.text('Skip'), findsNothing);
    expect(find.textContaining('of'), findsNothing);
  });
}
