import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/features/songwriter/songwriter_lane_row.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('picking a save from the palette adds a save block',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'Guitar');
    final l = container.read(songwriterProvider).sections.single.lanes.single.id;

    // Seed a visible fretboard save inside a folder.
    final ss = container.read(saveSystemProvider.notifier);
    final folderId = ss.createSaveFolder('F', null);
    ss.saveSnapshot(
      'Riff',
      folderId!,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SongwriterLaneRow(sectionId: s, laneId: l)),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600)); // drain debounce
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('addBlock_$l')));
    await tester.pumpAndSettle();
    // Navigate into the folder, then pick the save.
    await tester.tap(find.text('F'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riff'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600)); // drain debounce

    final blocks =
        container.read(songwriterProvider).sections.single.lanes.single.blocks;
    expect(blocks.length, 1);
    expect(blocks.single.saveId, isNotNull);
  });
}
