import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart' show AudioAsset;
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
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final harmonyLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
    );
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
        selectedKeys: const [],
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
    final harmonyLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
    );
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

    final pianoSaveId = saveSystem.saveSnapshot(
      'Piano save',
      projectId,
      PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const ['C4', 'E4', 'G4'],
        viewMode: PianoViewMode.exact,
      ),
    )!;
    writer.addLibraryBlockAt(
      sectionId: sectionId,
      saveId: pianoSaveId,
      startBar: 2,
      anchorLaneId: harmonyLaneId,
    );

    final drumLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
    );
    final drumPatternId = writer.addDrumPattern(name: 'Beat');
    writer.addDrumBlock(
      sectionId: sectionId,
      laneId: drumLaneId,
      patternId: drumPatternId,
      startBar: 0,
      spanBars: 1,
    );

    final melodyLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.melody,
    );
    final melodyPatternId = writer.addMelodyPattern(name: 'Melody');
    writer.addMelodyBlock(
      sectionId: sectionId,
      laneId: melodyLaneId,
      patternId: melodyPatternId,
      startBar: 0,
      spanBars: 1,
    );

    final strumLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.guitarStrum,
    );
    final strumPatternId = writer.addGuitarStrumPattern(name: 'Strum');
    writer.addGuitarStrumBlock(
      sectionId: sectionId,
      laneId: strumLaneId,
      patternId: strumPatternId,
      startBar: 0,
      spanBars: 1,
    );

    final audioLaneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.audio,
    );
    writer.addAudioAsset(
      const AudioAsset(
        id: 'asset',
        durationMs: 4000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20],
        sourceLabel: 'Recording',
      ),
    );
    final audioClipId = writer.addAudioClip(assetId: 'asset', durationMs: 4000);
    writer.addAudioBlock(
      sectionId: sectionId,
      laneId: audioLaneId,
      audioClipId: audioClipId,
      startBar: 0,
      spanBars: 1,
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

    Future<void> expectSheetActions(Finder blockFinder) async {
      await tester.ensureVisible(blockFinder);
      await tester.tap(blockFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barActionRenameBlock')), findsOneWidget);
      expect(find.byKey(const Key('barActionMakeBlockUnique')), findsOneWidget);
      await tester.tap(find.byKey(const Key('barActionRenameBlock')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('writerBlockNameCancel')));
      await tester.pumpAndSettle();
    }

    await expectSheetActions(find.text('C').first);
    await expectSheetActions(find.byKey(Key('silentCell_${silence.id}_0')));
    await expectSheetActions(find.byKey(Key('saveCell_${saveBlock.id}_0')));
    await expectPopupActions(drum);
    await expectPopupActions(melody);
    await expectPopupActions(strum);
    await expectPopupActions(audio);
    expect(tester.takeException(), isNull);
  });
}
