import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('attached save badge is labeled and at least 44 pixels wide', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Project',
      const ProjectConfig(
        defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
      ),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final harmonyLaneId = container
        .read(songwriterProvider)
        .sections
        .singleWhere((section) => section.id == sectionId)
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .id;
    writer.addHarmonyBlock(
      sectionId: sectionId,
      laneId: harmonyLaneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
      saveName: 'C',
    );
    final saveId = saveSystem.saveSnapshot(
      'Piano idea',
      projectId,
      PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [
          PianoCoordinate(keyIndex: 24, midiNote: 60, noteName: 'C'),
          PianoCoordinate(keyIndex: 28, midiNote: 64, noteName: 'E'),
          PianoCoordinate(keyIndex: 31, midiNote: 67, noteName: 'G'),
        ],
        selectedNotes: const ['C4', 'E4', 'G4'],
        viewMode: PianoViewMode.exact,
      ),
    )!;
    final saveLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.save,
    );
    writer.addSaveBlock(
      sectionId: sectionId,
      laneId: saveLaneId,
      saveId: saveId,
      startBar: 0,
      spanBars: 1,
    );
    await writer.reconcileCurrentProject();
    final saveBlock = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.save)
        .blocks
        .single;
    SaveEntry? editedSave;
    final screen = UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SongwriterScreenSheet(
            onEditInstrumentSave: (entry) => editedSave = entry,
          ),
        ),
      ),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in [const Size(390, 844), const Size(1180, 820)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(screen);
      await tester.pumpAndSettle();
      final badge = find.byKey(Key('saveBadge_${saveBlock.id}_0'));
      await tester.ensureVisible(badge);
      expect(tester.getSize(badge).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(badge).height, greaterThanOrEqualTo(44));
      expect(find.byTooltip('Open actions for Piano idea'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('saveBadge_${saveBlock.id}_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barActionEditInstrument')), findsOneWidget);
    await tester.tap(find.byKey(const Key('barActionEditInstrument')));
    await tester.pumpAndSettle();
    expect(editedSave?.id, saveId);
  });

  testWidgets('linked blocks expose Rename and Make Unique across lanes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final harmonyLaneId = container
        .read(songwriterProvider)
        .sections
        .singleWhere((section) => section.id == sectionId)
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .id;
    writer.addHarmonyBlock(
      sectionId: sectionId,
      laneId: harmonyLaneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
      saveName: 'C',
    );
    writer.addSilentBlock(
      sectionId: sectionId,
      laneId: harmonyLaneId,
      startBar: 1,
      spanBars: 1,
    );

    final fretboardSaveId = saveSystem.saveSnapshot(
      'Fretboard save',
      projectId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [
          FretCoordinate(stringIndex: 0, fret: 8, noteName: 'C'),
          FretCoordinate(stringIndex: 2, fret: 0, noteName: 'G'),
          FretCoordinate(stringIndex: 3, fret: 2, noteName: 'E'),
        ],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
        inputMode: FretboardInputMode.chord,
      ),
    )!;
    writer.addLibraryBlockAt(
      sectionId: sectionId,
      saveId: fretboardSaveId,
      startBar: 2,
      anchorLaneId: harmonyLaneId,
    );

    final drumLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
    );
    final drumSaveId = saveSystem.saveSnapshot(
      'Beat',
      projectId,
      WriterBlockSnapshot(
        laneKind: SongLaneKind.drum,
        drumPattern: const DrumPattern(
          id: 'linked-drum',
          name: 'Beat',
          lengthTicks: 16,
          lanes: [
            DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
          ],
        ),
      ),
    )!;
    expect(
      writer.insertWriterBlockFromSave(
        saveId: drumSaveId,
        sectionId: sectionId,
        laneKind: SongLaneKind.drum,
        laneId: drumLaneId,
        startBar: 0,
      ),
      isTrue,
    );

    final melodyLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.melody,
    );
    final melodySaveId = saveSystem.saveSnapshot(
      'Melody',
      projectId,
      WriterBlockSnapshot(
        laneKind: SongLaneKind.melody,
        melodyPattern: const NotePattern(
          id: 'linked-melody',
          name: 'Melody',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'melody-note',
              midiNote: 67,
              startTick: 0,
              durationTicks: 8,
            ),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: ['G'],
        ),
        melodyPerformance: const WriterMelodyPerformance(
          instrument: HarmonyLaneInstrument.piano,
        ),
      ),
    )!;
    expect(
      writer.insertWriterBlockFromSave(
        saveId: melodySaveId,
        sectionId: sectionId,
        laneKind: SongLaneKind.melody,
        laneId: melodyLaneId,
        startBar: 0,
      ),
      isTrue,
    );

    final strumLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.guitarStrum,
    );
    final strumSaveId = saveSystem.saveSnapshot(
      'Strum',
      projectId,
      WriterBlockSnapshot(
        laneKind: SongLaneKind.guitarStrum,
        guitarStrumPattern: const GuitarStrumPattern(
          id: 'linked-strum',
          name: 'Strum',
          lengthTicks: 16,
          events: [
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
          ],
        ),
      ),
    )!;
    expect(
      writer.insertWriterBlockFromSave(
        saveId: strumSaveId,
        sectionId: sectionId,
        laneKind: SongLaneKind.guitarStrum,
        laneId: strumLaneId,
        startBar: 0,
        anchorLaneId: harmonyLaneId,
      ),
      isTrue,
    );

    final audioLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.audio,
    );
    final audioSaveId = saveSystem.saveSnapshot(
      'Recording',
      projectId,
      const WriterBlockSnapshot(
        laneKind: SongLaneKind.audio,
        audioClip: AudioClip(
          id: 'linked-audio-clip',
          assetId: 'asset',
          trimEndMs: 4000,
        ),
        audioAsset: AudioAsset(
          id: 'asset',
          durationMs: 4000,
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [10, 20],
          sourceLabel: 'Recording',
        ),
      ),
    )!;
    expect(
      writer.insertWriterBlockFromSave(
        saveId: audioSaveId,
        sectionId: sectionId,
        laneKind: SongLaneKind.audio,
        laneId: audioLaneId,
        startBar: 0,
      ),
      isTrue,
    );
    await writer.reconcileCurrentProject();

    final project = container.read(songwriterProvider);
    final section = project.sections.single;
    SongBlock blockFor(SongLaneKind kind) =>
        section.lanes.singleWhere((lane) => lane.kind == kind).blocks.single;
    final silence = section.lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .blocks
        .singleWhere((block) => block.isSilent);
    final saveBlock = section.lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.save)
        .blocks
        .single;
    final drum = blockFor(SongLaneKind.drum);
    final melody = blockFor(SongLaneKind.melody);
    final strum = blockFor(SongLaneKind.guitarStrum);
    final audio = blockFor(SongLaneKind.audio);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final screen = UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
    );
    for (final size in [const Size(390, 844), const Size(1180, 820)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(screen);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> expectPopupActions(SongBlock block) async {
      final actions = find.byKey(Key('writerBlockActions_${block.id}'));
      await tester.ensureVisible(actions);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('writerRename_${block.id}')), findsOneWidget);
      expect(find.byKey(Key('writerMakeUnique_${block.id}')), findsOneWidget);
      await tester.tap(find.byKey(Key('writerRename_${block.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('writerBlockNameCancel')));
      await tester.pumpAndSettle();
    }

    Future<void> expectSheetActions(
      Finder blockFinder, {
      bool hasSave = true,
      bool harmony = false,
    }) async {
      await tester.ensureVisible(blockFinder);
      await tester.tap(blockFinder);
      await tester.pumpAndSettle();
      if (hasSave) {
        expect(find.byKey(const Key('barActionRenameBlock')), findsOneWidget);
        expect(
          find.byKey(const Key('barActionCreateStandaloneSave')),
          harmony ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('barActionMakeBlockUnique')),
          harmony ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('barActionRenameBlock')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('writerBlockNameCancel')));
        await tester.pumpAndSettle();
      } else {
        expect(find.byKey(const Key('barActionRenameBlock')), findsNothing);
        expect(find.byKey(const Key('barActionMakeBlockUnique')), findsNothing);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    }

    await expectSheetActions(find.text('C').first, harmony: true);
    await expectSheetActions(
      find.byKey(Key('silentCell_${silence.id}_0')),
      hasSave: false,
    );
    await expectSheetActions(find.byKey(Key('saveCell_${saveBlock.id}_0')));
    await expectPopupActions(drum);
    await expectPopupActions(melody);
    await expectPopupActions(strum);
    await expectPopupActions(audio);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicated Harmony placements keep their links when creating standalone Save',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'Project',
        const ProjectConfig(
          defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
        ),
      )!;
      saves.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      var section = container.read(songwriterProvider).sections.single;
      final harmonyLaneId = section.lanes.single.id;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: harmonyLaneId,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G'],
        ),
        saveName: 'C chord',
      );
      await writer.reconcileCurrentProject();
      await writer.duplicateHarmonyLane(
        sectionId: section.id,
        laneId: harmonyLaneId,
      );
      await writer.reconcileCurrentProject();

      section = container.read(songwriterProvider).sections.single;
      final blocks = section.lanes
          .where((lane) => lane.kind == SongLaneKind.harmony)
          .expand((lane) => lane.blocks)
          .toList();
      expect(blocks, hasLength(2));
      final sourceSaveId = blocks.first.saveId!;
      expect(blocks.last.saveId, sourceSaveId);
      final sourceBefore = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == sourceSaveId);
      final linksBefore = container
          .read(saveSystemProvider)
          .writerLinks
          .where((link) => link.saveId == sourceSaveId)
          .map((link) => link.toJson())
          .toList();
      expect(linksBefore, hasLength(2));

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('C').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('barActionCreateStandaloneSave')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('barActionMakeBlockUnique')), findsNothing);
      await tester.tap(find.byKey(const Key('barActionCreateStandaloneSave')));
      await tester.pumpAndSettle();
      expect(find.text('Create standalone Save'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('writerBlockNameField')),
        'Standalone C',
      );
      await tester.tap(find.byKey(const Key('writerBlockNameSave')));
      await tester.pumpAndSettle();

      final saveState = container.read(saveSystemProvider);
      final standalone = saveState.saves.singleWhere(
        (save) => save.id != sourceSaveId,
      );
      expect(standalone.name, 'Standalone C');
      expect(standalone.origin, SaveOrigin.manual);
      expect(standalone.folderId, projectId);
      expect(standalone.snapshot.toJson(), sourceBefore.snapshot.toJson());
      expect(
        saveState.saves.singleWhere((save) => save.id == sourceSaveId).toJson(),
        sourceBefore.toJson(),
      );
      final finalBlocks = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .where((lane) => lane.kind == SongLaneKind.harmony)
          .expand((lane) => lane.blocks)
          .toList();
      expect(finalBlocks.map((block) => block.saveId), [
        sourceSaveId,
        sourceSaveId,
      ]);
      expect(
        saveState.writerLinks
            .where((link) => link.saveId == sourceSaveId)
            .map((link) => link.toJson())
            .toList(),
        linksBefore,
      );
      expect(
        saveState.writerLinks.any((link) => link.saveId == standalone.id),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
