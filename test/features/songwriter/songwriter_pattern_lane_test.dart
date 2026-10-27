import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/features/songwriter/guitar_strum_pattern_sheet.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/theme/studio_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('placement dialog moves and resizes a melody', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final patternId = writer.addMelodyPattern();
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 1,
    );
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(Key('melodyBlockActions_${block.id}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust placement'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('melodyPlacementStartBar')),
      '3',
    );
    await tester.enterText(
      find.byKey(const Key('melodyPlacementSpanBars')),
      '2',
    );
    await tester.tap(find.byKey(const Key('applyMelodyPlacement')));
    await tester.pumpAndSettle();
    final moved = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;
    expect((moved.startBar, moved.spanBars), (2, 2));
  });

  testWidgets('dragging the resize edge does not scroll the Writer sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final patternId = writer.addMelodyPattern();
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 3,
    );
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final handle = find.byKey(Key('melodyResize_${block.id}_0'));
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final scrollable = Scrollable.of(tester.element(handle));
    final before = scrollable.position.pixels;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-120, 65));
    await tester.pump();
    expect(scrollable.position.pixels, before);
    await gesture.cancel();
  });

  testWidgets('creating beyond automatic repeats does not orphan a pattern', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final patternId = writer.addMelodyPattern();
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 2,
    );
    writer.setLaneRepeat(sectionId: section.id, laneId: laneId, repeat: 3);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(Key('emptyMelodyBar_${laneId}_0_6')));
    await tester.pumpAndSettle();
    expect(find.textContaining('automatic repeats'), findsOneWidget);
    expect(container.read(songwriterProvider).melodyPatterns.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing melody pattern remains visible and removable', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final patternId = writer.addMelodyPattern(name: 'Lost');
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 1,
    );
    final project = container.read(songwriterProvider);
    final block = project.sections.single.lanes
        .firstWhere((l) => l.id == laneId)
        .blocks
        .single;
    await writer.loadProject(project.copyWith(melodyPatterns: []));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(Key('melodySegment_${block.id}_0_0_0')), findsOneWidget);
    expect(find.text('Missing pattern'), findsWidgets);
    expect(find.byKey(Key('melodyBlockActions_${block.id}_0')), findsOneWidget);
    await tester.tap(find.byKey(Key('writerBrokenReference_${block.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Missing melody pattern'), findsOneWidget);
    expect(find.text('Delete block'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final variant in AppThemeVariant.values) {
    for (final width in [320.0, 390.0, 1024.0]) {
      testWidgets('melody controls fit $width ${variant.name}', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final writer = container.read(songwriterProvider.notifier);
        writer.addSection(lengthBars: 8);
        final section = container.read(songwriterProvider).sections.single;
        final laneId = writer.addLane(
          sectionId: section.id,
          kind: SongLaneKind.melody,
        );
        final patternId = writer.addMelodyPattern(name: 'Lead');
        writer.addMelodyBlock(
          sectionId: section.id,
          laneId: laneId,
          patternId: patternId,
          startBar: 0,
          spanBars: 6,
        );
        final block = container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .firstWhere((l) => l.id == laneId)
            .blocks
            .single;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: StudioTheme.data(variant),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.5 : 1),
                ),
                child: child!,
              ),
              home: const Scaffold(body: SongwriterScreenSheet()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getSize(find.byKey(Key('editMelodyBlock_${block.id}_0')))
              .width,
          greaterThanOrEqualTo(44),
        );
        expect(
          tester
              .getSize(find.byKey(Key('melodyBlockActions_${block.id}_0')))
              .width,
          greaterThanOrEqualTo(44),
        );
        await tester.ensureVisible(
          find.byKey(Key('melodyBlockActions_${block.id}_0')),
        );
        await tester.tap(find.byKey(Key('melodyBlockActions_${block.id}_0')));
        await tester.pumpAndSettle();
        expect(find.text('Adjust placement'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('resize stops at a neighbor and at the section boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final a = writer.addMelodyPattern(name: 'A');
    final b = writer.addMelodyPattern(name: 'B');
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: a,
      startBar: 0,
      spanBars: 1,
    );
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: b,
      startBar: 3,
      spanBars: 1,
    );
    List<SongBlock> blocks() => container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneId)
        .blocks;
    final firstId = blocks().first.id;
    final secondId = blocks().last.id;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.drag(
      find.byKey(Key('melodyResize_${firstId}_0')),
      const Offset(500, 0),
    );
    await tester.pump();
    expect(blocks().first.spanBars, 3);
    final secondHandle = find.byKey(Key('melodyResize_${secondId}_0'));
    await tester.ensureVisible(secondHandle);
    final gesture = await tester.startGesture(tester.getCenter(secondHandle));
    await gesture.moveTo(
      tester.getBottomRight(find.byKey(Key('emptyMelodyBar_${laneId}_0_7'))) +
          const Offset(100, 0),
    );
    await gesture.up();
    await tester.pump();
    expect(blocks().last.endBar, 8);
  });

  testWidgets(
    'automatic occurrences remain visible and explain resize conflicts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final laneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.melody,
      );
      final patternId = writer.addMelodyPattern(name: 'Lead');
      writer.addMelodyBlock(
        sectionId: section.id,
        laneId: laneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 2,
      );
      writer.setLaneRepeat(sectionId: section.id, laneId: laneId, repeat: 3);
      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.id == laneId)
          .blocks
          .single;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(Key('melodySegment_${block.id}_0_1_2')),
        findsOneWidget,
      );
      expect(find.textContaining('repeat'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Automatic repeat of Lead, bars 3 through 4',
        ),
        findsOneWidget,
      );
      final before = writer.undoCount;
      await tester.drag(
        find.byKey(Key('melodyResize_${block.id}_0')),
        const Offset(100, 0),
      );
      await tester.pump();
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .firstWhere((l) => l.id == laneId)
            .blocks
            .single
            .spanBars,
        2,
      );
      expect(writer.undoCount, before);
      await tester.tap(find.byKey(Key('melodyBlockActions_${block.id}_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjust placement'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('melodyPlacementSpanBars')),
        '3',
      );
      await tester.pump();
      expect(
        find.textContaining('conflicts with automatic repeats'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('applyMelodyPlacement')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'resize preview can cross a row and cancellation preserves history',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final laneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.melody,
      );
      final patternId = writer.addMelodyPattern();
      writer.addMelodyBlock(
        sectionId: section.id,
        laneId: laneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 3,
      );
      SongBlock block() => container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.id == laneId)
          .blocks
          .single;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final handle = find.byKey(Key('melodyResize_${block().id}_0'));
      await tester.ensureVisible(handle);
      final before = writer.undoCount;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      final target = tester.getCenter(
        find.byKey(Key('emptyMelodyBar_${laneId}_0_5')),
      );
      await gesture.moveTo(target);
      await tester.pump();
      expect(block().spanBars, 3);
      await gesture.cancel();
      await tester.pump();
      expect(block().spanBars, 3);
      expect(writer.undoCount, before);
      final second = await tester.startGesture(tester.getCenter(handle));
      await second.moveTo(target);
      await tester.pump();
      await second.up();
      await tester.pump();
      expect(block().spanBars, greaterThan(4));
      expect(writer.undoCount, before + 1);
    },
  );

  testWidgets('six-bar melody wraps with one resize handle', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
    );
    final patternId = writer.addMelodyPattern(name: 'Lead');
    writer.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 6,
    );
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(Key('melodySegment_${block.id}_0_0_0')), findsOneWidget);
    expect(find.byKey(Key('melodySegment_${block.id}_0_0_4')), findsOneWidget);
    expect(find.byKey(Key('melodyResize_${block.id}_0')), findsOneWidget);
    expect(find.text('Bar 5'), findsWidgets);
    final before = writer.undoCount;
    final handle = find.byKey(Key('melodyResize_${block.id}_0'));
    await tester.ensureVisible(handle);
    await tester.drag(handle, const Offset(-85, 0));
    await tester.pump();
    final resized = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    expect(resized.spanBars, lessThan(6));
    expect(writer.undoCount, before + 1);
    expect(writer.undo(), isTrue);
    expect(
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((lane) => lane.id == laneId)
          .blocks
          .single
          .spanBars,
      6,
    );
  });

  testWidgets('section menu creates an editable melody pattern lane', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addMelodyLaneSheetAction')));
    await tester.pumpAndSettle();

    final project = container.read(songwriterProvider);
    final lane = project.sections.single.lanes.singleWhere(
      (candidate) => candidate.kind == SongLaneKind.melody,
    );
    expect(lane.blocks.single.spanBars, 4);
    expect(find.byKey(Key('sheetMelodyLane_${lane.id}_0')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Edit melody pattern Melody. Pattern duration 1 bar. '
                    'Placed bars 1 through 4. repeats ×4 to fill.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(Key('sheetMelodyTile_${lane.blocks.single.patternId}_0_0')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saveWriterMelodyPattern')), findsOneWidget);
  });

  testWidgets('section menu hides guitar strum without a Fretboard lane', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final harmonyLane = section.lanes.single;
    notifier.setHarmonyLaneInstrument(
      sectionId: section.id,
      laneId: harmonyLane.id,
      instrument: HarmonyLaneInstrument.piano,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('addGuitarStrumLaneSheetAction')),
      findsNothing,
    );
    expect(container.read(songwriterProvider).guitarStrumPatterns, isEmpty);
  });

  testWidgets('stale guitar strum menu action creates no orphan pattern', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final harmonyLane = section.lanes.single;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('addGuitarStrumLaneSheetAction')),
      findsOneWidget,
    );

    notifier.removeLane(sectionId: section.id, laneId: harmonyLane.id);
    await tester.tap(find.byKey(const Key('addGuitarStrumLaneSheetAction')));
    await tester.pumpAndSettle();

    final updatedSection = container.read(songwriterProvider).sections.single;
    expect(
      updatedSection.lanes.where(
        (lane) => lane.kind == SongLaneKind.guitarStrum,
      ),
      isEmpty,
    );
    expect(container.read(songwriterProvider).guitarStrumPatterns, isEmpty);
  });

  testWidgets(
    'strum source selector hides occupied lanes and keeps labels stable',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songwriterProvider.notifier);
      notifier.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final primaryId = section.lanes.single.id;
      notifier.setHarmonyLaneInstrument(
        sectionId: section.id,
        laneId: primaryId,
        instrument: HarmonyLaneInstrument.fretboard,
      );
      final secondHarmonyId = notifier.addLane(
        sectionId: section.id,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      final thirdHarmonyId = notifier.addLane(
        sectionId: section.id,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      final firstStrumId = notifier.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      final secondStrumId = notifier.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      notifier.setLaneAnchorLane(
        sectionId: section.id,
        laneId: firstStrumId,
        harmonyLaneId: primaryId,
      );
      notifier.setLaneAnchorLane(
        sectionId: section.id,
        laneId: secondStrumId,
        harmonyLaneId: thirdHarmonyId,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final selector = tester.widget<DropdownButton<String>>(
        find.byKey(Key('strumAnchor_${secondStrumId}_0')),
      );
      final options = selector.items!
          .map((item) => (value: item.value, label: (item.child as Text).data))
          .toList();
      expect(selector.value, thirdHarmonyId);
      expect(options.map((option) => option.value), [
        '',
        secondHarmonyId,
        thirdHarmonyId,
      ]);
      expect(options.map((option) => option.label), [
        'Unassigned',
        'Fretboard 2',
        'Fretboard 3',
      ]);
    },
  );

  testWidgets(
    'stale Add guitar strum action creates no pattern after source is occupied',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songwriterProvider.notifier);
      notifier.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final sourceId = section.lanes.single.id;
      notifier.setHarmonyLaneInstrument(
        sectionId: section.id,
        laneId: sourceId,
        instrument: HarmonyLaneInstrument.fretboard,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
      await tester.pumpAndSettle();
      final staleAction = find.byKey(
        const Key('addGuitarStrumLaneSheetAction'),
      );
      expect(staleAction, findsOneWidget);

      final existingStrumId = notifier.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      notifier.setLaneAnchorLane(
        sectionId: section.id,
        laneId: existingStrumId,
        harmonyLaneId: sourceId,
      );
      await tester.pump();
      await tester.tap(staleAction);
      await tester.pumpAndSettle();

      final updatedSection = container.read(songwriterProvider).sections.single;
      expect(
        updatedSection.lanes.where(
          (lane) => lane.kind == SongLaneKind.guitarStrum,
        ),
        hasLength(1),
      );
      expect(container.read(songwriterProvider).guitarStrumPatterns, isEmpty);
    },
  );

  testWidgets('compact melody tiles show the complete placement summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = notifier.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
      label: 'Melody',
    );
    final patternId = notifier.addMelodyPattern(
      name: 'Lead',
      lengthTicks: container.read(songwriterProvider).config.measureTicks * 2,
    );
    notifier.addMelodyBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 1,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final tile = find.byKey(Key('sheetMelodyTile_${patternId}_0_0'));
    final duration = find.text('Duration: 2 bars');
    final placement = find.text('Placement: bars 1–1 · clips after 1 bar');
    expect(tile, findsOneWidget);
    expect(duration, findsOneWidget);
    expect(placement, findsOneWidget);
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((lane) => lane.id == laneId)
        .blocks
        .single;
    expect(
      tester.getSize(find.byKey(Key('editMelodyBlock_${block.id}_0'))).width,
      greaterThanOrEqualTo(44),
    );
    for (final finder in [duration, placement]) {
      final summary = tester.widget<Text>(finder);
      expect(summary.maxLines, isNull);
      expect(summary.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
        isFalse,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('first edit expands a newly created melody block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.melody,
      label: 'Melody',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(Key('emptyMelodyBar_${laneId}_0_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('createWriterPattern')));
    await tester.pumpAndSettle();

    final editorContainer = tester
        .widgetList<UncontrolledProviderScope>(
          find.byType(UncontrolledProviderScope),
        )
        .last
        .container;
    final pianoRoll = editorContainer.read(pianoRollProvider.notifier);
    pianoRoll
      ..setTotalMeasures(2)
      ..addNote(72, 16, 4);
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveWriterMelodyPattern')));
    await tester.pumpAndSettle();

    final project = container.read(songwriterProvider);
    final lane = project.sections.single.lanes.singleWhere(
      (candidate) => candidate.id == laneId,
    );
    expect(project.melodyPatterns.single.lengthTicks, 20);
    expect((lane.blocks.single.startBar, lane.blocks.single.spanBars), (1, 2));
  });

  testWidgets('lyrics and mixer gestures each commit one history step', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = container
        .read(songwriterProvider)
        .sections
        .singleWhere((candidate) => candidate.id == section.id)
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .id;
    final beforeLyrics = notifier.undoCount;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final lyricEditor = find.byKey(Key('sectionLyrics_${section.id}_0'));
    await tester.ensureVisible(lyricEditor);
    await tester.tap(lyricEditor);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sectionLyricsField')),
      'A lyric line',
    );
    await tester.tap(find.byKey(const Key('sectionLyricsSave')));
    await tester.pumpAndSettle();
    expect(notifier.undoCount, beforeLyrics + 1);
    expect(notifier.undo(), isTrue);
    expect(container.read(songwriterProvider).sections.single.lyrics, isEmpty);

    final beforeDrag = notifier.undoCount;
    await tester.tap(find.byKey(Key('sectionMixer_${section.id}')));
    await tester.pumpAndSettle();
    final volumeSlider = find.byKey(Key('mixerVolume_$laneId'));
    await tester.drag(volumeSlider, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(notifier.undoCount, beforeDrag + 1);
    expect(notifier.undo(), isTrue);
    expect(
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == laneId)
          .volume,
      1.0,
    );
  });

  testWidgets('strum grid cycles a step down to up and retains its edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = notifier.addLane(
      sectionId: section.id,
      kind: SongLaneKind.guitarStrum,
      label: 'Guitar',
    );
    final patternId = notifier.addGuitarStrumPattern();
    notifier.addGuitarStrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: section.lengthBars,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('openStrumPattern'),
                  onPressed: () => showGuitarStrumPatternSheet(
                    context: context,
                    patternId: patternId,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openStrumPattern')));
    await tester.pumpAndSettle();

    Finder stepLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    expect(stepLabel('Step 1, down'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('guitarStrumStep_0'))),
      const Size(44, 44),
    );
    await tester.tap(find.byKey(const Key('guitarStrumStep_0')));
    await tester.pump();
    expect(
      container
          .read(songwriterProvider)
          .guitarStrumPatterns
          .single
          .events
          .first
          .direction,
      GuitarStrumDirection.up,
    );
    expect(stepLabel('Step 1, up'), findsOneWidget);

    tester.binding.focusManager.primaryFocus?.unfocus();
    bool firstStepFocused() => tester
        .widgetList<Semantics>(find.byType(Semantics))
        .any(
          (semantics) =>
              semantics.properties.label == 'Step 1, up' &&
              semantics.properties.focused == true,
        );
    for (var attempt = 0; attempt < 20 && !firstStepFocused(); attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(firstStepFocused(), isTrue);
    final focusedFace = tester.widget<Container>(
      find.byKey(const Key('guitarStrumStepFace_0')),
    );
    final focusedBorder = (focusedFace.decoration! as BoxDecoration).border!;
    expect(focusedBorder.top.width, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(stepLabel('Step 1, off'), findsOneWidget);

    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('guitarStrumStep_0'))),
      const Size(44, 44),
    );
  });
}
