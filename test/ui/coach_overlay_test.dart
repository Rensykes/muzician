import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/ui/core/coach_overlay.dart';

void main() {
  testWidgets('tour shows steps, advances, and dismisses', (tester) async {
    final keyA = GlobalKey();
    final keyB = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Column(
                children: [
                  SizedBox(key: keyA, width: 80, height: 40),
                  SizedBox(key: keyB, width: 80, height: 40),
                  ElevatedButton(
                    onPressed: () => startCoachTour(context, [
                      CoachStep(key: keyA, title: 'First', body: 'Step one'),
                      CoachStep(key: keyB, title: 'Second', body: 'Step two'),
                    ]),
                    child: const Text('go'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('a step with an unmounted key is skipped', (tester) async {
    final keyA = GlobalKey();
    final ghost = GlobalKey(); // never attached
    final keyC = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                SizedBox(key: keyA, width: 80, height: 40),
                SizedBox(key: keyC, width: 80, height: 40),
                ElevatedButton(
                  onPressed: () => startCoachTour(context, [
                    CoachStep(key: keyA, title: 'A', body: 'a'),
                    CoachStep(key: ghost, title: 'Ghost', body: 'g'),
                    CoachStep(key: keyC, title: 'C', body: 'c'),
                  ]),
                  child: const Text('go'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('C'), findsOneWidget);
    expect(find.text('Ghost'), findsNothing);
  });

  testWidgets('no-op when every key is unmounted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => startCoachTour(context, [
                CoachStep(key: GlobalKey(), title: 'X', body: 'x'),
              ]),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('X'), findsNothing);
  });

  testWidgets('card clears the top safe-area inset (Dynamic Island)',
      (tester) async {
    final topKey = GlobalKey();
    const islandInset = 59.0; // iPhone 17 Pro top padding

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 874),
            padding: EdgeInsets.only(top: islandInset, bottom: 34),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => Stack(
                children: [
                  // Target hugging the very top of the screen.
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SizedBox(key: topKey, width: 120, height: 30),
                  ),
                  Positioned(
                    bottom: 0,
                    child: ElevatedButton(
                      onPressed: () => startCoachTour(context, [
                        CoachStep(key: topKey, title: 'Top', body: 'near island'),
                      ]),
                      child: const Text('go'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    // The tooltip card must sit fully below the top inset.
    final cardTop = tester.getTopLeft(find.text('Top')).dy;
    expect(cardTop, greaterThanOrEqualTo(islandInset));
  });
}
