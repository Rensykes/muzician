import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_library_match_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

SaveEntry _save(String id, String name) => SaveEntry(
      id: id,
      name: name,
      folderId: 'f',
      snapshot: FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
      createdAt: 0,
      updatedAt: 0,
      order: 0,
    );

void main() {
  const block = SongBlock(
    id: 'hb', startBar: 0, spanBars: 2,
    chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
    chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
  );

  testWidgets('sheet has Voicings + Harmony + Library tabs', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: block,
              voicings: const [],
              thirdAbove: null,
              chordMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('Library tab shows empty state when no matches', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: block,
              voicings: const [],
              thirdAbove: null,
              chordMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No saved voicing matches'), findsOneWidget);
  });

  testWidgets('Library tab renders only chord-note matches; tap fires '
      'onAcceptLibrary with the right saveId', (tester) async {
    String? pickedId;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: block,
              voicings: const [],
              thirdAbove: null,
              chordMatches: [
                LibraryMatch(entry: _save('chord1', 'Chord A'),
                    kind: LibraryMatchKind.chord),
              ],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (id) => pickedId = id,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('Matches this chord'), findsOneWidget);
    expect(find.text('Fits this key'), findsNothing);

    await tester.tap(find.byKey(const Key('libraryCard_chord1')));
    await tester.pumpAndSettle();

    expect(pickedId, 'chord1');
  });
}
