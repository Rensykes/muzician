import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/writer_handoff.dart';
import 'package:muzician/features/instrument_shared/instrument_binding.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmonic_analysis.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;
import 'package:shared_preferences/shared_preferences.dart';

const _chord = ChordDetectionResult(root: 'C', quality: '');

class _HandoffTestApp extends StatelessWidget {
  const _HandoffTestApp({
    this.reuseSave,
    this.binding,
    this.onTransferComplete,
    this.chordResults = const [_chord],
  });

  final SaveEntry? reuseSave;
  final InstrumentBinding? binding;
  final VoidCallback? onTransferComplete;
  final List<ChordDetectionResult> chordResults;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('startHandoff'),
            onPressed: () => startWriterHandoff(
              context: context,
              ref: ref,
              binding: binding ?? fretboardBinding,
              chordResults: chordResults,
              onTransferComplete: onTransferComplete ?? () {},
              reuseSave: reuseSave,
            ),
            child: const Text('Start handoff'),
          ),
        ),
      ),
    ),
  );
}

Future<ProviderContainer> _newContainer() async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  await container.read(saveSystemProvider.notifier).hydrate();
  return container;
}

Future<String> _createProject(ProviderContainer container, String name) async {
  final notifier = container.read(saveSystemProvider.notifier);
  final id = notifier.createProject(name, const ProjectConfig())!;
  notifier.selectProject(id);
  return id;
}

Future<void> _chooseChord(
  WidgetTester tester,
  ProviderContainer container, {
  String choiceLabel = 'Add C as harmony',
}) async {
  final fretboard = container.read(fretboardProvider.notifier);
  fretboard.setInputMode(FretboardInputMode.chord);
  fretboard.clearSelectedNotes();
  fretboard.toggleCell(4, 3, 'C');
  fretboard.toggleCell(3, 2, 'E');
  fretboard.toggleCell(2, 0, 'G');
  await tester.tap(find.byKey(const Key('startHandoff')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(choiceLabel));
  await tester.pumpAndSettle();
}

Future<void> _chooseDSharpMinorSlashChord(
  WidgetTester tester,
  ProviderContainer container, {
  required String choiceLabel,
}) async {
  final fretboard = container.read(fretboardProvider.notifier);
  fretboard.setInputMode(FretboardInputMode.chord);
  fretboard.clearSelectedNotes();
  fretboard.toggleCell(4, 3, 'D#');
  fretboard.toggleCell(3, 2, 'F#');
  fretboard.toggleCell(2, 0, 'A#');
  await tester.tap(find.byKey(const Key('startHandoff')));
  await tester.pumpAndSettle();
  expect(find.text(choiceLabel), findsOneWidget);
  await tester.tap(find.text(choiceLabel));
  await tester.pumpAndSettle();
}

Future<void> _chooseExactHarmony(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final fretboard = container.read(fretboardProvider.notifier);
  fretboard.setInputMode(FretboardInputMode.chord);
  fretboard.clearSelectedNotes();
  fretboard.toggleCell(4, 3, 'C');
  fretboard.toggleCell(3, 2, 'E');
  fretboard.toggleCell(2, 0, 'G');
  await tester.tap(find.byKey(const Key('startHandoff')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add exact notes as Harmony'));
  await tester.pumpAndSettle();
}

Future<void> _confirmImportName(WidgetTester tester, {String? name}) async {
  expect(find.byKey(const Key('writerImportNameField')), findsOneWidget);
  if (name != null) {
    await tester.enterText(
      find.byKey(const Key('writerImportNameField')),
      name,
    );
  }
  await tester.tap(find.byKey(const Key('confirmWriterImportName')));
  await tester.pumpAndSettle();
}

Future<void> _mountHandoffApp(
  WidgetTester tester,
  ProviderContainer container, {
  InstrumentBinding? binding,
  VoidCallback? onTransferComplete,
  SaveEntry? reuseSave,
  List<ChordDetectionResult> chordResults = const [_chord],
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _HandoffTestApp(
        reuseSave: reuseSave,
        binding: binding,
        onTransferComplete: onTransferComplete,
        chordResults: chordResults,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final viewport in const [
    (name: 'compact portrait', size: Size(390, 844)),
    (name: 'wide landscape', size: Size(1180, 820)),
  ]) {
    testWidgets('handoff picker and name prompt fit ${viewport.name}', (
      tester,
    ) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _newContainer();
      addTearDown(container.dispose);
      await _createProject(container, 'Viewport project');
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'Verse', lengthBars: 4);
      await _mountHandoffApp(tester, container);

      await _chooseChord(tester, container);

      final sectionId = container.read(songwriterProvider).sections.single.id;
      expect(find.text('Choose a Writer section and bar'), findsOneWidget);
      expect(
        find.byKey(Key('writerHandoffBar_${sectionId}_0')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('writerImportNameField')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('cancelWriterImportName')));
      await tester.pumpAndSettle();
      await container.read(songwriterSessionsProvider.notifier).flush();
    });
  }

  testWidgets(
    'slash chord transfer keeps canonical music across live spelling changes',
    (tester) async {
      final container = await _newContainer();
      addTearDown(container.dispose);
      await _createProject(container, 'Slash chord spelling');
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'Verse', lengthBars: 4);
      await container
          .read(settingsProvider.notifier)
          .setNoteSpelling(NoteSpelling.sharps);
      await _mountHandoffApp(
        tester,
        container,
        chordResults: const [
          ChordDetectionResult(root: 'D#', quality: 'm', bass: 'A#'),
        ],
      );

      final sectionId = container.read(songwriterProvider).sections.single.id;
      final fretboard = container.read(fretboardProvider.notifier);
      fretboard.setInputMode(FretboardInputMode.chord);
      fretboard.clearSelectedNotes();
      fretboard.toggleCell(4, 3, 'D#');
      fretboard.toggleCell(3, 2, 'F#');
      fretboard.toggleCell(2, 0, 'A#');
      await tester.tap(find.byKey(const Key('startHandoff')));
      await tester.pumpAndSettle();
      expect(find.text('Add D#m/A# as harmony'), findsOneWidget);
      await container
          .read(settingsProvider.notifier)
          .setNoteSpelling(NoteSpelling.flats);
      await tester.pumpAndSettle();
      expect(find.text('Add D#m/A# as harmony'), findsNothing);
      expect(find.text('Add Ebm/Bb as harmony'), findsOneWidget);
      await tester.tap(find.text('Add Ebm/Bb as harmony'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
      await tester.pumpAndSettle();
      await _confirmImportName(tester, name: 'D# idea');

      await container
          .read(settingsProvider.notifier)
          .setNoteSpelling(NoteSpelling.sharps);
      await tester.pumpAndSettle();
      await _chooseDSharpMinorSlashChord(
        tester,
        container,
        choiceLabel: 'Add D#m/A# as harmony',
      );
      await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_1')));
      await tester.pumpAndSettle();
      await _confirmImportName(tester, name: 'D# idea');

      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.singleWhere(
        (candidate) =>
            candidate.kind == SongLaneKind.harmony &&
            candidate.harmonyInstrument == HarmonyLaneInstrument.fretboard,
      );
      final blocks = lane.blocks.toList()
        ..sort((a, b) => a.startBar.compareTo(b.startBar));
      expect(blocks, hasLength(2));
      for (final block in blocks) {
        expect(block.chordSymbol, 'D#m/A#');
        expect(block.chordRootPc, 3);
        expect(block.chordQuality, 'm');
        expect(block.chordNotes.toSet(), {'D#', 'F#', 'A#'});
      }
      final saves = container.read(saveSystemProvider).saves;
      final linkedSaves = blocks
          .map((block) => saves.singleWhere((save) => save.id == block.saveId))
          .toList();
      expect(linkedSaves.map((save) => save.name), ['D# idea', 'D# idea']);
      expect(
        linkedSaves.map(
          (save) =>
              (save.snapshot as HarmonyChordSnapshot).writerBlock.chordSymbol,
        ),
        ['D#m/A#', 'D#m/A#'],
      );
    },
  );

  testWidgets(
    'exact handoff creates Harmony with the chosen name and native shape',
    (tester) async {
      final container = await _newContainer();
      addTearDown(container.dispose);
      await _createProject(container, 'Instrument-specific handoff');
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final fretboardHarmonyId = section.lanes
          .singleWhere(
            (lane) =>
                lane.kind == SongLaneKind.harmony &&
                lane.harmonyInstrument == HarmonyLaneInstrument.fretboard,
          )
          .id;
      final pianoHarmonyId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      final pianoSaveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: pianoSaveLaneId,
        harmonyLaneId: pianoHarmonyId,
      );
      await _mountHandoffApp(tester, container);

      await _chooseExactHarmony(tester, container);

      expect(
        find.byKey(Key('writerHandoffLane_${section.id}_$pianoSaveLaneId')),
        findsNothing,
      );
      expect(fretboardHarmonyId, isNotEmpty);
      await tester.tap(find.byKey(Key('writerHandoffBar_${section.id}_0')));
      await tester.pumpAndSettle();
      await _confirmImportName(tester, name: 'Fretboard C');

      final currentSection = container.read(songwriterProvider).sections.single;
      final pianoSaveLane = currentSection.lanes.singleWhere(
        (lane) => lane.id == pianoSaveLaneId,
      );
      expect(pianoSaveLane.blocks, isEmpty);
      final fretboardHarmonyLane = currentSection.lanes.singleWhere(
        (lane) =>
            lane.kind == SongLaneKind.harmony &&
            lane.harmonyInstrument == HarmonyLaneInstrument.fretboard,
      );
      final block = fretboardHarmonyLane.blocks.single;
      expect(block.startBar, 0);
      expect(block.chordSymbol, 'Fretboard C');
      expect(block.chordRootPc, isNull);
      expect(block.chordQuality, isNull);
      final save = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == block.saveId);
      expect(save.name, 'Fretboard C');
      expect(save.snapshot, isA<HarmonyChordSnapshot>());
      final harmony = save.snapshot as HarmonyChordSnapshot;
      expect(harmony.writerBlock.chordRootPc, isNull);
      expect(harmony.writerBlock.chordQuality, isNull);
      expect(harmony.writerBlock.chordSymbol, 'Fretboard C');
      expect(harmony.instrumentState, isA<FretboardSnapshot>());
      expect(
        (harmony.instrumentState as FretboardSnapshot).inputMode,
        FretboardInputMode.chord,
      );
      expect(
        (harmony.instrumentState as FretboardSnapshot).selectedCells,
        hasLength(3),
      );
      await container.read(songwriterSessionsProvider.notifier).flush();
    },
  );

  testWidgets('Piano exact handoff keeps its native selection in Harmony', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Piano exact handoff');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    writer.addHarmonyLane(
      sectionId: section.id,
      harmonyInstrument: HarmonyLaneInstrument.piano,
    );
    container.read(pianoProvider.notifier).loadExactMidis(const [60, 64, 67]);
    await _mountHandoffApp(tester, container, binding: pianoBinding);

    await tester.tap(find.byKey(const Key('startHandoff')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add exact notes as Harmony'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerHandoffBar_${section.id}_0')));
    await tester.pumpAndSettle();
    await _confirmImportName(tester, name: 'Piano cluster');

    final placedLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere(
          (lane) =>
              lane.kind == SongLaneKind.harmony &&
              lane.harmonyInstrument == HarmonyLaneInstrument.piano,
        );
    final block = placedLane.blocks.single;
    expect(block.chordSymbol, 'Piano cluster');
    expect(block.chordRootPc, isNull);
    expect(block.chordQuality, isNull);
    final saved = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((save) => save.id == block.saveId);
    expect(saved.name, 'Piano cluster');
    expect(saved.snapshot, isA<HarmonyChordSnapshot>());
    final harmony = saved.snapshot as HarmonyChordSnapshot;
    expect(harmony.harmonyInstrument, HarmonyLaneInstrument.piano);
    expect(harmony.writerBlock.chordSymbol, 'Piano cluster');
    expect(harmony.writerBlock.chordRootPc, isNull);
    expect(harmony.writerBlock.chordQuality, isNull);
    expect(harmony.writerBlock.chordNotes.toSet(), {'C', 'E', 'G'});
    expect(harmony.instrumentState, isA<PianoSnapshot>());
    expect(
      (harmony.instrumentState as PianoSnapshot).selectedKeys,
      hasLength(3),
    );
    await container.read(songwriterSessionsProvider.notifier).flush();
  });

  testWidgets('rejected Piano Harmony Save explains its eligibility issue', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final projectId = await _createProject(container, 'Invalid Piano Harmony');
    final piano = PianoSnapshot(
      currentRange: PianoRangeName.key88,
      selectedKeys: const [
        PianoCoordinate(keyIndex: 39, midiNote: 60, noteName: 'C'),
        PianoCoordinate(keyIndex: 41, midiNote: 62, noteName: 'D'),
        PianoCoordinate(keyIndex: 44, midiNote: 65, noteName: 'F'),
      ],
      selectedNotes: const ['C', 'D', 'F'],
      viewMode: PianoViewMode.exact,
    );
    final saveId = container
        .read(saveSystemProvider.notifier)
        .saveSnapshot(
          'Mismatched Piano Harmony',
          projectId,
          HarmonyChordSnapshot(
            harmonyInstrument: HarmonyLaneInstrument.piano,
            writerBlock: const WriterBlockSnapshot(
              laneKind: SongLaneKind.harmony,
              chordSymbol: 'C',
              chordQuality: '',
              chordRootPc: 0,
              chordNotes: ['C', 'E', 'G'],
            ),
            instrumentState: piano,
          ),
        );
    expect(saveId, isNotNull);
    final save = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((candidate) => candidate.id == saveId);
    await _mountHandoffApp(
      tester,
      container,
      binding: pianoBinding,
      reuseSave: save,
    );

    await tester.tap(find.byKey(const Key('startHandoff')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Piano Harmony saves need valid selected keys and matching Harmony notes to enter Writer.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Fretboard'), findsNothing);
    expect(find.text('Choose a Writer section and bar'), findsNothing);
    expect(find.byKey(const Key('writerImportNameField')), findsNothing);
  });

  testWidgets('no-project picker cancel leaves both workspaces untouched', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Existing', lengthBars: 4);
    final before = container.read(songwriterProvider);
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    expect(find.text('PROJECTS'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(container.read(saveSystemProvider).selectedProjectId, isNull);
    expect(identical(container.read(songwriterProvider), before), isTrue);
  });

  testWidgets('canceling the import name leaves no block or save', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Named handoff project');
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'Verse', lengthBars: 4);
    final before = container.read(songwriterProvider);
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelWriterImportName')));
    await tester.pumpAndSettle();

    expect(identical(container.read(songwriterProvider), before), isTrue);
    expect(container.read(saveSystemProvider).writerLinks, isEmpty);
    expect(container.read(saveSystemProvider).saves, isEmpty);
  });

  testWidgets('canceling a staged first section leaves no empty section', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'First section project');
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    await tester.tap(find.text('Create section'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerHandoffBar_new_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelWriterImportName')));
    await tester.pumpAndSettle();

    expect(container.read(songwriterProvider).sections, isEmpty);
    expect(container.read(saveSystemProvider).writerLinks, isEmpty);
    expect(container.read(saveSystemProvider).saves, isEmpty);
  });

  testWidgets('Use in Writer reuses a Harmony Save from its section folder', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final projectId = await _createProject(
      container,
      'Harmony library project',
    );
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final sourceLane = section.lanes.single;
    final result = writer.addHarmonyChord(
      sectionId: section.id,
      laneId: sourceLane.id,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
      saveName: 'C major',
    );
    expect(result.success, isTrue);
    final sourceBlock = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    final sourceSave = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((save) => save.id == sourceBlock.saveId);
    expect(sourceSave.folderId, isNot(projectId));

    writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
      label: 'Second Fretboard lane',
      harmonyInstrument: HarmonyLaneInstrument.fretboard,
    );
    final destinationLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .last;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _HandoffTestApp(reuseSave: sourceSave),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startHandoff')));
    await tester.pumpAndSettle();
    final destinationLaneKey = Key(
      'writerHandoffLane_${section.id}_${destinationLane.id}',
    );
    expect(find.byKey(destinationLaneKey), findsOneWidget);
    await tester.tap(find.byKey(destinationLaneKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerHandoffBar_${section.id}_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('writerImportNameField')), findsNothing);
    final destinationBlock = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == destinationLane.id)
        .blocks
        .single;
    expect(destinationBlock.startBar, 1);
    expect(destinationBlock.saveId, sourceSave.id);
    expect(
      container
          .read(saveSystemProvider)
          .saves
          .where((save) => save.id == sourceSave.id),
      hasLength(1),
    );
  });

  testWidgets(
    'no-project choice is retained through project and section pickers',
    (tester) async {
      final container = await _newContainer();
      addTearDown(container.dispose);
      final projectId = await _createProject(container, 'New Project');
      container.read(saveSystemProvider.notifier).selectProject(null);
      await _mountHandoffApp(tester, container);

      await _chooseChord(tester, container);
      await tester.tap(find.text('New Project'));
      await tester.pumpAndSettle();
      expect(container.read(saveSystemProvider).selectedProjectId, projectId);
      await tester.tap(find.text('Create section'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a Writer section and bar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('writerHandoffBar_new_0')));
      await tester.pumpAndSettle();
      await _confirmImportName(tester, name: 'Verse entry');
      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(block.chordSymbol, 'C');
      expect(block.startBar, 0);
      expect(block.saveId, isNotNull);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == block.saveId)
            .name,
        'Verse entry',
      );
      await container.read(songwriterSessionsProvider.notifier).flush();
    },
  );

  testWidgets('occupied bar is announced and replacement needs confirmation', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Song project');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .first
        .id;
    writer.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'F',
        chordQuality: '',
        chordRootPc: 5,
        chordNotes: const ['F', 'A', 'C'],
      ),
    );
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Verse, bar 1, Occupied'), findsOneWidget);
    semantics.dispose();
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    expect(find.text('Bar 1 is occupied'), findsOneWidget);
    await tester.tap(find.text('Replace…'));
    await tester.pumpAndSettle();
    expect(find.text('Replace the whole block?'), findsOneWidget);
    await tester.tap(find.text('Replace block'));
    await tester.pumpAndSettle();
    await _confirmImportName(tester);

    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(block.chordSymbol, 'C');
    expect(block.chordNotes, ['C', 'E', 'G']);
    await container.read(songwriterSessionsProvider.notifier).flush();
  });

  testWidgets('occupied exact replacement completes once with changed notes', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final projectId = await _createProject(container, 'Exact replacement');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final lane = section.lanes.single;
    final originalNative = FretboardSnapshot(
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
    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: section.id,
        laneId: lane.id,
        startBar: 0,
        snapshot: originalNative,
        asExactHarmony: true,
        chordSymbol: 'Old exact notes',
        saveName: 'Old exact notes',
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
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
    var transferCount = 0;
    await _mountHandoffApp(
      tester,
      container,
      onTransferComplete: () => transferCount++,
    );

    await _chooseExactHarmony(tester, container);
    await tester.tap(find.byKey(Key('writerHandoffBar_${section.id}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace block'));
    await tester.pumpAndSettle();
    await _confirmImportName(tester, name: 'New exact notes');

    final replaced = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(replaced.id, original.id);
    expect(replaced.chordSymbol, 'New exact notes');
    expect(replaced.chordRootPc, isNull);
    expect(replaced.chordQuality, isNull);
    expect(replaced.chordNotes.toSet(), {'C', 'E', 'G'});
    expect(transferCount, 1);
    expect(find.text('Choose a Writer section and bar'), findsNothing);
    expect(find.byKey(const Key('writerImportNameField')), findsNothing);
  });

  testWidgets('occupied Piano D-sharp 4 exact Harmony replaces once with D4', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final saves = container.read(saveSystemProvider.notifier);
    final projectId = saves.createProject(
      'Piano exact replacement',
      const ProjectConfig(
        defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
      ),
    )!;
    saves.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    await writer.reconcileCurrentProject();
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
        chordSymbol: 'D sharp four',
        saveName: 'D sharp four',
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
    container.read(pianoProvider.notifier).loadExactMidis(const [62]);
    var transferCount = 0;
    await _mountHandoffApp(
      tester,
      container,
      binding: pianoBinding,
      onTransferComplete: () => transferCount++,
    );

    await tester.tap(find.byKey(const Key('startHandoff')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add exact notes as Harmony'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerHandoffBar_${section.id}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace block'));
    await tester.pumpAndSettle();
    await _confirmImportName(tester, name: 'D4 exact');

    final replaced = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(replaced.id, original.id);
    expect(replaced.chordSymbol, 'D4 exact');
    expect(replaced.chordRootPc, isNull);
    expect(replaced.chordQuality, isNull);
    expect(replaced.chordNotes, ['D']);
    final native = (replaced.embedded as HarmonyChordSnapshot).instrumentState;
    expect((native as PianoSnapshot).selectedKeys.single.midiNote, 62);
    expect(transferCount, 1);
    expect(find.text('Choose a Writer section and bar'), findsNothing);
  });

  testWidgets(
    'failed exact replacement gives feedback and does not reopen picker',
    (tester) async {
      final container = await _newContainer();
      addTearDown(container.dispose);
      await _createProject(container, 'Rejected replacement');
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final lane = section.lanes.single;
      writer.addHarmonyBlock(
        sectionId: section.id,
        laneId: lane.id,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'F',
          chordQuality: '',
          chordRootPc: 5,
          chordNotes: const ['F', 'A', 'C'],
        ),
      );
      var transferCount = 0;
      await _mountHandoffApp(
        tester,
        container,
        onTransferComplete: () => transferCount++,
      );

      await _chooseExactHarmony(tester, container);
      await tester.tap(find.byKey(Key('writerHandoffBar_${section.id}_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace block'));
      await tester.pumpAndSettle();

      final occupied = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      writer.removeBlock(
        sectionId: section.id,
        laneId: lane.id,
        blockId: occupied.id,
      );
      await _confirmImportName(tester, name: 'Cannot place');

      expect(find.text('Choose a Writer section and bar'), findsNothing);
      expect(find.byKey(const Key('writerImportNameField')), findsNothing);
      expect(
        find.text(
          'That Writer bar is no longer available. Start again to choose another bar.',
        ),
        findsOneWidget,
      );
      expect(transferCount, 0);
      expect(
        container.read(songwriterProvider).sections.single.lanes.single.blocks,
        isEmpty,
      );
    },
  );

  testWidgets('choosing another bar preserves the occupied block', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Song project');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .first
        .id;
    writer.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'F',
        chordQuality: '',
        chordRootPc: 5,
        chordNotes: const ['F', 'A', 'C'],
      ),
    );
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose another bar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_1')));
    await tester.pumpAndSettle();
    await _confirmImportName(tester);

    final blocks = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks;
    expect(blocks, hasLength(2));
    expect(blocks.first.chordSymbol, 'F');
    expect(blocks.last.chordSymbol, 'C');
    expect(blocks.last.startBar, 1);
  });

  testWidgets('canceling occupancy and replacement leaves the lane unchanged', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Song project');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .first
        .id;
    writer.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'F',
        chordQuality: '',
        chordRootPc: 5,
        chordNotes: const ['F', 'A', 'C'],
      ),
    );
    final before = container.read(songwriterProvider);
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(identical(container.read(songwriterProvider), before), isTrue);

    await _chooseChord(tester, container);
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep existing'));
    await tester.pumpAndSettle();
    expect(identical(container.read(songwriterProvider), before), isTrue);
  });

  testWidgets('expanded repeated bars are occupied and replace their source', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Song project');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 6);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 0,
        chordSymbol: 'F',
        chordQuality: '',
        chordRootPc: 5,
        chordNotes: const ['F', 'A', 'C'],
      ),
      isTrue,
    );
    final sourceSection = container.read(songwriterProvider).sections.single;
    final sourceLane = sourceSection.lanes.single;
    final source = sourceLane.blocks.single;
    writer.setLaneRepeat(
      sectionId: sectionId,
      laneId: sourceLane.id,
      repeat: 3,
    );
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Verse, bar 3, Occupied'), findsOneWidget);
    semantics.dispose();
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Replacing it changes every copy together'),
      findsOneWidget,
    );
    await tester.tap(find.text('Replace block'));
    await tester.pumpAndSettle();
    await _confirmImportName(tester);

    final section = container.read(songwriterProvider).sections.single;
    final lane = section.lanes.single;
    final updatedSource = lane.blocks.single;
    expect(updatedSource.id, source.id);
    expect(updatedSource.startBar, source.startBar);
    expect(updatedSource.spanBars, source.spanBars);
    expect(lane.repeat, 3);
    expect(
      tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      ).map((block) => (block.startBar, block.chordSymbol)).toList(),
      [(0, 'C'), (1, 'C'), (2, 'C')],
    );
    await container.read(songwriterSessionsProvider.notifier).flush();
  });

  testWidgets('project switch while choosing a bar cancels the handoff', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final firstProjectId = await _createProject(container, 'First project');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'First section', lengthBars: 4);
    final firstSectionId = container
        .read(songwriterProvider)
        .sections
        .single
        .id;
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester, container);
    final secondProjectId = await _createProject(container, 'Second project');
    container.read(saveSystemProvider.notifier).selectProject(secondProjectId);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'Second section', lengthBars: 4);
    final secondSectionId = container
        .read(songwriterProvider)
        .sections
        .single
        .id;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('writerHandoffBar_${secondSectionId}_0')));
    await tester.pumpAndSettle();

    expect(find.text('Destination changed'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final secondSection = container.read(songwriterProvider).sections.single;
    expect(secondSection.lanes, hasLength(1));
    expect(secondSection.lanes.single.blocks, isEmpty);
    expect(
      container.read(songwriterSessionsProvider).containsKey(firstProjectId),
      isTrue,
    );
    expect(
      container
          .read(songwriterSessionsProvider)[firstProjectId]!
          .sections
          .single
          .id,
      firstSectionId,
    );
    await container.read(songwriterSessionsProvider.notifier).flush();
  });
}
