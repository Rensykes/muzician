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
}
