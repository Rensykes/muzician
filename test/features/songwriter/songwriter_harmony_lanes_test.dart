import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSheet(
    WidgetTester tester, {
    required void Function(SongwriterNotifier n) seed,
    ValueChanged<SaveEntry>? onEditInstrumentSave,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seed(container.read(songwriterProvider.notifier));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterScreenSheet(
              onEditInstrumentSave: onEditInstrumentSave,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return container;
  }

  testWidgets('two harmony lanes render two bar rows with labels', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );

    // 4 empty bar placeholders per harmony lane.
    expect(find.text('·'), findsNWidgets(8));
    // Lane labels shown when the section has more than one harmony lane.
    expect(find.text('Harmony'), findsWidgets);
    expect(find.text('Harmony 2'), findsOneWidget);
    expect(
      container.read(songwriterProvider).sections.single.lanes,
      hasLength(2),
    );
  });

  testWidgets('stale explicit Save anchor stays visible and can be repaired', (
    tester,
  ) async {
    final container = await pumpSheet(tester, seed: (_) {});
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Project',
      const ProjectConfig(
        defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
      ),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final pianoLaneId = writer.addHarmonyLane(
      sectionId: section.id,
      harmonyInstrument: HarmonyLaneInstrument.piano,
      label: 'Piano',
    )!;
    final saveLaneId = writer.addLane(
      sectionId: section.id,
      kind: SongLaneKind.save,
      label: 'Piano Voicings',
    );
    writer.setLaneAnchorLane(
      sectionId: section.id,
      laneId: saveLaneId,
      harmonyLaneId: pianoLaneId,
    );
    final pianoSaveId = saveSystem.saveSnapshot(
      'Piano voicing',
      projectId,
      PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const ['C4', 'E4', 'G4'],
        viewMode: PianoViewMode.exact,
      ),
    )!;
    writer.addSaveBlock(
      sectionId: section.id,
      laneId: saveLaneId,
      saveId: pianoSaveId,
      startBar: 0,
      spanBars: 1,
    );
    await writer.reconcileCurrentProject();
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.id == saveLaneId)
        .blocks
        .single;
    final currentSection = container.read(songwriterProvider).sections.single;
    writer.state = writer.state.copyWith(
      sections: [
        currentSection.copyWith(
          lanes: [
            for (final lane in currentSection.lanes)
              if (lane.id == saveLaneId)
                lane.copyWith(anchorLaneId: 'deleted-harmony-lane')
              else
                lane,
          ],
        ),
      ],
    );

    for (final size in [const Size(390, 844), const Size(1180, 820)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }
    expect(
      find.byKey(Key('unresolvedSaveLane_${saveLaneId}_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('unresolvedSaveBlock_${block.id}_0')),
      findsOneWidget,
    );
    expect(find.byKey(Key('saveCell_${block.id}_0')), findsNothing);

    await tester.tap(find.byKey(Key('repairSaveAnchor_${saveLaneId}_0')));
    await tester.pumpAndSettle();
    final pianoHarmonyLane = currentSection.lanes.firstWhere(
      (lane) =>
          lane.kind == SongLaneKind.harmony &&
          lane.harmonyInstrument == HarmonyLaneInstrument.piano,
    );
    await tester.tap(find.text('Piano').last);
    await tester.pumpAndSettle();

    expect(
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == saveLaneId)
          .anchorLaneId,
      pianoHarmonyLane.id,
    );
    expect(find.byKey(Key('unresolvedSaveLane_${saveLaneId}_0')), findsNothing);
    expect(find.byKey(Key('saveCell_${block.id}_0')), findsOneWidget);
  });

  testWidgets(
    'unresolved Save blocks open native editor and can be removed with their lane',
    (tester) async {
      SaveEntry? editedEntry;
      final container = await pumpSheet(
        tester,
        seed: (_) {},
        onEditInstrumentSave: (entry) => editedEntry = entry,
      );
      final saveSystem = container.read(saveSystemProvider.notifier);
      final projectId = saveSystem.createProject(
        'Project',
        const ProjectConfig(
          defaultHarmonyInstrument: HarmonyLaneInstrument.fretboard,
        ),
      )!;
      saveSystem.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final pianoLaneId = writer.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.piano,
        label: 'Piano',
      )!;
      final saveLaneId = writer.addLane(
        sectionId: section.id,
        kind: SongLaneKind.save,
        label: 'Piano Voicings',
      );
      writer.setLaneAnchorLane(
        sectionId: section.id,
        laneId: saveLaneId,
        harmonyLaneId: pianoLaneId,
      );
      final pianoSaveId = saveSystem.saveSnapshot(
        'Piano voicing',
        projectId,
        PianoSnapshot(
          currentRange: PianoRangeName.key61,
          selectedKeys: const [],
          selectedNotes: const ['C4', 'E4', 'G4'],
          viewMode: PianoViewMode.exact,
        ),
      )!;
      for (var bar = 0; bar < 2; bar++) {
        writer.addSaveBlock(
          sectionId: section.id,
          laneId: saveLaneId,
          saveId: pianoSaveId,
          startBar: bar,
          spanBars: 1,
        );
      }
      await writer.reconcileCurrentProject();

      final currentSection = container.read(songwriterProvider).sections.single;
      final saveBlocks = currentSection.lanes
          .singleWhere((lane) => lane.id == saveLaneId)
          .blocks;
      final primaryHarmonyLane = currentSection.lanes.firstWhere(
        (lane) => lane.kind == SongLaneKind.harmony,
      );
      writer.state = writer.state.copyWith(
        sections: [
          currentSection.copyWith(
            lanes: [
              for (final lane in currentSection.lanes)
                if (lane.id != pianoLaneId)
                  if (lane.id == saveLaneId)
                    lane.copyWith(anchorLaneId: 'deleted-harmony-lane')
                  else
                    lane,
            ],
          ),
        ],
      );

      for (final size in [const Size(390, 844), const Size(1180, 820)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }
      expect(primaryHarmonyLane.kind, SongLaneKind.harmony);
      expect(
        find.byKey(Key('unresolvedSaveLane_${saveLaneId}_0')),
        findsOneWidget,
      );
      expect(find.text('No compatible Harmony lane'), findsOneWidget);
      expect(
        find.byKey(Key('saveCell_${saveBlocks.first.id}_0')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(Key('unresolvedSaveBlock_${saveBlocks.first.id}_0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('unresolvedSaveEdit_${saveBlocks.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(editedEntry?.id, pianoSaveId);

      await tester.tap(
        find.byKey(Key('unresolvedSaveBlock_${saveBlocks.first.id}_0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('unresolvedSaveRemove_${saveBlocks.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .singleWhere((lane) => lane.id == saveLaneId)
            .blocks,
        hasLength(1),
      );
      expect(find.text('No compatible Harmony lane'), findsOneWidget);

      await tester.tap(
        find.byKey(Key('removeUnresolvedSaveLane_${saveLaneId}_0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('confirmRemoveUnresolvedSaveLane_$saveLaneId')),
      );
      await tester.pumpAndSettle();
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .any((lane) => lane.id == saveLaneId),
        isFalse,
      );
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .any((lane) => lane.id == primaryHarmonyLane.id),
        isTrue,
      );
    },
  );

  testWidgets('section menu adds a numbered harmony lane', (tester) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
      },
    );
    final sectionId = container.read(songwriterProvider).sections.single.id;

    await tester.tap(find.byKey(Key('sheetSectionMenu_$sectionId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addHarmonyLaneSheetAction')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a Harmony instrument'), findsOneWidget);
    await tester.tap(find.byKey(const Key('harmonyInstrumentOption_piano')));
    await tester.pumpAndSettle();

    final lanes = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .where((l) => l.kind == SongLaneKind.harmony)
        .toList();
    expect(lanes, hasLength(2));
    expect(lanes.last.label, 'Harmony 2');
    expect(lanes.last.harmonyInstrument, HarmonyLaneInstrument.piano);
    expect(find.text('Piano'), findsOneWidget);
  });

  testWidgets(
    'canceling secondary lane instrument selection is mutation-free',
    (tester) async {
      final container = await pumpSheet(
        tester,
        seed: (n) => n.addSection(label: 'Verse', lengthBars: 4),
      );
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final initialLanes = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes;

      await tester.tap(find.byKey(Key('sheetSectionMenu_$sectionId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addHarmonyLaneSheetAction')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('harmonyInstrumentCancel')));
      await tester.pumpAndSettle();

      expect(
        container.read(songwriterProvider).sections.single.lanes,
        same(initialLanes),
      );
      expect(find.text('Choose a Harmony instrument'), findsNothing);
    },
  );

  testWidgets('Harmony lane header exposes its project-default instrument', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final projectId = container
        .read(saveSystemProvider.notifier)
        .createProject(
          'Piano project',
          const ProjectConfig(
            defaultHarmonyInstrument: HarmonyLaneInstrument.piano,
          ),
        )!;
    container.read(saveSystemProvider.notifier).selectProject(projectId);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'Verse', lengthBars: 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final lane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single;
    expect(lane.harmonyInstrument, HarmonyLaneInstrument.piano);
    expect(find.text('Piano'), findsOneWidget);
    expect(find.byKey(Key('harmonyLaneInstrument_${lane.id}')), findsOneWidget);
  });

  testWidgets('empty Harmony lane can change instrument without changing ID', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) => n.addSection(label: 'Verse', lengthBars: 2),
    );
    final section = container.read(songwriterProvider).sections.single;
    final lane = section.lanes.single;
    expect(
      find.byKey(Key('changeHarmonyLaneInstrument_${lane.id}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('changeHarmonyLaneInstrument_${lane.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyInstrumentOption_piano')));
    await tester.pumpAndSettle();

    final changedLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single;
    expect(changedLane.id, lane.id);
    expect(changedLane.harmonyInstrument, HarmonyLaneInstrument.piano);
  });

  testWidgets('stale guitar strum anchor shows unresolved instead of primary', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final sectionId = n.state.sections.single.id;
        final strumId = n.addLane(
          sectionId: sectionId,
          kind: SongLaneKind.guitarStrum,
        );
        final section = n.state.sections.single;
        // A normal lane deletion clears its anchor. Seed the dangling ID
        // directly to model a stale reference loaded from persisted data.
        n.state = n.state.copyWith(
          sections: [
            section.copyWith(
              lanes: [
                for (final lane in section.lanes)
                  if (lane.id == strumId)
                    lane.copyWith(anchorLaneId: 'deleted-harmony')
                  else
                    lane,
              ],
            ),
          ],
        );
      },
    );

    final strumLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.guitarStrum);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(Key('strumAnchor_${strumLane.id}_0')),
    );
    expect(dropdown.value, isNull);
    expect((dropdown.hint as Text).data, 'Unresolved');
    expect(find.text('Unresolved'), findsOneWidget);
    expect(find.text('Unassigned'), findsNothing);
    expect(dropdown.items!.map((item) => item.value), contains(''));
    expect(strumLane.anchorLaneId, 'deleted-harmony');
    expect(
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == strumLane.id)
          .anchorLaneId,
      strumLane.anchorLaneId,
    );
  });

  testWidgets(
    'duplicate Harmony action copies placements with shared Save IDs',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final projectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Writer project', const ProjectConfig())!;
      container.read(saveSystemProvider.notifier).selectProject(projectId);
      final notifier = container.read(songwriterProvider.notifier);
      notifier.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final sourceLane = section.lanes.single;
      final result = notifier.addHarmonyChord(
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
      );
      expect(result.success, isTrue, reason: result.errorMessage);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(
        find.byKey(Key('duplicateHarmonyLane_${sourceLane.id}')),
      );
      await tester.pumpAndSettle();

      final lanes = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .where((lane) => lane.kind == SongLaneKind.harmony)
          .toList();
      expect(lanes, hasLength(2));
      expect(lanes.last.harmonyInstrument, sourceLane.harmonyInstrument);
      expect(lanes.last.blocks, hasLength(1));
      expect(lanes.last.blocks.single.id, isNot(lanes.first.blocks.single.id));
      expect(lanes.last.blocks.single.saveId, lanes.first.blocks.single.saveId);
    },
  );

  testWidgets(
    'Replace chord picker filters by lane instrument and cancel keeps placement',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final projectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Writer project', const ProjectConfig())!;
      container.read(saveSystemProvider.notifier).selectProject(projectId);
      final notifier = container.read(songwriterProvider.notifier);
      notifier.addSection(label: 'Verse', lengthBars: 4);
      final section = container.read(songwriterProvider).sections.single;
      final primaryLane = section.lanes.single;
      final target = notifier.addHarmonyChord(
        sectionId: section.id,
        laneId: primaryLane.id,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 2,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G'],
        ).copyWith(lyrics: const ['Keep this lyric']),
      );
      final replacement = notifier.addHarmonyChord(
        sectionId: section.id,
        laneId: primaryLane.id,
        block: makeHarmonyBlock(
          startBar: 2,
          spanBars: 1,
          chordSymbol: 'G',
          chordQuality: '',
          chordRootPc: 7,
          chordNotes: const ['G', 'B', 'D'],
        ),
      );
      final pianoLaneId = notifier.addHarmonyLane(
        sectionId: section.id,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      final incompatible = notifier.addHarmonyChord(
        sectionId: section.id,
        laneId: pianoLaneId,
        block: makeHarmonyBlock(
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'Dm',
          chordQuality: 'm',
          chordRootPc: 2,
          chordNotes: const ['D', 'F', 'A'],
        ),
      );
      expect(target.success, isTrue, reason: target.errorMessage);
      expect(replacement.success, isTrue, reason: replacement.errorMessage);
      expect(incompatible.success, isTrue, reason: incompatible.errorMessage);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barActionReplaceChord')), findsOneWidget);
      await tester.tap(find.byKey(const Key('barActionReplaceChord')));
      await tester.pumpAndSettle();

      final saves = container.read(saveSystemProvider).saves;
      final replacementId = saves.singleWhere((save) => save.name == 'G').id;
      final incompatibleId = saves.singleWhere((save) => save.name == 'Dm').id;
      expect(
        find.byKey(Key('harmonyLibrarySave_$replacementId')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('harmonyLibrarySave_$incompatibleId')),
        findsNothing,
      );

      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      final currentTarget = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == primaryLane.id)
          .blocks
          .singleWhere((block) => block.id == target.blockId);
      expect(currentTarget.saveId, isNot(replacementId));
      expect(currentTarget.startBar, 0);
      expect(currentTarget.spanBars, 2);
      expect(currentTarget.lyrics, ['Keep this lyric']);

      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barActionReplaceChord')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('harmonyLibrarySave_$replacementId')));
      await tester.pumpAndSettle();

      final replacedTarget = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == primaryLane.id)
          .blocks
          .singleWhere((block) => block.id == target.blockId);
      expect(replacedTarget.saveId, replacementId);
      expect(replacedTarget.chordSymbol, 'G');
      expect(replacedTarget.startBar, 0);
      expect(replacedTarget.spanBars, 2);
      expect(replacedTarget.lyrics, ['Keep this lyric']);

      await tester.tap(find.text('·').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barActionAddLibrary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('harmonyLibrarySave_$replacementId')));
      await tester.pumpAndSettle();

      final inserted = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == primaryLane.id)
          .blocks
          .singleWhere((block) => block.startBar == 3);
      expect(inserted.saveId, replacementId);
      expect(inserted.chordSymbol, 'G');
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .where((lane) => lane.kind == SongLaneKind.save),
        isEmpty,
      );
    },
  );

  testWidgets('secondary lane header deletes the lane after confirm', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        final saveLane = n.addLane(sectionId: s, kind: SongLaneKind.save);
        n.setLaneAnchorLane(
          sectionId: s,
          laneId: saveLane,
          harmonyLaneId: secondary,
        );
      },
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere(
          (lane) =>
              lane.kind == SongLaneKind.harmony && lane.label == 'Harmony 2',
        )
        .id;

    await tester.tap(find.byKey(Key('deleteHarmonyLane_$laneId')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The chords in this lane and any Save / Voicing lanes anchored to it are removed.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirmDeleteHarmonyLane')));
    await tester.pumpAndSettle();

    expect(
      container.read(songwriterProvider).sections.single.lanes,
      hasLength(1),
    );
    expect(
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .where((lane) => lane.kind == SongLaneKind.save),
      isEmpty,
    );
  });

  testWidgets('primary harmony lane header has no delete action', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );
    final lanes = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .where((l) => l.kind == SongLaneKind.harmony)
        .toList();

    expect(
      find.byKey(Key('deleteHarmonyLane_${lanes.first.id}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('deleteHarmonyLane_${lanes.last.id}')),
      findsOneWidget,
    );
  });

  testWidgets('harmony lane header label renames the lane', (tester) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .last
        .id;

    await tester.tap(find.byKey(Key('renameHarmonyLane_$laneId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('laneRenameField')), 'Double');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      container.read(songwriterProvider).sections.single.lanes.last.label,
      'Double',
    );
    expect(find.text('Double'), findsOneWidget);
  });

  testWidgets('lyric bar action only offered on the primary harmony lane', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        final l1 = n.state.sections.single.lanes
            .firstWhere((lane) => lane.kind == SongLaneKind.harmony)
            .id;
        final l2 = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        for (final l in [l1, l2]) {
          n.addHarmonyBlock(
            sectionId: s,
            laneId: l,
            block: makeHarmonyBlock(
              startBar: 0,
              spanBars: 1,
              chordSymbol: 'C',
              chordQuality: '',
              chordRootPc: 0,
              chordNotes: const ['C', 'E', 'G'],
            ),
          );
        }
      },
    );

    // Both lanes show the chord cell.
    expect(find.text('C'), findsNWidgets(2));

    // Primary lane's chord: action sheet offers the lyric action.
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barActionLyrics')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss
    await tester.pumpAndSettle();

    // Secondary lane's chord: no lyric action.
    await tester.tap(find.text('C').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    expect(find.byKey(const Key('barActionLyrics')), findsNothing);
  });

  testWidgets('secondary empty bar offers library saves too', (tester) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );

    await tester.tap(find.text('·').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionAddChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionAddLibrary')), findsOneWidget);
  });

  testWidgets('secondary add-chord sheet offers library saves too', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );

    await tester.tap(find.text('·').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('barActionAddChord')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fromLibraryButton')), findsOneWidget);
  });

  testWidgets('secondary chord action does not expose primary save removal', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        final primary = n.state.sections.single.lanes
            .firstWhere((lane) => lane.kind == SongLaneKind.harmony)
            .id;
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        final saveLane = n.addLane(
          sectionId: s,
          kind: SongLaneKind.save,
          label: 'Save',
        );
        n.addHarmonyBlock(
          sectionId: s,
          laneId: primary,
          block: const SongBlock(
            id: 'primary-c',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'C',
            chordQuality: '',
            chordRootPc: 0,
            chordNotes: ['C', 'E', 'G'],
          ),
        );
        n.addHarmonyBlock(
          sectionId: s,
          laneId: secondary,
          block: const SongBlock(
            id: 'secondary-g',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'G',
            chordQuality: '',
            chordRootPc: 7,
            chordNotes: ['G', 'B', 'D'],
          ),
        );
        n.addSaveBlock(
          sectionId: s,
          laneId: saveLane,
          saveId: 'save-xyz',
          startBar: 0,
          spanBars: 1,
        );
      },
    );

    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    expect(find.byKey(const Key('barActionRemoveSave')), findsNothing);
  });

  testWidgets('secondary chord tools expose the library too', (tester) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        n.addHarmonyBlock(
          sectionId: s,
          laneId: secondary,
          block: const SongBlock(
            id: 'secondary-g',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'G',
            chordQuality: '',
            chordRootPc: 7,
            chordNotes: ['G', 'B', 'D'],
          ),
        );
      },
    );

    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();

    expect(find.text('Voicings & library'), findsOneWidget);

    await tester.tap(find.byKey(const Key('barActionVoicings')));
    await tester.pumpAndSettle();

    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsWidgets);
    expect(find.text('Library'), findsOneWidget);
    // Lyrics stay primary-only, so the edit label omits them here.
    expect(find.text('Edit chord'), findsOneWidget);
    expect(find.text('Edit chord & lyrics'), findsNothing);
  });

  testWidgets('anchored save renders on its harmony lane row only', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        n.addLibraryBlockAt(
          sectionId: s,
          saveId: 'save-xyz',
          startBar: 1,
          anchorLaneId: secondary,
        );
      },
    );

    final saveLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((l) => l.kind == SongLaneKind.save);
    expect(
      saveLane.anchorLaneId,
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.label == 'Harmony 2')
          .id,
    );
    final blockId = saveLane.blocks.single.id;
    // Exactly one standalone save cell across both harmony rows.
    expect(find.byKey(Key('saveCell_${blockId}_0')), findsOneWidget);
  });
}
