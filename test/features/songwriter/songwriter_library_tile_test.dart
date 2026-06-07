import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_block_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tap → Library tab → card → save-lane block inserted; '
      'no new SaveEntry', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    final saves = container.read(saveSystemProvider.notifier);

    n.setProjectName('Song A');
    n.setKey(0, 'major');
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l =
        container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );

    // Seed an existing save inside the project folder so library-match finds it.
    final projectFolderId = saves.createSaveFolder('Song A', null)!;
    final existingSaveId = saves.saveSnapshot(
      'Existing C voicing',
      projectFolderId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
        pendingChord: const PendingChord(
            symbol: 'C', root: 'C', quality: ''),
      ),
    )!;
    final savesCountBefore = container.read(saveSystemProvider).saves.length;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320, height: 44,
            child: SongwriterBlockTile(
              sectionId: s,
              laneId: l,
              blockId: 'hb1',
              barWidth: 40,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('block_hb1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('libraryCard_$existingSaveId')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(saveSystemProvider).saves.length,
        savesCountBefore,
        reason: 'no new SaveEntry created');

    final section = container
        .read(songwriterProvider)
        .sections
        .firstWhere((sec) => sec.id == s);
    final saveLane = section.lanes.firstWhere(
      (la) => la.kind == SongLaneKind.save,
    );
    expect(saveLane.blocks.single.saveId, existingSaveId);
  });
}
