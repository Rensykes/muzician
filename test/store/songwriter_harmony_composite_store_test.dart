import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart'
    show
        makeHarmonyBlock,
        makeSaveBlock,
        primaryHarmonyLane,
        saveAnchorLane,
        guitarStrumAnchorLane;
import 'package:muzician/schema/rules/songwriter_playback_rules.dart'
    show writerSaveBlockMidiNotes;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/fretboard_store.dart' show fretboardProvider;
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart'
    show songwriterSessionsProvider;
import 'package:muzician/store/writer_save_sync_store.dart'
    show
        WriterSaveSyncStorage,
        writerSaveSyncProvider,
        writerSaveSyncStorageProvider;
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingWriterSaveSyncStorage implements WriterSaveSyncStorage {
  final events = <String>[];

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<bool> write(String key, String value) async {
    events.add('write:$key');
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    events.add('remove:$key');
    return true;
  }
}

FretboardSnapshot _cMajorFretboard({
  FretboardInputMode inputMode = FretboardInputMode.chord,
}) => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [
    FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
    FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
    FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
    FretCoordinate(stringIndex: 3, fret: 2, noteName: 'E'),
    FretCoordinate(stringIndex: 4, fret: 3, noteName: 'C'),
    FretCoordinate(stringIndex: 5, fret: 3, noteName: 'G'),
  ],
  selectedNotes: const ['C', 'E', 'G'],
  viewMode: FretboardViewMode.exact,
  inputMode: inputMode,
);

FretboardSnapshot _dMajorFretboard() => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [
    FretCoordinate(stringIndex: 0, fret: 2, noteName: 'F#'),
    FretCoordinate(stringIndex: 1, fret: 3, noteName: 'D'),
    FretCoordinate(stringIndex: 2, fret: 2, noteName: 'A'),
  ],
  selectedNotes: const ['D', 'F#', 'A'],
  viewMode: FretboardViewMode.exact,
  inputMode: FretboardInputMode.chord,
);

PianoSnapshot _cMajorPiano() => PianoSnapshot(
  currentRange: PianoRangeName.key88,
  selectedKeys: const [
    PianoCoordinate(keyIndex: 39, midiNote: 60, noteName: 'C'),
    PianoCoordinate(keyIndex: 43, midiNote: 64, noteName: 'E'),
    PianoCoordinate(keyIndex: 46, midiNote: 67, noteName: 'G'),
  ],
  selectedNotes: const ['C', 'E', 'G'],
  viewMode: PianoViewMode.exact,
);

PianoSnapshot _dMajorPiano() => PianoSnapshot(
  currentRange: PianoRangeName.key88,
  selectedKeys: const [
    PianoCoordinate(keyIndex: 41, midiNote: 62, noteName: 'D'),
    PianoCoordinate(keyIndex: 45, midiNote: 66, noteName: 'F#'),
    PianoCoordinate(keyIndex: 48, midiNote: 69, noteName: 'A'),
  ],
  selectedNotes: const ['D', 'F#', 'A'],
  viewMode: PianoViewMode.exact,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({ProviderContainer container, String projectId, SongwriterNotifier writer})
  >
  makeProject({
    HarmonyLaneInstrument defaultInstrument = HarmonyLaneInstrument.piano,
    WriterSaveSyncStorage? syncStorage,
  }) async {
    final container = ProviderContainer(
      overrides: [
        if (syncStorage != null)
          writerSaveSyncStorageProvider.overrideWithValue(syncStorage),
      ],
    );
    addTearDown(container.dispose);
    final saves = container.read(saveSystemProvider.notifier);
    await saves.hydrate();
    final projectId = saves.createProject(
      'Harmony store test',
      ProjectConfig(defaultHarmonyInstrument: defaultInstrument),
    )!;
    saves.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    await writer.reconcileCurrentProject();
    return (container: container, projectId: projectId, writer: writer);
  }

  SongBlock chord({
    required String symbol,
    required int rootPc,
    required List<String> notes,
    required int startBar,
    int spanBars = 1,
  }) => makeHarmonyBlock(
    startBar: startBar,
    spanBars: spanBars,
    chordSymbol: symbol,
    chordQuality: '',
    chordRootPc: rootPc,
    chordNotes: notes,
  );

  HarmonyChordSnapshot pianoChord({
    required String symbol,
    required int rootPc,
    required List<String> notes,
    required List<int> midiNotes,
    required String pendingRoot,
  }) => HarmonyChordSnapshot(
    harmonyInstrument: HarmonyLaneInstrument.piano,
    writerBlock: WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      chordSymbol: symbol,
      chordQuality: '',
      chordRootPc: rootPc,
      chordNotes: notes,
    ),
    instrumentState: PianoSnapshot(
      currentRange: PianoRangeName.key88,
      selectedKeys: [
        for (final midiNote in midiNotes)
          PianoCoordinate(
            keyIndex: midiNote - 21,
            midiNote: midiNote,
            noteName: notes[midiNotes.indexOf(midiNote)],
          ),
      ],
      selectedNotes: notes,
      viewMode: PianoViewMode.exact,
      pendingChord: PendingChord(
        root: pendingRoot,
        quality: '',
        symbol: pendingRoot,
      ),
    ),
  );

  test('Add chord creates one linked Harmony composite Save', () async {
    final (:container, :projectId, :writer) = await makeProject();
    writer.addSection(label: 'Verse', lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final primary = section.lanes.single;
    expect(primary.harmonyInstrument, HarmonyLaneInstrument.piano);

    final result = writer.addHarmonyChord(
      sectionId: section.id,
      laneId: primary.id,
      block: chord(
        symbol: 'C',
        rootPc: 0,
        notes: const ['C', 'E', 'G'],
        startBar: 2,
        spanBars: 2,
      ),
      saveName: 'C',
    );
    await writer.reconcileCurrentProject();

    expect(result.success, isTrue);
    final savedSection = container.read(songwriterProvider).sections.single;
    expect(savedSection.lanes, hasLength(1));
    final lane = savedSection.lanes.single;
    expect(lane.kind, SongLaneKind.harmony);
    expect(lane.blocks, hasLength(1));
    final block = lane.blocks.single;
    expect(block.id, result.blockId);
    expect(block.saveId, isNotNull);

    final saves = container.read(saveSystemProvider);
    expect(saves.saves, hasLength(1));
    expect(saves.writerLinks, hasLength(1));
    final save = saves.saves.single;
    expect(save.id, block.saveId);
    expect(save.folderId, isNot(projectId));
    expect(save.origin, SaveOrigin.writer);
    expect(save.snapshot, isA<HarmonyChordSnapshot>());
    final composite = save.snapshot as HarmonyChordSnapshot;
    expect(composite.harmonyInstrument, HarmonyLaneInstrument.piano);
    expect(composite.instrumentState, isA<PianoSnapshot>());
    expect(composite.writerBlock.chordSymbol, 'C');
    expect(saves.writerLinks.single.blockId, block.id);
    expect(saves.writerLinks.single.saveId, save.id);
  });

  test(
    'failed Fretboard realization leaves Writer, saves, history, and journal unchanged',
    () async {
      final storage = _RecordingWriterSaveSyncStorage();
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
        syncStorage: storage,
      );
      container.read(fretboardProvider.notifier)
        ..setNumFrets(1)
        ..setCapo(1);
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      final result = writer.addHarmonyChord(
        sectionId: section.id,
        laneId: lane.id,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'Fsus4',
          chordQuality: 'sus4',
          chordRootPc: 5,
          chordNotes: const ['F', 'A#', 'C'],
        ),
      );
      expect(result.success, isTrue);
      await writer.reconcileCurrentProject();
      storage.events.clear();

      final projectBefore = container.read(songwriterProvider);
      final savesBefore = container.read(saveSystemProvider);
      final undoCountBefore = writer.undoCount;
      final revisionBefore = writer.historyRevision;
      final block = projectBefore.sections.single.lanes.single.blocks.single;
      final update = writer.updateHarmonyBlock(
        sectionId: section.id,
        laneId: lane.id,
        blockId: block.id,
        content: const SongBlock(
          id: 'editor-result',
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
        ),
      );

      expect(update, isFalse);
      expect(
        identical(container.read(songwriterProvider), projectBefore),
        isTrue,
      );
      expect(writer.undoCount, undoCountBefore);
      expect(writer.historyRevision, revisionBefore);
      expect(
        identical(container.read(saveSystemProvider), savesBefore),
        isTrue,
      );
      expect(container.read(saveSystemProvider).saves, hasLength(1));
      expect(container.read(saveSystemProvider).writerLinks, hasLength(1));
      expect(
        writer.lastHarmonyMutationError,
        contains('Adjust the tuning, capo, or fret range.'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(storage.events, isEmpty);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == block.saveId)
            .folderId,
        isNot(projectId),
      );
    },
  );

  test(
    'undoing section removal restores Harmony folder IDs and linked Save ownership',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      final result = writer.addHarmonyChord(
        sectionId: section.id,
        laneId: lane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 0,
        ),
      );
      expect(result.success, isTrue);
      await writer.reconcileCurrentProject();
      final originalState = container.read(saveSystemProvider);
      final originalRoot = originalState.folders.singleWhere(
        (folder) =>
            folder.writerSectionId == section.id &&
            folder.writerLaneKind == null,
      );
      final originalCategory = originalState.folders.singleWhere(
        (folder) =>
            folder.writerSectionId == section.id &&
            folder.writerLaneKind == SongLaneKind.harmony,
      );
      final originalBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      final saveId = originalBlock.saveId!;
      expect(
        originalState.saves.singleWhere((save) => save.id == saveId).folderId,
        originalCategory.id,
      );

      writer.removeSection(section.id);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(songwriterProvider).sections, isEmpty);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == saveId)
            .folderId,
        projectId,
      );
      expect(container.read(saveSystemProvider).writerLinks, isEmpty);

      expect(writer.undo(), isTrue);
      await Future<void>.delayed(Duration.zero);
      final restoredSaves = container.read(saveSystemProvider);
      expect(
        restoredSaves.folders.any((folder) => folder.id == originalRoot.id),
        isTrue,
      );
      expect(
        restoredSaves.folders.any((folder) => folder.id == originalCategory.id),
        isTrue,
      );
      expect(
        restoredSaves.saves.singleWhere((save) => save.id == saveId).folderId,
        originalCategory.id,
      );
      expect(restoredSaves.writerLinks, hasLength(1));
      expect(restoredSaves.writerLinks.single.blockId, originalBlock.id);
      expect(restoredSaves.writerLinks.single.folderId, originalCategory.id);
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .saveId,
        saveId,
      );
    },
  );

  test(
    'native Save placements must match their Harmony anchor instrument',
    () async {
      final project = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.piano,
      );
      final container = project.container;
      final writer = project.writer;
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final pianoLane = section.lanes.single;
      final fretboardSnapshot = _cMajorFretboard();

      final pianoSaveLane = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      final beforeRejectedPlacement = container.read(songwriterProvider);
      writer.addSaveBlock(
        sectionId: section.id,
        laneId: pianoSaveLane,
        snapshot: fretboardSnapshot,
        saveName: 'Fretboard C',
        startBar: 0,
        spanBars: 1,
      );

      expect(
        identical(container.read(songwriterProvider), beforeRejectedPlacement),
        isTrue,
      );
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .singleWhere((lane) => lane.id == pianoSaveLane)
            .blocks,
        isEmpty,
      );

      final fretboardLane = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      final fretboardSaveLane = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: fretboardSaveLane,
        harmonyLaneId: fretboardLane,
      );
      writer.addSaveBlock(
        sectionId: section.id,
        laneId: fretboardSaveLane,
        snapshot: fretboardSnapshot,
        saveName: 'Fretboard C',
        startBar: 0,
        spanBars: 1,
      );

      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: fretboardSaveLane,
        harmonyLaneId: pianoLane.id,
      );

      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .singleWhere((lane) => lane.id == fretboardSaveLane)
            .blocks,
        hasLength(1),
      );
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .singleWhere((lane) => lane.id == fretboardSaveLane)
            .anchorLaneId,
        fretboardLane,
      );
      expect(pianoLane.harmonyInstrument, HarmonyLaneInstrument.piano);
    },
  );

  test(
    'silent Harmony placeholders keep lyrics without creating a Save',
    () async {
      final (:container, :writer, projectId: _) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      writer.addSilentBlock(
        sectionId: section.id,
        laneId: lane.id,
        startBar: 2,
        spanBars: 2,
        verseCount: 1,
      );
      final placeholder = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      writer.setBlockLyric(
        sectionId: section.id,
        laneId: lane.id,
        blockId: placeholder.id,
        verseIndex: 0,
        text: 'Keep this lyric',
      );

      await writer.reconcileCurrentProject();

      final savedPlaceholder = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(savedPlaceholder.isSilent, isTrue);
      expect(savedPlaceholder.startBar, 2);
      expect(savedPlaceholder.spanBars, 2);
      expect(savedPlaceholder.lyrics, ['Keep this lyric']);
      expect(savedPlaceholder.saveId, isNull);
      expect(savedPlaceholder.embedded, isNull);
      expect(container.read(saveSystemProvider).saves, isEmpty);
      expect(container.read(saveSystemProvider).writerLinks, isEmpty);
    },
  );

  test(
    'making a linked chord silent leaves its composite Save unchanged',
    () async {
      final (:container, :writer, projectId: _) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: lane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 2,
        ),
      );
      await writer.reconcileCurrentProject();
      final chordBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      final originalSave = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == chordBlock.saveId);

      expect(
        writer.updateHarmonyBlock(
          sectionId: section.id,
          laneId: lane.id,
          blockId: chordBlock.id,
          content: const SongBlock(
            id: 'unused',
            startBar: 0,
            spanBars: 1,
            isSilent: true,
            lyrics: ['Preserved lyric'],
          ),
          lyricVerseIndex: 0,
        ),
        isTrue,
      );
      await writer.reconcileCurrentProject();

      final silentBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(silentBlock.isSilent, isTrue);
      expect(silentBlock.startBar, 2);
      expect(silentBlock.lyrics, ['Preserved lyric']);
      expect(silentBlock.saveId, isNull);
      expect(silentBlock.embedded, isNull);
      final saveState = container.read(saveSystemProvider);
      expect(
        saveState.saves
            .singleWhere((save) => save.id == originalSave.id)
            .toJson(),
        originalSave.toJson(),
      );
      expect(saveState.writerLinks, isEmpty);
    },
  );

  test(
    'duplicating a Harmony lane creates placements sharing Save IDs',
    () async {
      final (:container, :writer, projectId: _) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final originalLane = section.lanes.single;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: originalLane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 0,
        ),
      );
      await writer.reconcileCurrentProject();
      final original = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;

      final duplicateLaneId = await writer.duplicateHarmonyLane(
        sectionId: section.id,
        laneId: originalLane.id,
      );
      await writer.reconcileCurrentProject();

      final lanes = container.read(songwriterProvider).sections.single.lanes;
      expect(lanes, hasLength(2));
      final duplicate = lanes
          .singleWhere((lane) => lane.id == duplicateLaneId)
          .blocks
          .single;
      expect(duplicate.id, isNot(original.id));
      expect(duplicate.saveId, original.saveId);
      final links = container
          .read(saveSystemProvider)
          .writerLinks
          .where((link) => link.saveId == original.saveId)
          .toList();
      expect(links.map((link) => link.blockId).toSet(), {
        original.id,
        duplicate.id,
      });
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .where((save) => save.id == original.saveId),
        hasLength(1),
      );
    },
  );

  test(
    'Add chord rejection leaves Writer, Saves, and history untouched',
    () async {
      final (:container, :writer, projectId: _) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final beforeWriter = container.read(songwriterProvider);
      final beforeSaveSystem = container.read(saveSystemProvider);
      final beforeHistoryRevision = writer.historyRevision;

      final result = writer.addHarmonyChord(
        sectionId: section.id,
        laneId: section.lanes.single.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'D', 'G'],
          startBar: 0,
        ),
      );

      expect(result.success, isFalse);
      expect(
        identical(container.read(songwriterProvider), beforeWriter),
        isTrue,
      );
      expect(
        identical(container.read(saveSystemProvider), beforeSaveSystem),
        isTrue,
      );
      expect(writer.historyRevision, beforeHistoryRevision);
    },
  );

  test('reused Harmony Save keeps its ID and source entry unchanged', () async {
    final (:container, :projectId, :writer) = await makeProject();
    writer.addSection(label: 'Source', lengthBars: 8);
    final sourceSection = container.read(songwriterProvider).sections.single;
    writer.addHarmonyChord(
      sectionId: sourceSection.id,
      laneId: sourceSection.lanes.single.id,
      block: chord(
        symbol: 'C',
        rootPc: 0,
        notes: const ['C', 'E', 'G'],
        startBar: 0,
      ),
      saveName: 'Original source name',
    );
    await writer.reconcileCurrentProject();
    final sourceSave = container.read(saveSystemProvider).saves.single;
    final sourceJson = sourceSave.toJson();
    final beforeCount = container.read(saveSystemProvider).saves.length;

    writer.addSection(label: 'Destination', lengthBars: 8);
    final destination = container.read(songwriterProvider).sections.last;
    final inserted = writer.insertWriterBlockFromSave(
      saveId: sourceSave.id,
      sectionId: destination.id,
      laneKind: SongLaneKind.harmony,
      laneId: destination.lanes.single.id,
      startBar: 3,
      spanBars: 2,
      expectedProjectId: projectId,
    );
    expect(inserted, isTrue);
    await writer.reconcileCurrentProject();

    final after = container.read(saveSystemProvider);
    final destinationSection = container.read(songwriterProvider).sections.last;
    expect(destinationSection.lanes, hasLength(1));
    final block = destinationSection.lanes.single.blocks.single;
    expect(block.saveId, sourceSave.id);
    expect(block.startBar, 3);
    expect(block.spanBars, 2);
    expect(after.saves, hasLength(beforeCount));
    expect(after.saves.single.toJson(), sourceJson);
    expect(after.saves.single.name, 'Original source name');
    expect(after.writerLinks, hasLength(2));
    expect(
      after.writerLinks.map((link) => link.saveId),
      everyElement(sourceSave.id),
    );
    expect(
      container
          .read(songwriterProvider)
          .sections
          .expand((section) => section.lanes)
          .where((lane) => lane.kind == SongLaneKind.save),
      isEmpty,
    );
  });

  test(
    'Harmony reuse stages a matching lane and section only on commit',
    () async {
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      final saves = container.read(saveSystemProvider.notifier);
      final sourceSaveId = saves.saveSnapshot(
        'Piano chord source',
        projectId,
        pianoChord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          midiNotes: const [60, 64, 67],
          pendingRoot: 'C',
        ),
      )!;
      final sourceBefore = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == sourceSaveId)
          .toJson();
      final beforeWriter = container.read(songwriterProvider);
      final beforeSaveSystem = container.read(saveSystemProvider);
      final beforeHistoryRevision = writer.historyRevision;

      expect(
        writer.insertWriterBlockFromSave(
          saveId: sourceSaveId,
          sectionId: null,
          laneKind: SongLaneKind.harmony,
          startBar: 1,
          expectedProjectId: projectId,
        ),
        isFalse,
      );
      expect(
        identical(container.read(songwriterProvider), beforeWriter),
        isTrue,
      );
      expect(
        identical(container.read(saveSystemProvider), beforeSaveSystem),
        isTrue,
      );
      expect(writer.historyRevision, beforeHistoryRevision);

      final inserted = writer.insertWriterBlockFromSave(
        saveId: sourceSaveId,
        sectionId: null,
        createSectionIfMissing: true,
        stagedSectionId: 'pending-harmony-section',
        laneKind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.piano,
        laneId: 'pending-piano-lane',
        startBar: 1,
        expectedProjectId: projectId,
      );
      expect(inserted, isTrue);
      await writer.reconcileCurrentProject();

      final section = container.read(songwriterProvider).sections.single;
      expect(section.id, 'pending-harmony-section');
      expect(section.lengthBars, 8);
      expect(section.lanes, hasLength(2));
      expect(
        section.lanes.first.harmonyInstrument,
        HarmonyLaneInstrument.fretboard,
      );
      final lane = section.lanes.singleWhere(
        (candidate) => candidate.id == 'pending-piano-lane',
      );
      expect(lane.harmonyInstrument, HarmonyLaneInstrument.piano);
      expect(lane.blocks.single.saveId, sourceSaveId);
      final after = container.read(saveSystemProvider);
      expect(after.saves, hasLength(1));
      expect(after.saves.single.toJson(), sourceBefore);
      expect(after.writerLinks, hasLength(1));
      expect(after.writerLinks.single.saveId, sourceSaveId);
      expect(
        section.lanes.where((candidate) => candidate.kind == SongLaneKind.save),
        isEmpty,
      );
    },
  );

  test(
    'mismatched explicit Harmony lane and stale project target are no-ops',
    () async {
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      final saves = container.read(saveSystemProvider.notifier);
      final sourceSaveId = saves.saveSnapshot(
        'Piano chord source',
        projectId,
        pianoChord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          midiNotes: const [60, 64, 67],
          pendingRoot: 'C',
        ),
      )!;
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final beforeWriter = container.read(songwriterProvider);
      final beforeSaveSystem = container.read(saveSystemProvider);
      final beforeHistoryRevision = writer.historyRevision;

      expect(
        writer.insertWriterBlockFromSave(
          saveId: sourceSaveId,
          sectionId: section.id,
          laneKind: SongLaneKind.harmony,
          laneId: section.lanes.single.id,
          startBar: 0,
        ),
        isFalse,
      );
      expect(
        writer.insertWriterBlockFromSave(
          saveId: sourceSaveId,
          sectionId: section.id,
          laneKind: SongLaneKind.harmony,
          startBar: 0,
          expectedProjectId: 'another-project',
        ),
        isFalse,
      );
      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          startBar: 0,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G'],
          expectedProjectId: 'another-project',
        ),
        isFalse,
      );
      expect(
        identical(container.read(songwriterProvider), beforeWriter),
        isTrue,
      );
      expect(
        identical(container.read(saveSystemProvider), beforeSaveSystem),
        isTrue,
      );
      expect(writer.historyRevision, beforeHistoryRevision);
    },
  );

  test('failed Harmony Save replacement clears the previous error', () async {
    final (:container, :writer, projectId: _) = await makeProject();
    writer.addSection(label: 'Verse', lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final lane = section.lanes.single;
    writer.addHarmonyChord(
      sectionId: section.id,
      laneId: lane.id,
      block: chord(
        symbol: 'C',
        rootPc: 0,
        notes: const ['C', 'E', 'G'],
        startBar: 0,
      ),
    );
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;

    expect(
      writer.replaceHarmonyBlockWithSave(
        sectionId: section.id,
        laneId: lane.id,
        blockId: block.id,
        saveId: 'missing-save',
      ),
      isFalse,
    );
    expect(
      writer.lastHarmonyMutationError,
      contains('Choose a Harmony save made for this lane’s instrument.'),
    );

    expect(
      writer.replaceHarmonyBlockWithSave(
        sectionId: 'missing-section',
        laneId: lane.id,
        blockId: block.id,
        saveId: 'missing-save',
      ),
      isFalse,
    );
    expect(writer.lastHarmonyMutationError, isNull);
  });

  test(
    'replacing a Harmony Save preserves block placement and local lyrics',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: lane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 2,
          spanBars: 2,
        ),
      );
      await writer.reconcileCurrentProject();
      final sourceBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      writer.setBlockLyric(
        sectionId: section.id,
        laneId: lane.id,
        blockId: sourceBlock.id,
        verseIndex: 0,
        text: 'Keep this lyric',
      );
      writer.setLaneRepeat(sectionId: section.id, laneId: lane.id, repeat: 3);
      final targetSnapshot = pianoChord(
        symbol: 'G',
        rootPc: 7,
        notes: const ['G', 'B', 'D'],
        midiNotes: const [55, 59, 62],
        pendingRoot: 'G',
      );
      final targetSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('G chord', projectId, targetSnapshot)!;
      final targetSaveBefore = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == targetSaveId)
          .toJson();

      expect(
        writer.replaceHarmonyBlockWithSave(
          sectionId: section.id,
          laneId: lane.id,
          blockId: sourceBlock.id,
          saveId: targetSaveId,
        ),
        isTrue,
      );
      await writer.reconcileCurrentProject();

      final updatedSection = container.read(songwriterProvider).sections.single;
      final updatedLane = updatedSection.lanes.single;
      final updatedBlock = updatedLane.blocks.single;
      expect(updatedLane.id, lane.id);
      expect(updatedLane.repeat, 3);
      expect(updatedBlock.id, sourceBlock.id);
      expect(updatedBlock.startBar, 2);
      expect(updatedBlock.spanBars, 2);
      expect(updatedBlock.lyrics, ['Keep this lyric']);
      expect(updatedBlock.chordSymbol, 'G');
      expect(updatedBlock.saveId, targetSaveId);
      final saveState = container.read(saveSystemProvider);
      expect(
        saveState.saves.singleWhere((save) => save.id == targetSaveId).toJson(),
        targetSaveBefore,
      );
      expect(
        saveState.writerLinks
            .singleWhere((link) => link.blockId == sourceBlock.id)
            .saveId,
        targetSaveId,
      );
    },
  );

  test(
    'reused Harmony Save replacement preserves repeated placement identity',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: lane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 1,
          spanBars: 2,
        ),
      );
      await writer.reconcileCurrentProject();
      final sourceBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      writer.setBlockLyric(
        sectionId: section.id,
        laneId: lane.id,
        blockId: sourceBlock.id,
        verseIndex: 0,
        text: 'Local lyric',
      );
      writer.setLaneRepeat(sectionId: section.id, laneId: lane.id, repeat: 3);
      final targetSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'G chord source',
            projectId,
            pianoChord(
              symbol: 'G',
              rootPc: 7,
              notes: const ['G', 'B', 'D'],
              midiNotes: const [55, 59, 62],
              pendingRoot: 'G',
            ),
          )!;
      final targetBefore = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == targetSaveId)
          .toJson();
      final saveCount = container.read(saveSystemProvider).saves.length;

      expect(
        writer.insertWriterBlockFromSave(
          saveId: targetSaveId,
          sectionId: section.id,
          laneKind: SongLaneKind.harmony,
          laneId: lane.id,
          startBar: 4,
          replaceBlockId: sourceBlock.id,
        ),
        isTrue,
      );
      await writer.reconcileCurrentProject();

      final updatedSection = container.read(songwriterProvider).sections.single;
      final updatedLane = updatedSection.lanes.single;
      final updatedBlock = updatedLane.blocks.single;
      expect(updatedLane.id, lane.id);
      expect(updatedLane.repeat, 3);
      expect(updatedBlock.id, sourceBlock.id);
      expect(updatedBlock.startBar, 1);
      expect(updatedBlock.spanBars, 2);
      expect(updatedBlock.lyrics, ['Local lyric']);
      expect(updatedBlock.saveId, targetSaveId);
      expect(updatedBlock.chordSymbol, 'G');
      final saveState = container.read(saveSystemProvider);
      expect(saveState.saves, hasLength(saveCount));
      expect(
        saveState.saves.singleWhere((save) => save.id == targetSaveId).toJson(),
        targetBefore,
      );
      expect(
        saveState.saves.singleWhere((save) => save.id == targetSaveId).folderId,
        projectId,
      );
      expect(
        saveState.writerLinks
            .singleWhere((link) => link.blockId == sourceBlock.id)
            .saveId,
        targetSaveId,
      );
    },
  );

  test(
    'standalone Harmony edit copies to root without rebinding placements',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: section.lanes.single.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 0,
        ),
        saveName: 'Canonical C',
      );
      await writer.reconcileCurrentProject();
      final sourceBefore = container.read(saveSystemProvider).saves.single;
      final blockBefore = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      final historyBefore = writer.historyRevision;
      final editedNative = PianoSnapshot(
        currentRange: PianoRangeName.key88,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 51, midiNote: 72, noteName: 'C'),
          PianoCoordinate(keyIndex: 55, midiNote: 76, noteName: 'E'),
          PianoCoordinate(keyIndex: 58, midiNote: 79, noteName: 'G'),
        ],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: PianoViewMode.exact,
        pendingChord: const PendingChord(root: 'G', quality: '', symbol: 'G'),
      );

      final standaloneId = writer.saveStandaloneHarmonyEdit(
        sourceSaveId: sourceBefore.id,
        name: 'Edited standalone C',
        snapshot: editedNative,
      );

      expect(standaloneId, isNotNull);
      final saves = container.read(saveSystemProvider).saves;
      expect(saves, hasLength(2));
      final standalone = saves.singleWhere((save) => save.id == standaloneId);
      expect(standalone.origin, SaveOrigin.manual);
      expect(standalone.folderId, projectId);
      expect(standalone.name, 'Edited standalone C');
      final composite = standalone.snapshot as HarmonyChordSnapshot;
      expect(
        composite.writerBlock.toJson(),
        (sourceBefore.snapshot as HarmonyChordSnapshot).writerBlock.toJson(),
      );
      expect(composite.instrumentState.pendingChord?.symbol, 'C');
      expect(
        saves.singleWhere((save) => save.id == sourceBefore.id).toJson(),
        sourceBefore.toJson(),
      );
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .toJson(),
        blockBefore.toJson(),
      );
      expect(writer.historyRevision, historyBefore);
    },
  );

  test(
    'linked Harmony update rejects instrument and Save anchor mismatches atomically',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      var section = container.read(songwriterProvider).sections.single;
      final harmonyLaneId = section.lanes.single.id;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: harmonyLaneId,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 0,
        ),
        saveName: 'Canonical C',
      );
      await writer.reconcileCurrentProject();
      section = container.read(songwriterProvider).sections.single;
      final harmonyBlock = section.lanes
          .singleWhere((lane) => lane.id == harmonyLaneId)
          .blocks
          .single;
      final saveId = harmonyBlock.saveId!;
      final canonicalBefore = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId)
          .toJson();

      final fretboardLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      )!;
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: saveLaneId,
        harmonyLaneId: fretboardLaneId,
      );
      section = container.read(songwriterProvider).sections.single;
      writer.state = writer.state.copyWith(
        sections: [
          section.copyWith(
            lanes: [
              for (final lane in section.lanes)
                if (lane.id == saveLaneId)
                  lane.copyWith(
                    blocks: [
                      makeSaveBlock(saveId: saveId, startBar: 2, spanBars: 1),
                    ],
                  )
                else
                  lane,
            ],
          ),
        ],
      );
      await writer.reconcileCurrentProject();

      final projectBefore = container.read(songwriterProvider).toJson();
      final savesBefore = container
          .read(saveSystemProvider)
          .saves
          .map((save) => save.toJson())
          .toList();
      final linksBefore = container
          .read(saveSystemProvider)
          .writerLinks
          .map((link) => link.toJson())
          .toList();
      final historyBefore = writer.historyRevision;
      final canonical =
          container
                  .read(saveSystemProvider)
                  .saves
                  .singleWhere((save) => save.id == saveId)
                  .snapshot
              as HarmonyChordSnapshot;

      expect(
        writer.updateLinkedSaveSnapshot(
          saveId: saveId,
          snapshot: _cMajorFretboard(inputMode: FretboardInputMode.free),
        ),
        isFalse,
      );
      expect(
        writer.updateLinkedSaveSnapshot(
          saveId: saveId,
          snapshot: canonical.instrumentState,
        ),
        isFalse,
      );

      expect(container.read(songwriterProvider).toJson(), projectBefore);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .map((save) => save.toJson())
            .toList(),
        savesBefore,
      );
      expect(
        container
            .read(saveSystemProvider)
            .writerLinks
            .map((link) => link.toJson())
            .toList(),
        linksBefore,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == saveId)
            .toJson(),
        canonicalBefore,
      );
      expect(writer.historyRevision, historyBefore);
      expect(
        container
            .read(saveSystemProvider)
            .writerLinks
            .where((link) => link.saveId == saveId)
            .map((link) => link.laneKind),
        containsAll([SongLaneKind.harmony, SongLaneKind.save]),
      );
      expect(projectId, isNotEmpty);
    },
  );

  test(
    'native linked Save edits reject instrument and anchor mismatches atomically',
    () async {
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      writer.addSection(label: 'Verse', lengthBars: 8);
      var section = container.read(songwriterProvider).sections.single;
      final pianoHarmonyLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      )!;
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      final canonical = _cMajorFretboard();
      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('Fretboard voicing', projectId, canonical)!;
      writer.addSaveBlock(
        sectionId: section.id,
        laneId: saveLaneId,
        saveId: saveId,
        startBar: 0,
        spanBars: 1,
      );
      await writer.reconcileCurrentProject();

      section = container.read(songwriterProvider).sections.single;
      writer.state = writer.state.copyWith(
        sections: [
          section.copyWith(
            lanes: [
              for (final lane in section.lanes)
                if (lane.id == saveLaneId)
                  lane.copyWith(anchorLaneId: pianoHarmonyLaneId)
                else
                  lane,
            ],
          ),
        ],
      );
      final projectBefore = container.read(songwriterProvider).toJson();
      final savesBefore = container
          .read(saveSystemProvider)
          .saves
          .map((save) => save.toJson())
          .toList();
      final linksBefore = container
          .read(saveSystemProvider)
          .writerLinks
          .map((link) => link.toJson())
          .toList();
      final historyBefore = writer.historyRevision;

      expect(
        writer.updateLinkedSaveSnapshot(
          saveId: saveId,
          snapshot: _cMajorFretboard(inputMode: FretboardInputMode.free),
        ),
        isFalse,
      );
      expect(
        writer.updateLinkedSaveSnapshot(
          saveId: saveId,
          snapshot: PianoSnapshot(
            currentRange: PianoRangeName.key61,
            selectedKeys: const [],
            selectedNotes: const ['C', 'E', 'G'],
            viewMode: PianoViewMode.exact,
          ),
        ),
        isFalse,
      );
      expect(
        writer.updateLinkedSaveSnapshot(saveId: saveId, snapshot: canonical),
        isFalse,
      );

      expect(container.read(songwriterProvider).toJson(), projectBefore);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .map((save) => save.toJson())
            .toList(),
        savesBefore,
      );
      expect(
        container
            .read(saveSystemProvider)
            .writerLinks
            .map((link) => link.toJson())
            .toList(),
        linksBefore,
      );
      expect(writer.historyRevision, historyBefore);
      expect(pianoHarmonyLaneId, isNotEmpty);
    },
  );

  test(
    'normal Writer reconciliation fails closed on a Free Save block',
    () async {
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      writer.addSection(label: 'Verse', lengthBars: 8);
      var section = container.read(songwriterProvider).sections.single;
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      section = container.read(songwriterProvider).sections.single;
      final saveLane = section.lanes.singleWhere(
        (lane) => lane.id == saveLaneId,
      );
      final invalidBlock = SongBlock(
        id: 'imported-free',
        startBar: 0,
        spanBars: 1,
        embedded: _cMajorFretboard(inputMode: FretboardInputMode.free),
      );
      writer.state = writer.state.copyWith(
        sections: [
          section.copyWith(
            lanes: [
              for (final lane in section.lanes)
                if (lane.id == saveLaneId)
                  lane.copyWith(blocks: [invalidBlock])
                else
                  lane,
            ],
          ),
        ],
      );
      final projectBefore = container.read(songwriterProvider);
      final savesBefore = container.read(saveSystemProvider);
      final historyBefore = writer.historyRevision;

      await writer.reconcileCurrentProject();

      expect(
        identical(container.read(songwriterProvider), projectBefore),
        isTrue,
      );
      expect(
        identical(container.read(saveSystemProvider), savesBefore),
        isTrue,
      );
      expect(writer.historyRevision, historyBefore);
      expect(writer.lastHarmonyMutationError, contains('not eligible'));
      expect(projectId, isNotEmpty);
      expect(saveLane.blocks, isEmpty);
    },
  );

  test(
    'Free selections are rejected by every direct Writer placement gate',
    () async {
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      writer.addSection(label: 'Verse', lengthBars: 8);
      var section = container.read(songwriterProvider).sections.single;
      final harmonyLane = section.lanes.single;
      writer.addHarmonyBlock(
        sectionId: section.id,
        laneId: harmonyLane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 0,
        ),
      );
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      final freeSnapshot = _cMajorFretboard(inputMode: FretboardInputMode.free);
      final freeSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('Free voicing', projectId, freeSnapshot)!;
      await writer.reconcileCurrentProject();

      section = container.read(songwriterProvider).sections.single;
      final harmonyBlock = section.lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
          .blocks
          .single;
      final projectBefore = container.read(songwriterProvider);
      final savesBefore = container.read(saveSystemProvider);
      final historyBefore = writer.historyRevision;

      writer.addSaveBlock(
        sectionId: section.id,
        laneId: saveLaneId,
        snapshot: freeSnapshot,
        saveName: 'Free voicing',
        startBar: 2,
        spanBars: 1,
      );
      writer.addLibraryBlockAt(
        sectionId: section.id,
        saveId: freeSaveId,
        startBar: 2,
        anchorLaneId: harmonyLane.id,
      );
      writer.acceptLibraryMatch(
        sectionId: section.id,
        harmonyBlockId: harmonyBlock.id,
        saveId: freeSaveId,
      );
      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          startBar: 3,
          snapshot: freeSnapshot,
          asExactHarmony: true,
          chordSymbol: 'Free shape',
        ),
        isFalse,
      );

      expect(
        identical(container.read(songwriterProvider), projectBefore),
        isTrue,
      );
      expect(
        identical(container.read(saveSystemProvider), savesBefore),
        isTrue,
      );
      expect(writer.historyRevision, historyBefore);
    },
  );

  test(
    'root Save promotion keeps its identity and folder through journal reload',
    () async {
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('C shape', projectId, _cMajorFretboard())!;
      final original = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final harmonyLane = section.lanes.single;
      writer.addLibraryBlockAt(
        sectionId: section.id,
        saveId: saveId,
        startBar: 2,
        anchorLaneId: harmonyLane.id,
      );
      await writer.reconcileCurrentProject();
      final rootVoicingBefore = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save)
          .blocks
          .single;
      expect(
        writerSaveBlockMidiNotes(
          rootVoicingBefore,
          container.read(saveSystemProvider).saves,
          projectId: projectId,
          folders: container.read(saveSystemProvider).folders,
        ),
        [43, 48, 52, 55, 60, 64],
      );

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          startBar: 0,
          reuseSaveId: saveId,
          asExactHarmony: true,
          chordSymbol: 'C shape',
        ),
        isTrue,
      );
      await container.read(writerSaveSyncProvider.notifier).drain();

      final promotedEntry = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      expect(promotedEntry.folderId, projectId);
      expect(promotedEntry.name, original.name);
      expect(promotedEntry.createdAt, original.createdAt);
      expect(promotedEntry.order, original.order);
      expect(promotedEntry.snapshot, isA<HarmonyChordSnapshot>());
      final composite = promotedEntry.snapshot as HarmonyChordSnapshot;
      expect(composite.writerBlock.chordSymbol, 'C shape');
      expect(composite.writerBlock.chordRootPc, isNull);
      expect(composite.writerBlock.chordQuality, isNull);
      expect(composite.instrumentState, isA<FretboardSnapshot>());
      expect(
        (composite.instrumentState as FretboardSnapshot).inputMode,
        FretboardInputMode.chord,
      );
      final linkedBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
          .blocks
          .single;
      expect(linkedBlock.saveId, saveId);
      final linksForSave = container
          .read(saveSystemProvider)
          .writerLinks
          .where((link) => link.saveId == saveId)
          .toList();
      expect(linksForSave, hasLength(2));
      expect(
        linksForSave.map((link) => link.laneKind),
        containsAll([SongLaneKind.harmony, SongLaneKind.save]),
      );

      final rootVoicingAfter = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save)
          .blocks
          .single;
      expect(rootVoicingAfter.saveId, saveId);
      expect(
        writerSaveBlockMidiNotes(
          rootVoicingAfter,
          container.read(saveSystemProvider).saves,
          projectId: projectId,
          folders: container.read(saveSystemProvider).folders,
        ),
        [43, 48, 52, 55, 60, 64],
      );

      final reloaded = SaveEntry.fromJson(promotedEntry.toJson());
      expect(reloaded.id, saveId);
      expect(reloaded.folderId, projectId);
      expect(
        (reloaded.snapshot as HarmonyChordSnapshot).writerBlock.chordRootPc,
        isNull,
      );

      final restoredContainer = ProviderContainer();
      addTearDown(restoredContainer.dispose);
      await restoredContainer.read(saveSystemProvider.notifier).hydrate();
      await restoredContainer
          .read(songwriterSessionsProvider.notifier)
          .hydrate();
      final restoredSave = restoredContainer
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      expect(restoredSave.folderId, projectId);
      expect(restoredSave.name, original.name);
      expect(restoredSave.snapshot, isA<HarmonyChordSnapshot>());
      final restoredProject = restoredContainer.read(songwriterProvider);
      final restoredRootVoicing = restoredProject.sections.single.lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save)
          .blocks
          .single;
      expect(restoredRootVoicing.saveId, saveId);
      expect(
        writerSaveBlockMidiNotes(
          restoredRootVoicing,
          restoredContainer.read(saveSystemProvider).saves,
          projectId: projectId,
          folders: restoredContainer.read(saveSystemProvider).folders,
        ),
        [43, 48, 52, 55, 60, 64],
      );
    },
  );

  test(
    'native exact Harmony insertion retains captured name and octave',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final capture = PianoSnapshot(
        currentRange: PianoRangeName.key88,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 27, midiNote: 48, noteName: 'C'),
          PianoCoordinate(keyIndex: 40, midiNote: 61, noteName: 'C#'),
          PianoCoordinate(keyIndex: 58, midiNote: 79, noteName: 'G'),
        ],
        selectedNotes: const ['C', 'C#', 'G'],
        viewMode: PianoViewMode.exact,
      );

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          startBar: 0,
          snapshot: capture,
          asExactHarmony: true,
          chordSymbol: 'C cluster',
          expectedProjectId: projectId,
        ),
        isTrue,
      );
      await container.read(writerSaveSyncProvider.notifier).drain();

      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
          .blocks
          .single;
      expect(block.chordSymbol, 'C cluster');
      expect(block.chordRootPc, isNull);
      expect(block.chordQuality, isNull);
      final composite = block.embedded as HarmonyChordSnapshot;
      expect(composite.writerBlock.chordRootPc, isNull);
      expect(composite.writerBlock.chordQuality, isNull);
      expect(
        writerSaveBlockMidiNotes(
          block,
          container.read(saveSystemProvider).saves,
          projectId: projectId,
          folders: container.read(saveSystemProvider).folders,
        ),
        [48, 61, 79],
      );
    },
  );

  test(
    'insertion and replacement preserve primary Harmony lane placement',
    () async {
      final storage = _RecordingWriterSaveSyncStorage();
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
        syncStorage: storage,
      );
      writer.addSection(label: 'Verse', lengthBars: 8);
      var section = container.read(songwriterProvider).sections.single;
      final primaryLaneId = section.lanes.single.id;

      for (final startBar in [1, 2]) {
        expect(
          writer.insertInstrumentSelectionAtBar(
            sectionId: section.id,
            laneId: primaryLaneId,
            startBar: startBar,
            snapshot: _cMajorFretboard(),
            asExactHarmony: true,
            chordSymbol: 'C shape',
            saveName: 'C shape $startBar',
            harmonyInstrument: HarmonyLaneInstrument.fretboard,
            expectedProjectId: projectId,
          ),
          isTrue,
        );
      }

      final pianoLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      )!;
      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          laneId: pianoLaneId,
          startBar: 1,
          snapshot: _cMajorPiano(),
          asExactHarmony: true,
          chordSymbol: 'C piano',
          saveName: 'C piano',
          harmonyInstrument: HarmonyLaneInstrument.piano,
          expectedProjectId: projectId,
        ),
        isTrue,
      );

      final additionalFretboardLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      )!;
      final primaryStrumLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      final additionalStrumLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: primaryStrumLaneId,
        harmonyLaneId: primaryLaneId,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: additionalStrumLaneId,
        harmonyLaneId: additionalFretboardLaneId,
      );
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      writer.addSaveBlock(
        sectionId: section.id,
        laneId: saveLaneId,
        snapshot: _cMajorFretboard(),
        saveName: 'Primary voicing',
        startBar: 4,
        spanBars: 1,
      );

      section = container.read(songwriterProvider).sections.single;
      var primaryBlock = section.lanes
          .singleWhere((lane) => lane.id == primaryLaneId)
          .blocks
          .singleWhere((block) => block.startBar == 1);
      writer.setBlockLyric(
        sectionId: section.id,
        laneId: primaryLaneId,
        blockId: primaryBlock.id,
        verseIndex: 0,
        text: 'Keep this local lyric',
      );
      writer.setLaneRepeat(
        sectionId: section.id,
        laneId: primaryLaneId,
        repeat: 3,
      );
      await writer.reconcileCurrentProject();
      await container.read(writerSaveSyncProvider.notifier).drain();
      storage.events.clear();

      section = container.read(songwriterProvider).sections.single;
      final laneIdsBefore = section.lanes.map((lane) => lane.id).toList();
      final laneOrdersBefore = {
        for (final lane in section.lanes) lane.id: lane.order,
      };
      final primaryBefore = primaryHarmonyLane(section)!.id;
      expect(primaryBefore, primaryLaneId);
      expect(
        saveAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == saveLaneId),
        )!.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == primaryStrumLaneId),
        )!.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == additionalStrumLaneId),
        )!.id,
        additionalFretboardLaneId,
      );
      final originalBlock = section.lanes
          .singleWhere((lane) => lane.id == primaryLaneId)
          .blocks
          .singleWhere((block) => block.startBar == 1);
      final untouchedPrimaryBlock = section.lanes
          .singleWhere((lane) => lane.id == primaryLaneId)
          .blocks
          .singleWhere((block) => block.startBar == 2)
          .toJson();
      final pianoBlock = section.lanes
          .singleWhere((lane) => lane.id == pianoLaneId)
          .blocks
          .single
          .toJson();
      final saveBlock = section.lanes
          .singleWhere((lane) => lane.id == saveLaneId)
          .blocks
          .single
          .toJson();

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          laneId: primaryLaneId,
          startBar: 3,
          snapshot: _dMajorFretboard(),
          asExactHarmony: true,
          chordSymbol: 'D shape',
          saveName: 'D shape',
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
          expectedProjectId: projectId,
        ),
        isTrue,
      );
      await container.read(writerSaveSyncProvider.notifier).drain();
      expect(storage.events, isNotEmpty);
      section = container.read(songwriterProvider).sections.single;
      expect(section.lanes.map((lane) => lane.id), laneIdsBefore);
      expect({
        for (final lane in section.lanes) lane.id: lane.order,
      }, laneOrdersBefore);
      expect(primaryHarmonyLane(section)!.id, primaryLaneId);

      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: section.id,
          laneId: primaryLaneId,
          startBar: originalBlock.startBar,
          snapshot: _dMajorFretboard(),
          asExactHarmony: true,
          chordSymbol: 'D shape replacement',
          saveName: 'D shape replacement',
          replaceBlockId: originalBlock.id,
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
          expectedProjectId: projectId,
        ),
        isTrue,
      );
      await writer.reconcileCurrentProject();
      await container.read(writerSaveSyncProvider.notifier).drain();
      expect(storage.events, isNotEmpty);

      section = container.read(songwriterProvider).sections.single;
      final primaryLane = section.lanes.singleWhere(
        (lane) => lane.id == primaryLaneId,
      );
      primaryBlock = primaryLane.blocks.singleWhere(
        (block) => block.startBar == originalBlock.startBar,
      );
      expect(section.lanes.map((lane) => lane.id), laneIdsBefore);
      expect({
        for (final lane in section.lanes) lane.id: lane.order,
      }, laneOrdersBefore);
      expect(primaryHarmonyLane(section)!.id, primaryLaneId);
      expect(primaryBlock.id, originalBlock.id);
      expect(primaryBlock.startBar, originalBlock.startBar);
      expect(primaryBlock.spanBars, originalBlock.spanBars);
      expect(primaryBlock.lyrics, ['Keep this local lyric']);
      expect(primaryLane.repeat, 3);
      expect(primaryBlock.chordSymbol, 'D shape replacement');
      expect(
        ((primaryBlock.embedded as HarmonyChordSnapshot).instrumentState
                as FretboardSnapshot)
            .selectedNotes,
        ['D', 'F#', 'A'],
      );
      expect(
        primaryLane.blocks.singleWhere((block) => block.startBar == 2).toJson(),
        untouchedPrimaryBlock,
      );
      expect(
        section.lanes
            .singleWhere((lane) => lane.id == pianoLaneId)
            .blocks
            .single
            .toJson(),
        pianoBlock,
      );
      expect(
        section.lanes
            .singleWhere((lane) => lane.id == saveLaneId)
            .blocks
            .single
            .toJson(),
        saveBlock,
      );
      expect(
        saveAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == saveLaneId),
        )!.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == primaryStrumLaneId),
        )!.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == additionalStrumLaneId),
        )!.id,
        additionalFretboardLaneId,
      );

      storage.events.clear();
      expect(writer.undo(), isTrue);
      await writer.reconcileCurrentProject();
      await container.read(writerSaveSyncProvider.notifier).drain();
      expect(storage.events, isNotEmpty);
      section = container.read(songwriterProvider).sections.single;
      primaryBlock = section.lanes
          .singleWhere((lane) => lane.id == primaryLaneId)
          .blocks
          .singleWhere((block) => block.startBar == originalBlock.startBar);
      expect(section.lanes.map((lane) => lane.id), laneIdsBefore);
      expect(primaryHarmonyLane(section)!.id, primaryLaneId);
      expect(primaryBlock.toJson(), originalBlock.toJson());
      expect(
        saveAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == saveLaneId),
        )!.id,
        primaryLaneId,
      );
    },
  );

  test(
    'reused Harmony Save replacement preserves primary lane order and anchors',
    () async {
      final storage = _RecordingWriterSaveSyncStorage();
      final (:container, :projectId, :writer) = await makeProject(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
        syncStorage: storage,
      );
      writer.addSection(label: 'Verse', lengthBars: 8);
      var section = container.read(songwriterProvider).sections.single;
      final primaryLaneId = section.lanes.single.id;
      final addedChord = writer.addHarmonyChord(
        sectionId: section.id,
        laneId: primaryLaneId,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 2,
          spanBars: 2,
        ),
        saveName: 'Initial C',
      );
      expect(addedChord.success, isTrue);
      await writer.reconcileCurrentProject();

      final sourceBlockId = addedChord.blockId!;
      writer.setBlockLyric(
        sectionId: section.id,
        laneId: primaryLaneId,
        blockId: sourceBlockId,
        verseIndex: 0,
        text: 'Keep this lyric',
      );
      writer.setLaneRepeat(
        sectionId: section.id,
        laneId: primaryLaneId,
        repeat: 3,
      );
      final targetSnapshot = HarmonyChordSnapshot(
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
        writerBlock: WriterBlockSnapshot(
          laneKind: SongLaneKind.harmony,
          chordSymbol: 'D voicing',
          chordNotes: const ['D', 'F#', 'A'],
        ),
        instrumentState: _dMajorFretboard(),
      );
      final targetSaveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot('D voicing', projectId, targetSnapshot)!;
      final targetSaveBefore = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == targetSaveId)
          .toJson();

      final pianoLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      )!;
      final secondaryFretboardLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      )!;
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .singleWhere((lane) => lane.id == pianoLaneId)
            .harmonyInstrument,
        HarmonyLaneInstrument.piano,
      );
      final primaryStrumLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      final secondaryStrumLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: primaryStrumLaneId,
        harmonyLaneId: primaryLaneId,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: secondaryStrumLaneId,
        harmonyLaneId: secondaryFretboardLaneId,
      );
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      writer.addSaveBlock(
        sectionId: section.id,
        laneId: saveLaneId,
        snapshot: _cMajorFretboard(),
        saveName: 'Implicit primary voicing',
        startBar: 5,
        spanBars: 1,
      );
      await writer.reconcileCurrentProject();
      await container.read(writerSaveSyncProvider.notifier).drain();

      section = container.read(songwriterProvider).sections.single;
      final laneIdsBefore = section.lanes.map((lane) => lane.id).toList();
      final laneOrdersBefore = {
        for (final lane in section.lanes) lane.id: lane.order,
      };
      final sourceLane = section.lanes.singleWhere(
        (lane) => lane.id == primaryLaneId,
      );
      final sourceBlock = sourceLane.blocks.single;
      final sourceBlockBefore = sourceBlock.toJson();
      final implicitSaveLane = section.lanes.singleWhere(
        (lane) => lane.id == saveLaneId,
      );
      expect(implicitSaveLane.anchorLaneId, isNull);
      expect(saveAnchorLane(section, implicitSaveLane)?.id, primaryLaneId);
      storage.events.clear();

      expect(
        writer.insertWriterBlockFromSave(
          saveId: targetSaveId,
          sectionId: section.id,
          laneKind: SongLaneKind.harmony,
          startBar: sourceBlock.startBar,
          replaceBlockId: sourceBlock.id,
          expectedProjectId: projectId,
        ),
        isTrue,
      );
      await writer.reconcileCurrentProject();
      await container.read(writerSaveSyncProvider.notifier).drain();

      section = container.read(songwriterProvider).sections.single;
      final updatedLane = section.lanes.singleWhere(
        (lane) => lane.id == primaryLaneId,
      );
      final updatedBlock = updatedLane.blocks.single;
      final updatedHarmony = updatedBlock.embedded as HarmonyChordSnapshot;
      expect(section.lanes.map((lane) => lane.id), laneIdsBefore);
      expect({
        for (final lane in section.lanes) lane.id: lane.order,
      }, laneOrdersBefore);
      expect(primaryHarmonyLane(section)?.id, primaryLaneId);
      expect(updatedLane.repeat, 3);
      expect(updatedBlock.id, sourceBlock.id);
      expect(updatedBlock.startBar, sourceBlock.startBar);
      expect(updatedBlock.spanBars, sourceBlock.spanBars);
      expect(updatedBlock.lyrics, ['Keep this lyric']);
      expect(updatedBlock.saveId, targetSaveId);
      expect(updatedBlock.chordSymbol, 'D voicing');
      expect(updatedHarmony.writerBlock.chordRootPc, isNull);
      expect(updatedHarmony.writerBlock.chordQuality, isNull);
      expect(updatedHarmony.writerBlock.chordNotes, ['D', 'F#', 'A']);
      expect(
        (updatedHarmony.instrumentState as FretboardSnapshot).selectedNotes,
        ['D', 'F#', 'A'],
      );
      expect(
        saveAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == saveLaneId),
        )?.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == primaryStrumLaneId),
        )?.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == secondaryStrumLaneId),
        )?.id,
        secondaryFretboardLaneId,
      );
      final savesAfterReplacement = container.read(saveSystemProvider);
      expect(
        savesAfterReplacement.saves
            .singleWhere((save) => save.id == targetSaveId)
            .toJson(),
        targetSaveBefore,
      );
      expect(
        savesAfterReplacement.writerLinks
            .singleWhere((link) => link.blockId == sourceBlock.id)
            .saveId,
        targetSaveId,
      );
      expect(storage.events, isNotEmpty);

      storage.events.clear();
      expect(writer.undo(), isTrue);
      await writer.reconcileCurrentProject();
      await container.read(writerSaveSyncProvider.notifier).drain();
      expect(storage.events, isNotEmpty);

      section = container.read(songwriterProvider).sections.single;
      final undoneLane = section.lanes.singleWhere(
        (lane) => lane.id == primaryLaneId,
      );
      expect(section.lanes.map((lane) => lane.id), laneIdsBefore);
      expect({
        for (final lane in section.lanes) lane.id: lane.order,
      }, laneOrdersBefore);
      expect(primaryHarmonyLane(section)?.id, primaryLaneId);
      expect(undoneLane.repeat, 3);
      expect(undoneLane.blocks.single.toJson(), sourceBlockBefore);
      expect(
        saveAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == saveLaneId),
        )?.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == primaryStrumLaneId),
        )?.id,
        primaryLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          section,
          section.lanes.singleWhere((lane) => lane.id == secondaryStrumLaneId),
        )?.id,
        secondaryFretboardLaneId,
      );
    },
  );

  for (final instrument in HarmonyLaneInstrument.values) {
    for (final startingContent in ['recognized', 'exact']) {
      test(
        '$instrument exact replacement accepts changed notes from $startingContent Harmony and undoes cleanly',
        () async {
          final (:container, :projectId, :writer) = await makeProject(
            defaultInstrument: instrument,
          );
          writer.addSection(label: 'Verse', lengthBars: 8);
          final section = container.read(songwriterProvider).sections.single;
          final lane = section.lanes.single;
          if (startingContent == 'recognized') {
            final result = writer.addHarmonyChord(
              sectionId: section.id,
              laneId: lane.id,
              block: chord(
                symbol: 'C',
                rootPc: 0,
                notes: const ['C', 'E', 'G'],
                startBar: 1,
              ),
              saveName: 'Original C',
            );
            expect(result.success, isTrue);
          } else {
            final originalNative = switch (instrument) {
              HarmonyLaneInstrument.piano => _cMajorPiano(),
              HarmonyLaneInstrument.fretboard => _cMajorFretboard(),
            };
            expect(
              writer.insertInstrumentSelectionAtBar(
                sectionId: section.id,
                laneId: lane.id,
                startBar: 1,
                snapshot: originalNative,
                asExactHarmony: true,
                chordSymbol: 'C cluster',
                saveName: 'Original C cluster',
                harmonyInstrument: instrument,
                expectedProjectId: projectId,
              ),
              isTrue,
            );
          }
          await writer.reconcileCurrentProject();

          final sourceBefore = container
              .read(songwriterProvider)
              .sections
              .single
              .lanes
              .single
              .blocks
              .single;
          final sourceSaveId = sourceBefore.saveId!;
          final sourceSaveBefore = container
              .read(saveSystemProvider)
              .saves
              .singleWhere((save) => save.id == sourceSaveId)
              .toJson();
          writer.setBlockLyric(
            sectionId: section.id,
            laneId: lane.id,
            blockId: sourceBefore.id,
            verseIndex: 0,
            text: 'Keep this local lyric',
          );
          writer.setLaneRepeat(
            sectionId: section.id,
            laneId: lane.id,
            repeat: 3,
          );
          final duplicateLaneId = await writer.duplicateHarmonyLane(
            sectionId: section.id,
            laneId: lane.id,
          );
          expect(duplicateLaneId, isNotNull);
          await writer.reconcileCurrentProject();

          final duplicateBlock = container
              .read(songwriterProvider)
              .sections
              .single
              .lanes
              .singleWhere((candidate) => candidate.id == duplicateLaneId)
              .blocks
              .single;
          final targetNative = switch (instrument) {
            HarmonyLaneInstrument.piano => _dMajorPiano(),
            HarmonyLaneInstrument.fretboard => _dMajorFretboard(),
          };
          expect(
            writer.insertInstrumentSelectionAtBar(
              sectionId: section.id,
              laneId: lane.id,
              startBar: sourceBefore.startBar,
              snapshot: targetNative,
              asExactHarmony: true,
              chordSymbol: 'D cluster',
              saveName: 'Replacement D cluster',
              replaceBlockId: sourceBefore.id,
              harmonyInstrument: instrument,
              expectedProjectId: projectId,
            ),
            isTrue,
          );
          await writer.reconcileCurrentProject();

          var current = container.read(songwriterProvider).sections.single;
          var replacedLane = current.lanes.singleWhere(
            (candidate) => candidate.id == lane.id,
          );
          var replacedBlock = replacedLane.blocks.single;
          final untouchedLane = current.lanes.singleWhere(
            (candidate) => candidate.id == duplicateLaneId,
          );
          expect(replacedBlock.id, sourceBefore.id);
          expect(replacedBlock.startBar, sourceBefore.startBar);
          expect(replacedBlock.spanBars, sourceBefore.spanBars);
          expect(replacedBlock.lyrics, ['Keep this local lyric']);
          expect(replacedLane.repeat, 3);
          expect(replacedBlock.chordSymbol, 'D cluster');
          expect(replacedBlock.chordRootPc, isNull);
          expect(replacedBlock.chordQuality, isNull);
          expect(replacedBlock.chordNotes.toSet(), {'A', 'D', 'F#'});
          expect(replacedBlock.embedded, isA<HarmonyChordSnapshot>());
          final newSaveId = replacedBlock.saveId!;
          expect(newSaveId, isNot(sourceSaveId));
          expect(untouchedLane.blocks.single.id, duplicateBlock.id);
          expect(untouchedLane.blocks.single.saveId, sourceSaveId);
          expect(
            container
                .read(saveSystemProvider)
                .saves
                .singleWhere((save) => save.id == sourceSaveId)
                .toJson(),
            sourceSaveBefore,
            reason: 'a separate use of the old Harmony Save stays canonical',
          );

          expect(writer.undo(), isTrue);
          await writer.reconcileCurrentProject();
          current = container.read(songwriterProvider).sections.single;
          replacedLane = current.lanes.singleWhere(
            (candidate) => candidate.id == lane.id,
          );
          replacedBlock = replacedLane.blocks.single;
          expect(replacedBlock.id, sourceBefore.id);
          expect(replacedBlock.startBar, sourceBefore.startBar);
          expect(replacedBlock.spanBars, sourceBefore.spanBars);
          expect(replacedBlock.lyrics, ['Keep this local lyric']);
          expect(replacedLane.repeat, 3);
          expect(replacedBlock.saveId, sourceSaveId);
          expect(
            replacedBlock.chordSymbol,
            startingContent == 'recognized' ? 'C' : 'C cluster',
          );
          expect(
            container
                .read(saveSystemProvider)
                .saves
                .singleWhere((save) => save.id == sourceSaveId)
                .toJson(),
            sourceSaveBefore,
          );
        },
      );
    }
  }

  test('Piano D-sharp 4 exact Harmony can be replaced with exact D4', () async {
    final (:container, :projectId, :writer) = await makeProject(
      defaultInstrument: HarmonyLaneInstrument.piano,
    );
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final lane = section.lanes.single;
    final dSharp = PianoSnapshot(
      currentRange: PianoRangeName.key88,
      selectedKeys: const [
        PianoCoordinate(keyIndex: 42, midiNote: 63, noteName: 'D#'),
      ],
      selectedNotes: const ['D#'],
      viewMode: PianoViewMode.exact,
    );
    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: section.id,
        laneId: lane.id,
        startBar: 0,
        snapshot: dSharp,
        asExactHarmony: true,
        chordSymbol: 'D#4',
        saveName: 'D#4',
        harmonyInstrument: HarmonyLaneInstrument.piano,
        expectedProjectId: projectId,
      ),
      isTrue,
    );
    await writer.reconcileCurrentProject();
    final original = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    final d = PianoSnapshot(
      currentRange: PianoRangeName.key88,
      selectedKeys: const [
        PianoCoordinate(keyIndex: 41, midiNote: 62, noteName: 'D'),
      ],
      selectedNotes: const ['D'],
      viewMode: PianoViewMode.exact,
    );

    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: section.id,
        laneId: lane.id,
        startBar: 0,
        snapshot: d,
        asExactHarmony: true,
        chordSymbol: 'D4',
        saveName: 'D4',
        replaceBlockId: original.id,
        harmonyInstrument: HarmonyLaneInstrument.piano,
        expectedProjectId: projectId,
      ),
      isTrue,
    );
    await writer.reconcileCurrentProject();

    var block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(block.id, original.id);
    expect(block.startBar, original.startBar);
    expect(block.spanBars, original.spanBars);
    expect(block.chordSymbol, 'D4');
    expect(block.chordNotes, ['D']);
    expect(block.chordRootPc, isNull);
    expect(block.chordQuality, isNull);
    expect(
      (((block.embedded as HarmonyChordSnapshot).instrumentState
              as PianoSnapshot)
          .selectedKeys
          .single
          .midiNote),
      62,
    );

    expect(writer.undo(), isTrue);
    await writer.reconcileCurrentProject();
    block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(block.id, original.id);
    expect(block.saveId, original.saveId);
    expect(block.chordSymbol, 'D#4');
    expect(block.chordNotes, ['D#']);
    expect(
      (((block.embedded as HarmonyChordSnapshot).instrumentState
              as PianoSnapshot)
          .selectedKeys
          .single
          .midiNote),
      63,
    );
  });

  test('each insertion attempt clears the previous Harmony error', () async {
    final (:container, :projectId, :writer) = await makeProject();
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    writer.lastHarmonyMutationError = 'Stale error from an earlier attempt.';

    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: section.id,
        startBar: -1,
        expectedProjectId: projectId,
      ),
      isFalse,
    );
    expect(writer.lastHarmonyMutationError, isNull);
  });

  test(
    'recognized Harmony can become exact, undo, redo, then known again',
    () async {
      final (:container, :projectId, :writer) = await makeProject();
      writer.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      writer.addHarmonyBlock(
        sectionId: section.id,
        laneId: lane.id,
        block: chord(
          symbol: 'C',
          rootPc: 0,
          notes: const ['C', 'E', 'G'],
          startBar: 0,
        ),
      );
      await writer.reconcileCurrentProject();
      var block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;

      expect(
        writer.updateHarmonyBlock(
          sectionId: section.id,
          laneId: lane.id,
          blockId: block.id,
          content: const SongBlock(
            id: 'exact-content',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'C shape',
            chordNotes: ['C', 'E', 'G'],
          ),
        ),
        isTrue,
      );
      await container.read(writerSaveSyncProvider.notifier).drain();
      block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(block.chordSymbol, 'C shape');
      expect(block.chordRootPc, isNull);
      expect(block.chordQuality, isNull);

      expect(writer.undo(), isTrue);
      await container.read(writerSaveSyncProvider.notifier).drain();
      block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(block.chordRootPc, 0);
      expect(block.chordQuality, '');

      expect(writer.redo(), isTrue);
      await container.read(writerSaveSyncProvider.notifier).drain();
      block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(block.chordRootPc, isNull);
      expect(block.chordQuality, isNull);

      expect(
        writer.updateHarmonyBlock(
          sectionId: section.id,
          laneId: lane.id,
          blockId: block.id,
          content: const SongBlock(
            id: 'known-content',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'C',
            chordQuality: '',
            chordRootPc: 0,
            chordNotes: ['C', 'E', 'G'],
          ),
        ),
        isTrue,
      );
      await container.read(writerSaveSyncProvider.notifier).drain();
      final restored = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(restored.chordRootPc, 0);
      expect(restored.chordQuality, '');
    },
  );
}
