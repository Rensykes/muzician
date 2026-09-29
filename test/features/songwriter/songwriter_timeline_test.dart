import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'strum source choices are Fretboard-only and keep the primary lane ID',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = _createWriterContainer(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
      );
      addTearDown(container.dispose);
      final writer = container.read(songwriterProvider.notifier);
      final section = container.read(songwriterProvider).sections.single;
      final primaryHarmony = section.lanes.firstWhere(
        (lane) => lane.kind == SongLaneKind.harmony,
      );
      writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.harmony,
        label: 'Piano',
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      final strumLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
        label: 'Guitar Strum',
      );
      final patternId = writer.addGuitarStrumPattern(lengthTicks: 16);
      final pattern = container
          .read(songwriterProvider)
          .guitarStrumPatterns
          .single;
      writer.updateGuitarStrumPattern(
        pattern.copyWith(
          events: const [
            GuitarStrumEvent(tick: 12, direction: GuitarStrumDirection.up),
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
            GuitarStrumEvent(tick: 4, direction: GuitarStrumDirection.up),
          ],
        ),
      );
      writer.addGuitarStrumBlock(
        sectionId: section.id,
        laneId: strumLaneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 2,
      );

      await _pumpWriter(tester, container);
      final anchorKey = Key('strumAnchor_${strumLaneId}_0');
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(anchorKey),
      );
      expect(dropdown.value, '');
      expect(dropdown.items!.map((item) => item.value), [
        '',
        primaryHarmony.id,
      ]);
      final preview = tester.widget<Semantics>(
        find.byKey(Key('strumPatternPreview_$patternId')),
      );
      expect(
        preview.properties.label,
        'Ordered strum preview: down at tick 0, up at tick 4, up at tick 12',
      );

      await tester.tap(find.byKey(anchorKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Primary Fretboard'));
      await tester.pumpAndSettle();
      final assignedStrumLane = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == strumLaneId);
      expect(assignedStrumLane.anchorLaneId, primaryHarmony.id);
      expect(
        tester.widget<DropdownButton<String>>(find.byKey(anchorKey)).value,
        primaryHarmony.id,
      );
    },
  );

  testWidgets(
    'melody tiles show exact duration and clipping, with a continuation across rows',
    (tester) async {
      final container = _createWriterContainer(
        defaultInstrument: HarmonyLaneInstrument.fretboard,
        lengthBars: 8,
      );
      addTearDown(container.dispose);
      final writer = container.read(songwriterProvider.notifier);
      final section = container.read(songwriterProvider).sections.single;
      final laneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.melody,
        label: 'Melody',
      );
      final patternId = writer.addMelodyPattern(
        name: 'Long phrase',
        lengthTicks: 25,
      );
      writer.addMelodyBlock(
        sectionId: section.id,
        laneId: laneId,
        patternId: patternId,
        startBar: 3,
        spanBars: 3,
      );
      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .blocks
          .single;
      String? editedPerformancePatternId;

      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpWriter(
        tester,
        container,
        onEditMelodyPerformance: (id) => editedPerformancePatternId = id,
      );
      expect(find.text('Duration: 1 bar + 2 beats + 1 tick'), findsOneWidget);
      expect(
        find.text('Placement: bars 4–6 · repeats, then clips the final pass'),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('writerBlockName_${block.id}_0_4')),
        findsOneWidget,
      );
      expect(find.text('Long phrase · continued'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(900, 1000));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('writerBlockName_${block.id}_0_4')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(Key('melodyBlockActions_${block.id}_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit performance'));
      await tester.pumpAndSettle();
      expect(editedPerformancePatternId, patternId);
    },
  );

  testWidgets('empty melody bars support reuse and grouped creation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _createWriterContainer(
      defaultInstrument: HarmonyLaneInstrument.fretboard,
      lengthBars: 6,
    );
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
      label: 'Melody',
    );
    final patternId = writer.addMelodyPattern(name: 'A', lengthTicks: 32);

    await _pumpWriter(tester, container);
    final undoCount = writer.undoCount;
    await tester.tap(find.byKey(Key('emptyMelodyBar_${laneId}_0_1')));
    await tester.pumpAndSettle();
    expect(find.text('Use existing pattern'), findsOneWidget);
    expect(find.text('Create new pattern'), findsOneWidget);
    await tester.tap(find.byKey(Key('reuseWriterPattern_$patternId')));
    await tester.pumpAndSettle();
    var melodyLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId);
    expect(melodyLane.blocks, hasLength(1));
    expect(melodyLane.blocks.single.patternId, patternId);
    expect(melodyLane.blocks.single.startBar, 1);
    expect(melodyLane.blocks.single.spanBars, 2);
    expect(writer.undoCount, undoCount + 1);

    expect(writer.undo(), isTrue);
    await tester.pumpAndSettle();
    melodyLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId);
    expect(melodyLane.blocks, isEmpty);

    await tester.tap(find.byKey(Key('emptyMelodyBar_${laneId}_0_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('createWriterPattern')));
    await tester.pumpAndSettle();
    melodyLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId);
    expect(melodyLane.blocks, hasLength(1));
    expect(melodyLane.blocks.single.patternId, isNot(patternId));
    expect(melodyLane.blocks.single.spanBars, 1);
    expect(writer.undoCount, undoCount + 1);
    expect(find.byKey(const Key('saveWriterMelodyPattern')), findsOneWidget);
  });

  testWidgets('placement dialog preflights section bounds and overlaps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = _createWriterContainer(
      defaultInstrument: HarmonyLaneInstrument.fretboard,
      lengthBars: 5,
    );
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
      label: 'Melody',
    );
    final patternId = writer.addMelodyPattern(name: 'A', lengthTicks: 16);
    final obstaclePatternId = writer.addMelodyPattern(
      name: 'B',
      lengthTicks: 16,
    );
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 1,
    );
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: obstaclePatternId,
      startBar: 2,
      spanBars: 1,
    );
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .firstWhere((candidate) => candidate.patternId == patternId);

    await _pumpWriter(tester, container);
    await tester.tap(find.byKey(Key('melodyBlockActions_${block.id}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust placement'));
    await tester.pumpAndSettle();

    final startField = find.byKey(const Key('melodyPlacementStartBar'));
    final spanField = find.byKey(const Key('melodyPlacementSpanBars'));
    final applyButton = find.byKey(const Key('applyMelodyPlacement'));
    await tester.enterText(startField, '4');
    await tester.enterText(spanField, '3');
    await tester.pump();
    expect(tester.widget<FilledButton>(applyButton).onPressed, isNull);

    await tester.enterText(startField, '2');
    await tester.enterText(spanField, '2');
    await tester.pump();
    expect(
      find.text('This placement overlaps another block in the lane.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(applyButton).onPressed, isNull);

    await tester.enterText(startField, '1');
    await tester.enterText(spanField, '2');
    await tester.pump();
    expect(tester.widget<FilledButton>(applyButton).onPressed, isNotNull);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    final movedBlock = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == laneId)
        .blocks
        .firstWhere((candidate) => candidate.id == block.id);
    expect(movedBlock.startBar, 0);
    expect(movedBlock.spanBars, 2);
  });
}

ProviderContainer _createWriterContainer({
  required HarmonyLaneInstrument defaultInstrument,
  int lengthBars = 4,
}) {
  final container = ProviderContainer();
  final saves = container.read(saveSystemProvider.notifier);
  final projectId = saves.createProject(
    'Timeline test',
    ProjectConfig(defaultHarmonyInstrument: defaultInstrument),
  )!;
  saves.selectProject(projectId);
  container
      .read(songwriterProvider.notifier)
      .addSection(label: 'Verse', lengthBars: lengthBars);
  return container;
}

Future<void> _pumpWriter(
  WidgetTester tester,
  ProviderContainer container, {
  ValueChanged<String>? onEditMelodyPerformance,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SongwriterScreenSheet(
            onEditMelodyPerformance: onEditMelodyPerformance,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
