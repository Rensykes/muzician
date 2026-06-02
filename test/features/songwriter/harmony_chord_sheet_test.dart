import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';

void main() {
  testWidgets('picking C major returns a harmony block with notes + numeral',
      (tester) async {
    SongBlock? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showHarmonyChordSheet(
                context,
                startBar: 0,
                spanBars: 2,
                keyRoot: 0,
                keyScaleName: 'major',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('harmonyRoot_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.chordRootPc, 0);
    expect(result!.chordNotes, contains('C'));
    expect(result!.romanNumeral, 'I');
  });
}
