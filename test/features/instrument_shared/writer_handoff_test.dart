import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/writer_handoff.dart';
import 'package:muzician/models/harmonic_analysis.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chord = ChordDetectionResult(root: 'C', quality: '');

class _HandoffTestApp extends StatelessWidget {
  const _HandoffTestApp();

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
              binding: fretboardBinding,
              chordResults: const [_chord],
              onTransferComplete: () {},
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

Future<void> _chooseChord(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('startHandoff')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add C as harmony'));
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
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _HandoffTestApp(),
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

      await _chooseChord(tester);

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

  testWidgets('no-project picker cancel leaves both workspaces untouched', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Existing', lengthBars: 4);
    final before = container.read(songwriterProvider);
    await _mountHandoffApp(tester, container);

    await _chooseChord(tester);
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

    await _chooseChord(tester);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelWriterImportName')));
    await tester.pumpAndSettle();

    expect(identical(container.read(songwriterProvider), before), isTrue);
    expect(container.read(saveSystemProvider).writerLinks, isEmpty);
    expect(container.read(saveSystemProvider).saves, isEmpty);
  });

  testWidgets(
    'no-project choice is retained through project and section pickers',
    (tester) async {
      final container = await _newContainer();
      addTearDown(container.dispose);
      final projectId = await _createProject(container, 'New Project');
      container.read(saveSystemProvider.notifier).selectProject(null);
      await _mountHandoffApp(tester, container);

      await _chooseChord(tester);
      await tester.tap(find.text('New Project'));
      await tester.pumpAndSettle();
      expect(container.read(saveSystemProvider).selectedProjectId, projectId);
      await tester.tap(find.text('Create section'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a Writer section and bar'), findsOneWidget);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
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
    writer.addLane(sectionId: sectionId, kind: SongLaneKind.harmony);
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
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

    await _chooseChord(tester);
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
    expect(block.chordNotes, isEmpty);
    await container.read(songwriterSessionsProvider.notifier).flush();
  });

  testWidgets('choosing another bar preserves the occupied block', (
    tester,
  ) async {
    final container = await _newContainer();
    addTearDown(container.dispose);
    await _createProject(container, 'Song project');
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
    );
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

    await _chooseChord(tester);
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
    final laneId = writer.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
    );
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

    await _chooseChord(tester);
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(identical(container.read(songwriterProvider), before), isTrue);

    await _chooseChord(tester);
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

    await _chooseChord(tester);
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

    await _chooseChord(tester);
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
    expect(container.read(songwriterProvider).sections.single.lanes, isEmpty);
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
