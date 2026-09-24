import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/features/songwriter/guitar_strum_pattern_sheet.dart';
import 'package:muzician/models/songwriter.dart';
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
            widget.properties.label == 'Edit melody pattern Melody',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(Key('sheetMelodyTile_${lane.blocks.single.patternId}_0')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saveWriterMelodyPattern')), findsOneWidget);
  });

  testWidgets('lyrics and mixer gestures each commit one history step', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = notifier.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
    );
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
      container.read(songwriterProvider).sections.single.lanes.single.volume,
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
