import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Seeds a section with an empty harmony lane (so the bar grid renders) and a
  /// save lane holding [block]. Returns the save block id.
  String seed(ProviderContainer container, SongBlock block) {
    final n = container.read(songwriterProvider.notifier);
    n.setKey(0, 'major'); // C major
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.harmony, label: 'Harmony');
    final saveLaneId =
        n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Saves');
    n.insertBlock(sectionId: sectionId, laneId: saveLaneId, block: block);
    return block.id;
  }

  testWidgets('save cell shows roman numeral detected from saved notes',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Fretboard save with NO pendingChord — F major triad notes only.
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 15,
      capo: 0,
      selectedCells: const [],
      selectedNotes: const ['F', 'A', 'C'],
      viewMode: FretboardViewMode.exact,
    );
    final blockId = seed(
      container,
      SongBlock(
        id: 'save1',
        startBar: 0,
        spanBars: 2,
        embedded: snapshot,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // F major in C major → IV, rendered in the standalone save cell.
    expect(find.byKey(Key('saveRoman_${blockId}_0')), findsOneWidget);
    expect(find.text('IV'), findsOneWidget);
  });

  testWidgets('save cell omits roman numeral for a non-diatonic chord',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // F# major triad — non-diatonic in C major → no roman.
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 15,
      capo: 0,
      selectedCells: const [],
      selectedNotes: const ['F#', 'A#', 'C#'],
      viewMode: FretboardViewMode.exact,
    );
    final blockId = seed(
      container,
      SongBlock(
        id: 'save2',
        startBar: 0,
        spanBars: 2,
        embedded: snapshot,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(Key('saveRoman_${blockId}_0')), findsNothing);
  });
}
