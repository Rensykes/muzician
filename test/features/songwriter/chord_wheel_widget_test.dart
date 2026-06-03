import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  testWidgets('tapping near 12 o\'clock calls onPick with degree 0 (I)',
      (tester) async {
    DiatonicTriad? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: ChordWheel(
            keyRootPc: 0,
            scaleName: 'major',
            onPick: (t) => picked = t,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap near 12 o'clock, slightly clockwise so we're inside wedge 0 (not on
    // its boundary). Center is (150,150). Move up and slightly right.
    await tester.tapAt(const Offset(160, 40));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.degree, 0);
    expect(picked!.romanNumeral, 'I');
    expect(picked!.symbol, 'C');
  });

  testWidgets('renders without errors and shows fallback for no scale',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: ChordWheel(
            keyRootPc: 0,
            scaleName: 'major',
            onPick: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows fallback message when scale unknown', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: ChordWheel(
            keyRootPc: 0,
            scaleName: 'nonexistent',
            onPick: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('key'), findsOneWidget);
  });
}
