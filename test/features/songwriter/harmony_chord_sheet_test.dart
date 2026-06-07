import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';

void main() {
  testWidgets('picking C major via manual picker returns a harmony block',
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
                keyRoot: null,
                keyScaleName: null,
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
    expect(result!.romanNumeral, isNull);
  });

  testWidgets('shows chord wheel when key is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyChordSheet(
              context,
              startBar: 0,
              spanBars: 2,
              keyRoot: 0,
              keyScaleName: 'major',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordWheel), findsOneWidget);
  });

  testWidgets('manual picker behind Other chord expander commits with key',
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

    // Expand the Other chord section to reveal the manual picker.
    await tester.tap(find.text('Other chord'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('harmonyRoot_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.chordRootPc, 0);
    expect(result!.chordNotes, contains('C'));
    // Roman numeral is derived from the key context (C major key, C chord = I).
    expect(result!.romanNumeral, 'I');
  });

  testWidgets('shows root+quality grid when no key is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyChordSheet(
              context,
              startBar: 0,
              spanBars: 2,
              keyRoot: null,
              keyScaleName: null,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordWheel), findsNothing);
    expect(find.text('Root'), findsOneWidget);
  });
}
