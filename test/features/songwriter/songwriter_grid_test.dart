import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_grid.dart';

void main() {
  testWidgets('bar ruler renders a number per bar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BarRuler(lengthBars: 4, gutter: 72)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('playhead painter renders without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomPaint(
          size: const Size(200, 40),
          painter: PlayheadPainter(bar: 2, lengthBars: 8, color: Colors.cyan),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
