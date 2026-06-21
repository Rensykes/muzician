import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  testWidgets('renders a single lyric input prefilled with currentLyric',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                await showHarmonyChordSheet(
                  ctx,
                  startBar: 0,
                  spanBars: 1,
                  keyRoot: 0,
                  keyScaleName: 'major',
                  instanceIndex: 2,
                  currentLyric: 'verse 3 lyric',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lyricInput')), findsOneWidget);
    final TextField field = tester.widget(find.byKey(const Key('lyricInput')));
    expect(field.controller!.text, 'verse 3 lyric');
    // Label should mention the instance for clarity.
    expect(find.textContaining('Verse 3'), findsOneWidget);
  });

  testWidgets('silent toggle returns a silent block with the typed lyric',
      (tester) async {
    SongBlock? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showHarmonyChordSheet(
                  ctx,
                  startBar: 1,
                  spanBars: 1,
                  keyRoot: 0,
                  keyScaleName: 'major',
                  instanceIndex: 0,
                  currentLyric: '',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('silentToggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lyricInput')), 'oh');
    await tester.tap(find.byKey(const Key('confirmSilent')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isSilent, isTrue);
    expect(result!.chordSymbol, isNull);
    expect(result!.lyrics, ['oh']); // single-entry list
    expect(result!.startBar, 1);
  });
}
