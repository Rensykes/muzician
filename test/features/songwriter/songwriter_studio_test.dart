import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_screen_v2.dart';
import 'package:muzician/features/songwriter/guitar_strum_pattern_sheet.dart';
import 'package:muzician/features/songwriter/songwriter_melody_pattern_editor.dart';
import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/guitar_sound.dart' show GuitarTone;
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/main.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StudioHost extends ConsumerWidget {
  const _StudioHost({required this.child, this.scale = 1});
  final Widget child;
  final double scale;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(settingsProvider.select((s) => s.themeVariant));
    return StudioThemeSource(
      variant: variant,
      child: MaterialApp(
        theme: StudioTheme.data(variant),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(1024, 768), 1.0),
    (const Size(320, 844), 1.5),
  ]) {
    testWidgets(
      'Fretboard Harmony sound updates shared tone at $size x$scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final saves = container.read(saveSystemProvider.notifier);
        final projectId = saves.createProject(
          'Guitar sketch',
          const ProjectConfig(
            defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
          ),
        )!;
        saves.selectProject(projectId);
        final writer = container.read(songwriterProvider.notifier);
        writer.addSection(label: 'Verse', lengthBars: 4);
        final section = container.read(songwriterProvider).sections.single;
        final laneId = section.lanes.first.id;
        writer.addHarmonyChord(
          sectionId: section.id,
          laneId: laneId,
          block: makeHarmonyBlock(
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'C',
            chordRootPc: 0,
            chordQuality: '',
            chordNotes: const ['C', 'E', 'G'],
          ),
        );
        final before = container.read(songwriterProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _StudioHost(
              scale: scale,
              child: const SongwriterScreenSheet(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Populated Writer layout',
        );
        final sound = find.byKey(Key('harmonyGuitarSound_$laneId'));
        await tester.ensureVisible(sound);
        expect(tester.getSize(sound).height, greaterThanOrEqualTo(44));
        expect(find.text('Sound: Clean'), findsOneWidget);
        await tester.tap(sound);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Sound menu layout');
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<GuitarTone>, 'Distorted'),
        );
        await tester.pumpAndSettle();
        expect(
          container.read(settingsProvider).guitarTone,
          GuitarTone.distorted,
        );
        expect(find.text('Sound: Distorted'), findsOneWidget);
        expect(container.read(songwriterProvider), same(before));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Studio mixed Harmony rows align while empty rows stay compact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saves = container.read(saveSystemProvider.notifier);
    final projectId = saves.createProject('Mixed row', const ProjectConfig())!;
    saves.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 8);
    final section = container.read(songwriterProvider).sections.single;
    final laneId = section.lanes.first.id;
    writer.addHarmonyChord(
      sectionId: section.id,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordRootPc: 0,
        chordQuality: '',
        chordNotes: const ['C', 'E', 'G'],
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _StudioHost(child: SongwriterScreenSheet()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final filled = find.byKey(Key('writerHarmonyCell_${laneId}_0_0'));
    for (var bar = 0; bar < 8; bar++) {
      final cell = find.byKey(Key('writerHarmonyCell_${laneId}_0_$bar'));
      expect(tester.getSize(cell).height, bar < 4 ? 64 : 44);
      if (bar < 4) {
        expect(tester.getTopLeft(cell).dy, tester.getTopLeft(filled).dy);
        expect(
          tester.getBottomRight(cell).dy,
          tester.getBottomRight(filled).dy,
        );
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('Studio Writer shows eight bars, strum and lyrics at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'Redesign study',
        const ProjectConfig(keyRootPc: 0, keyScaleName: 'major'),
      )!;
      saves.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse 1', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.single;
      final laneId = section.lanes.first.id;
      for (var bar = 0; bar < 4; bar++) {
        writer.addHarmonyChord(
          sectionId: section.id,
          laneId: laneId,
          block: makeHarmonyBlock(
            startBar: bar,
            spanBars: 1,
            chordSymbol: 'C',
            chordRootPc: 0,
            chordQuality: '',
            chordNotes: const ['C', 'E', 'G'],
          ),
        );
      }
      final strumLane = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
        label: 'Guitar Strum',
      );
      final patternId = writer.addGuitarStrumPattern(
        name: 'Strum',
        lengthTicks: 16,
      );
      writer.addGuitarStrumBlock(
        sectionId: section.id,
        laneId: strumLane,
        patternId: patternId,
        startBar: 0,
        spanBars: 8,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _StudioHost(
            child: Padding(
              padding: EdgeInsets.only(top: 44, bottom: 80),
              child: SongwriterScreenSheet(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      for (var bar = 0; bar < 8; bar++) {
        final cell = find.byKey(Key('writerHarmonyCell_${laneId}_0_$bar'));
        expect(cell, findsOneWidget);
        expect(tester.getSize(cell).height, bar < 4 ? 64 : 44);
        expect(tester.getBottomRight(cell).dy, lessThan(size.height - 80));
      }
      final source = find.byKey(Key('strumAnchor_${strumLane}_0'));
      final lyrics = find.byKey(Key('sectionLyrics_${section.id}_0'));
      expect(tester.getBottomRight(source).dy, lessThan(size.height - 80));
      expect(
        (tester.getCenter(source).dy -
                tester.getCenter(find.text('Guitar Strum')).dy)
            .abs(),
        lessThan(2),
      );
      expect(tester.getBottomRight(lyrics).dy, lessThan(size.height - 80));
      expect(tester.getSize(lyrics).height, greaterThanOrEqualTo(44));
      for (final control in [('barsPill', 'Bars'), ('repeatPill', 'Verses')]) {
        final disclosure = find.byKey(Key('${control.$1}_${section.id}'));
        expect(tester.getSize(disclosure).height, greaterThanOrEqualTo(44));
        expect(
          find.descendant(
            of: disclosure,
            matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
          ),
          findsOneWidget,
        );
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        expect(find.text(control.$2), findsOneWidget);
        expect(find.byKey(const Key('stepperPlus')), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
      expect(
        find.descendant(
          of: find.byKey(Key('sectionMixer_${section.id}')),
          matching: find.text('Mixer'),
        ),
        size.width >= 700 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('removeSection_${section.id}')));
      await tester.pumpAndSettle();
      expect(container.read(songwriterProvider).sections, isEmpty);
      await tester.tap(find.byKey(const Key('writerUndoButton')));
      await tester.pumpAndSettle();
      expect(container.read(songwriterProvider).sections.single.id, section.id);
      expect(
        container.read(songwriterProvider).sections.single.lanes.first.blocks,
        hasLength(4),
      );
      expect(tester.takeException(), isNull);
      final strumBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((lane) => lane.id == strumLane)
          .blocks
          .single;
      writer.setBlockPlacement(
        sectionId: section.id,
        laneId: strumLane,
        blockId: strumBlock.id,
        startBar: 0,
        spanBars: 1,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(Key('sheetGuitarStrumTile_${patternId}_0_0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
    const Size(320, 844),
  ]) {
    testWidgets('Studio Writer fits $size with long names and both palettes', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'A long project name for a song we are writing',
        const ProjectConfig(),
      )!;
      saves.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(
        label: 'Verse with a long descriptive section name',
        lengthBars: 4,
      );
      final section = container.read(songwriterProvider).sections.single;
      writer.addHarmonyBlock(
        sectionId: section.id,
        laneId: section.lanes.first.id,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'Cmaj7',
          chordQuality: 'maj7',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G', 'B'],
        ).copyWith(lyrics: ['Under the moon']),
      );
      for (final kind in [
        SongLaneKind.drum,
        SongLaneKind.melody,
        SongLaneKind.guitarStrum,
        SongLaneKind.audio,
      ]) {
        final laneId = writer.addLane(
          sectionId: section.id,
          kind: kind,
          label: '${kind.name} performance',
        );
        if (kind == SongLaneKind.melody) {
          final patternId = writer.addMelodyPattern(
            name: 'Melody idea',
            lengthTicks: 16,
          );
          writer.addMelodyBlock(
            sectionId: section.id,
            laneId: laneId,
            patternId: patternId,
            startBar: 0,
            spanBars: 4,
          );
        } else if (kind == SongLaneKind.guitarStrum && laneId.isNotEmpty) {
          final patternId = writer.addGuitarStrumPattern(
            name: 'Strum idea',
            lengthTicks: 16,
          );
          writer.addGuitarStrumBlock(
            sectionId: section.id,
            laneId: laneId,
            patternId: patternId,
            startBar: 0,
            spanBars: 4,
          );
        } else if (kind == SongLaneKind.drum) {
          final patternId = writer.addDrumPattern(name: 'Beat idea');
          writer.addDrumBlock(
            sectionId: section.id,
            laneId: laneId,
            patternId: patternId,
            startBar: 0,
            spanBars: 4,
          );
        }
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _StudioHost(
            scale: size.width == 320 ? 1.5 : 1,
            child: const SongwriterScreenSheet(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Writer'), findsOneWidget);
      expect(find.text('Save version'), findsOneWidget);
      expect(find.byKey(const Key('songwriterPlay')), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (size.width == 1024) {
        expect(
          tester
              .getSize(find.byKey(Key('sectionInstance_${section.id}_0')))
              .width,
          greaterThan(900),
        );
      }
      final before = container.read(songwriterProvider);
      final history = writer.historyRevision;
      container
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studioMuzician);
      await tester.pumpAndSettle();
      expect(container.read(songwriterProvider), same(before));
      expect(writer.historyRevision, history);
      expect(
        StudioPalette.of(tester.element(find.byType(SongwriterScreenSheet))),
        StudioPalette.studioMuzician,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final size in [const Size(320, 844), const Size(1024, 768)]) {
    testWidgets('actual app root Writer fits $size at 1.5 text scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MuzicianApp(),
        ),
      );
      for (
        var attempt = 0;
        attempt < 30 && find.byType(IndexedStack).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(IndexedStack), findsOneWidget);
      expect(find.byKey(const Key('writerSaveButton')), findsOneWidget);
      expect(tester.takeException(), isNull);
      container
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studioMuzician);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'Studio block sheet keeps common and advanced actions and changes live',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'Chord actions',
        const ProjectConfig(),
      )!;
      saves.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      writer.addHarmonyChord(
        sectionId: section.id,
        laneId: section.lanes.first.id,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G'],
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _StudioHost(child: SongwriterScreenSheet()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barActionChangeChord')), findsOneWidget);
      expect(find.byKey(const Key('barActionPlayFromHere')), findsOneWidget);
      expect(find.byKey(const Key('barActionLyrics')), findsOneWidget);
      for (final key in [
        'barActionVoicings',
        'barActionReplaceChord',
        'barActionRenameBlock',
        'barActionCreateStandaloneSave',
        'barActionRemove',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      final before = container.read(songwriterProvider);
      container
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studioMuzician);
      await tester.pumpAndSettle();
      final action = find.byKey(const Key('barActionChangeChord'));
      expect(
        StudioPalette.of(tester.element(action)),
        StudioPalette.studioMuzician,
      );
      expect(container.read(songwriterProvider), same(before));
      await tester.tap(find.byKey(const Key('barActionLyrics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('verseLyricField')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'open isolated Writer melody retains edits and tool across theme switch',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final writer = container.read(songwriterProvider.notifier);
      final patternId = writer.addMelodyPattern(
        name: 'Isolated melody',
        lengthTicks: 16,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _StudioHost(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSongwriterMelodyPatternEditor(
                  context: context,
                  patternId: patternId,
                ),
                child: const Text('Open melody'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Open melody'));
      await tester.pumpAndSettle();
      final roll = find.byType(PianoRollScreenV2);
      final element = tester.element(roll);
      final editor = ProviderScope.containerOf(element);
      expect(editor, isNot(same(container)));
      final local = editor.read(pianoRollProvider.notifier);
      local.addNote(64, 0, 4);
      local.setActiveTool(PianoRollTool.select);
      local.setSnapTicks(2);
      await tester.pumpAndSettle();
      final edited = editor.read(pianoRollProvider);
      final parentPattern = container
          .read(songwriterProvider)
          .melodyPatterns
          .single;
      expect(parentPattern.notes, isEmpty);
      final screen = tester.widget<PianoRollScreenV2>(roll);
      expect(screen.showScale, isFalse);
      expect(screen.showSavePanels, isFalse);
      container
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studioMuzician);
      await tester.pumpAndSettle();
      expect(tester.element(roll), same(element));
      expect(ProviderScope.containerOf(tester.element(roll)), same(editor));
      expect(editor.read(pianoRollProvider), same(edited));
      expect(
        StudioPalette.of(tester.element(roll)),
        StudioPalette.studioMuzician,
      );
      expect(
        container.read(songwriterProvider).melodyPatterns.single,
        same(parentPattern),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('saveWriterMelodyPattern')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(songwriterProvider)
            .melodyPatterns
            .single
            .notes
            .single
            .midiNote,
        64,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('strum editor wraps complete four-step beat groups at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final patternId = container
          .read(songwriterProvider.notifier)
          .addGuitarStrumPattern(lengthTicks: 16);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _StudioHost(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGuitarStrumPatternSheet(
                  context: context,
                  patternId: patternId,
                ),
                child: const Text('Open strum'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Open strum'));
      await tester.pumpAndSettle();
      for (var beat = 0; beat < 4; beat++) {
        final group = find.byKey(Key('guitarStrumBeat_$beat'));
        expect(group, findsOneWidget);
        for (var step = beat * 4; step < beat * 4 + 4; step++) {
          final face = find.byKey(Key('guitarStrumStepFace_$step'));
          expect(tester.getSize(face), const Size(44, 44));
          expect(find.descendant(of: group, matching: face), findsOneWidget);
          expect(
            tester.getTopLeft(face).dy,
            tester
                .getTopLeft(find.byKey(Key('guitarStrumStepFace_${beat * 4}')))
                .dy,
          );
        }
      }
      final step = find.byKey(const Key('guitarStrumStepFace_0'));
      await tester.ensureVisible(step);
      for (final expected in [
        GuitarStrumDirection.up,
        null,
        GuitarStrumDirection.down,
      ]) {
        await tester.tap(step);
        await tester.pumpAndSettle();
        expect(
          container
              .read(songwriterProvider)
              .guitarStrumPatterns
              .single
              .events
              .where((event) => event.tick == 0)
              .firstOrNull
              ?.direction,
          expected,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
