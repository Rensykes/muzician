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
                  Container(key: keyA, width: 80, height: 40),
                  Container(key: keyB, width: 80, height: 40),
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
                Container(key: keyA, width: 80, height: 40),
                Container(key: keyC, width: 80, height: 40),
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
}
