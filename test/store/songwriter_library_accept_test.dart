// test/store/songwriter_library_accept_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(saveSystemProvider.notifier);
    return c;
  }

  ({String sectionId, String harmonyLaneId, String harmonyBlockId})
      seedSong(ProviderContainer c) {
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'hb1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );
    return (sectionId: s, harmonyLaneId: l, harmonyBlockId: 'hb1');
  }

  String seedExistingSave(ProviderContainer c) {
    final saves = c.read(saveSystemProvider.notifier);
    final folderId = saves.createSaveFolder('Other folder', null)!;
    return saves.saveSnapshot(
      'Existing C voicing',
      folderId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    )!;
  }

  test('accept inserts a save-lane block referencing the existing saveId; '
      'no new SaveEntry created', () {
    final c = freshContainer();
    final ids = seedSong(c);
    final existingSaveId = seedExistingSave(c);
    final saveCountBefore = c.read(saveSystemProvider).saves.length;

    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          saveId: existingSaveId,
        );

    final saveCountAfter = c.read(saveSystemProvider).saves.length;
    expect(saveCountAfter, saveCountBefore,
        reason: 'acceptLibraryMatch must NOT create a new SaveEntry');

    final section = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId);
    final saveLane = section.lanes.firstWhere(
      (l) => l.kind == SongLaneKind.save,
    );
    expect(saveLane.blocks.single.saveId, existingSaveId);
    expect(saveLane.blocks.single.startBar, 0);
    expect(saveLane.blocks.single.spanBars, 2);
  });

  test('second accept at overlapping bars is silently rejected by '
      'blocksOverlap; no second block created', () {
    final c = freshContainer();
    final ids = seedSong(c);
    final existingSaveId = seedExistingSave(c);

    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          saveId: existingSaveId,
        );
    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: ids.harmonyBlockId,
          saveId: existingSaveId,
        );

    final saveLane = c
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save);
    expect(saveLane.blocks.length, 1,
        reason: 'overlap rejection is silent; only the first block lands');
  });

  test('missing harmony block: silent no-op', () {
    final c = freshContainer();
    final ids = seedSong(c);
    final existingSaveId = seedExistingSave(c);
    final initialSnapshot = c.read(songwriterProvider);

    c.read(songwriterProvider.notifier).acceptLibraryMatch(
          sectionId: ids.sectionId,
          harmonyBlockId: 'nope',
          saveId: existingSaveId,
        );

    expect(c.read(songwriterProvider), initialSnapshot,
        reason: 'missing block must leave songwriter state untouched');
  });

  group('save-lane anchoring', () {
    test('accept from a secondary harmony block anchors to that lane; '
        'same-bar saves for two lanes land in separate save lanes', () {
      final c = freshContainer();
      final ids = seedSong(c);
      final n = c.read(songwriterProvider.notifier);
      // Second harmony lane with a chord on the same bars.
      n.addLane(sectionId: ids.sectionId, kind: SongLaneKind.harmony);
      final lane2 = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .last
          .id;
      n.addHarmonyBlock(
        sectionId: ids.sectionId,
        laneId: lane2,
        block: const SongBlock(
          id: 'hb2', startBar: 0, spanBars: 2,
          chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
        ),
      );
      final saveId = seedExistingSave(c);

      // Accept on the primary block, then on the secondary block (same bars).
      n.acceptLibraryMatch(
        sectionId: ids.sectionId,
        harmonyBlockId: ids.harmonyBlockId,
        saveId: saveId,
      );
      n.acceptLibraryMatch(
        sectionId: ids.sectionId,
        harmonyBlockId: 'hb2',
        saveId: saveId,
      );

      final saveLanes = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .where((l) => l.kind == SongLaneKind.save)
          .toList();
      expect(saveLanes, hasLength(2));
      expect(saveLanes[0].anchorLaneId, ids.harmonyLaneId);
      expect(saveLanes[1].anchorLaneId, lane2);
      // Both placements landed despite sharing bars 0-2.
      expect(saveLanes[0].blocks.single.saveId, saveId);
      expect(saveLanes[1].blocks.single.saveId, saveId);
    });

    test('addLibraryBlockAt anchors to the given harmony lane', () {
      final c = freshContainer();
      final ids = seedSong(c);
      final n = c.read(songwriterProvider.notifier);
      n.addLane(sectionId: ids.sectionId, kind: SongLaneKind.harmony);
      final lane2 = c.read(songwriterProvider).sections.single.lanes.last.id;
      final saveId = seedExistingSave(c);

      n.addLibraryBlockAt(
        sectionId: ids.sectionId,
        saveId: saveId,
        startBar: 4,
        anchorLaneId: lane2,
      );

      final saveLane = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((l) => l.kind == SongLaneKind.save);
      expect(saveLane.anchorLaneId, lane2);
      expect(saveLane.blocks.single.startBar, 4);
    });
  });
}
