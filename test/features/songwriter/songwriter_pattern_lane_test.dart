import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/features/songwriter/guitar_strum_pattern_sheet.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    expect(tester.getSize(tile).width, greaterThan(100));
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
