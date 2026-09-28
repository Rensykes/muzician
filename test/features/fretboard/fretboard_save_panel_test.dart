import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard_save_panel.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(ProviderContainer container, {String? linkedEditSaveId}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: FretboardSavePanel(linkedEditSaveId: linkedEditSaveId),
      ),
    ),
  );
}

Future<void> _loadSave(
  WidgetTester tester, {
  required String folderName,
  required String saveName,
}) async {
  await tester.tap(find.text(folderName));
  await tester.pumpAndSettle();
  await tester.tap(find.text(saveName));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loading a snapshot without a scale clears stale activeScale', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeScaleProvider.notifier).state = (
      root: 'C',
      scaleName: 'major',
    );

    final saveSystem = container.read(saveSystemProvider.notifier);
    final dumpId = saveSystem.ensureDumpFolder();
    saveSystem.selectProject(dumpId);
    final folderId = container
        .read(saveSystemProvider.notifier)
        .createSaveFolder('Fretboard Saves', dumpId);
    expect(folderId, isNotNull);

    final saveId = container
        .read(saveSystemProvider.notifier)
        .saveSnapshot(
          'No Scale',
          folderId!,
          FretboardSnapshot(
            tuning: TuningName.standard,
            numFrets: 12,
            capo: 0,
            selectedCells: const [],
            selectedNotes: const [],
            viewMode: FretboardViewMode.exact,
          ),
        );
    expect(saveId, isNotNull);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _loadSave(
      tester,
      folderName: 'Fretboard Saves',
      saveName: 'No Scale',
    );

    expect(container.read(activeScaleProvider), isNull);
    expect(container.read(pendingScaleProvider), isNull);
  });

  testWidgets('Dump root ideas do not offer Use in Writer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final dumpId = saveSystem.ensureDumpFolder();
    saveSystem.selectProject(dumpId);
    saveSystem.saveSnapshot(
      'Dump shape',
      dumpId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      ),
    );

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dump shape'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('useWriterSaveButton')), findsNothing);
    expect(find.byKey(const Key('useWriterSaveAction')), findsNothing);
    tester.view.physicalSize = const Size(1180, 820);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveBrowserGridToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('useWriterSaveButton')), findsNothing);
    expect(find.byKey(const Key('useWriterSaveAction')), findsNothing);
  });

  testWidgets('removing the final Writer link clears the edit target', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    await saveSystem.hydrate();
    final projectId = saveSystem.createProject(
      'Fretboard project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [],
      selectedNotes: const [],
      viewMode: FretboardViewMode.exact,
    );
    final saveId = saveSystem.saveSnapshot(
      'Linked shape',
      projectId,
      snapshot,
    )!;
    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: section.id,
        startBar: 0,
        snapshot: snapshot,
        saveName: 'Linked shape',
        reuseSaveId: saveId,
      ),
      isTrue,
    );
    final lane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single;
    final block = lane.blocks.single;

    await tester.pumpWidget(_wrap(container, linkedEditSaveId: saveId));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updateLinkedSaveButton')), findsOneWidget);

    writer.removeBlock(
      sectionId: section.id,
      laneId: lane.id,
      blockId: block.id,
    );
    await tester.pumpAndSettle();

    expect(container.read(saveSystemProvider).writerLinks, isEmpty);
    expect(find.byKey(const Key('updateLinkedSaveButton')), findsNothing);
  });

  testWidgets(
    'Use in Writer reuses the selected root save and edits its name',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      await saveSystem.hydrate();
      final projectId = saveSystem.createProject(
        'Fretboard project',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'Verse', lengthBars: 4);
      final snapshot = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      );
      final saveId = saveSystem.saveSnapshot('Root idea', projectId, snapshot)!;

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Root idea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('useWriterSaveButton')));
      await tester.pumpAndSettle();
      final sectionId = container.read(songwriterProvider).sections.single.id;
      await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('writerImportNameField')),
        'Verse shape',
      );
      await tester.tap(find.byKey(const Key('confirmWriterImportName')));
      await tester.pumpAndSettle();

      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      final reusedSave = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      expect(block.saveId, saveId);
      expect(reusedSave.name, 'Verse shape');
      expect(container.read(saveSystemProvider).saves, hasLength(1));
      expect(
        container
            .read(saveSystemProvider)
            .writerLinks
            .singleWhere((link) => link.blockId == block.id)
            .saveId,
        saveId,
      );

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verse shape'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed shape');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == saveId)
            .name,
        'Renamed shape',
      );
      expect(
        container
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .blocks
            .single
            .saveId,
        saveId,
      );
      await container.read(songwriterSessionsProvider.notifier).flush();
    },
  );

  testWidgets('save reuse and linked update fit compact and wide layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final viewport in [const Size(390, 844), const Size(1180, 820)]) {
      tester.view.physicalSize = viewport;
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      await saveSystem.hydrate();
      final projectId = saveSystem.createProject(
        'Fretboard project',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'Verse', lengthBars: 4);
      final snapshot = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      );
      final saveId = saveSystem.saveSnapshot('Root idea', projectId, snapshot)!;

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Root idea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('useWriterSaveButton')));
      await tester.pumpAndSettle();
      final sectionId = container.read(songwriterProvider).sections.single.id;
      await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('writerImportNameField')),
        'Verse shape',
      );
      await tester.tap(find.byKey(const Key('confirmWriterImportName')));
      await tester.pumpAndSettle();

      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect(block.saveId, saveId);
      expect(container.read(saveSystemProvider).saves, hasLength(1));

      container.read(fretboardProvider.notifier).setCapo(3);
      await tester.pumpWidget(_wrap(container, linkedEditSaveId: saveId));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('updateLinkedSaveButton')));
      await tester.pumpAndSettle();

      final canonical = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      final updatedBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .blocks
          .single;
      expect((canonical.snapshot as FretboardSnapshot).capo, 3);
      expect((updatedBlock.embedded! as FretboardSnapshot).capo, 3);
      await container.read(songwriterSessionsProvider.notifier).flush();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Update linked save writes through the same canonical ID', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    await saveSystem.hydrate();
    final projectId = saveSystem.createProject(
      'Fretboard project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [],
      selectedNotes: const [],
      viewMode: FretboardViewMode.exact,
    );
    final saveId = saveSystem.saveSnapshot(
      'Linked shape',
      projectId,
      snapshot,
    )!;
    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: sectionId,
        startBar: 0,
        snapshot: snapshot,
        saveName: 'Linked shape',
        reuseSaveId: saveId,
      ),
      isTrue,
    );
    container.read(fretboardProvider.notifier).setCapo(3);

    await tester.pumpWidget(_wrap(container, linkedEditSaveId: saveId));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updateLinkedSaveButton')));
    await tester.pumpAndSettle();

    final canonical = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((save) => save.id == saveId);
    final block = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    expect(canonical.id, saveId);
    expect((canonical.snapshot as FretboardSnapshot).capo, 3);
    expect((block.embedded! as FretboardSnapshot).capo, 3);
    await container.read(songwriterSessionsProvider.notifier).flush();
  });
}
