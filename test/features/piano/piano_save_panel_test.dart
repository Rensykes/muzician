import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano/piano_save_panel.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/models/project_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(ProviderContainer container, {String? linkedEditSaveId}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: PianoSavePanel(linkedEditSaveId: linkedEditSaveId)),
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

  testWidgets(
    'loading a snapshot with a scale syncs pending and active scale',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final saveSystem = container.read(saveSystemProvider.notifier);
      final dumpId = saveSystem.ensureDumpFolder();
      saveSystem.selectProject(dumpId);
      final folderId = container
          .read(saveSystemProvider.notifier)
          .createSaveFolder('Piano Saves', dumpId);
      expect(folderId, isNotNull);

      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'With Scale',
            folderId!,
            PianoSnapshot(
              currentRange: PianoRangeName.key61,
              selectedKeys: const [],
              selectedNotes: const [],
              viewMode: PianoViewMode.exact,
              pendingScale: const PendingScale(root: 'D', scaleName: 'dorian'),
            ),
          );
      expect(saveId, isNotNull);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _loadSave(
        tester,
        folderName: 'Piano Saves',
        saveName: 'With Scale',
      );

      expect(container.read(pianoPendingScaleProvider), (
        root: 'D',
        scaleName: 'dorian',
      ));
      expect(container.read(pianoActiveScaleProvider), (
        root: 'D',
        scaleName: 'dorian',
      ));
    },
  );

  testWidgets('Dump root ideas do not offer Use in Writer', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final dumpId = saveSystem.ensureDumpFolder();
    saveSystem.selectProject(dumpId);
    saveSystem.saveSnapshot(
      'Dump piano',
      dumpId,
      PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const [],
        viewMode: PianoViewMode.exact,
      ),
    );

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dump piano'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('useWriterSaveButton')), findsNothing);
    expect(find.byKey(const Key('useWriterSaveAction')), findsNothing);
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
      'Piano project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.single;
    final snapshot = PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [],
      selectedNotes: const [],
      viewMode: PianoViewMode.exact,
    );
    final saveId = saveSystem.saveSnapshot(
      'Linked piano',
      projectId,
      snapshot,
    )!;
    expect(
      writer.insertInstrumentSelectionAtBar(
        sectionId: section.id,
        startBar: 0,
        snapshot: snapshot,
        saveName: 'Linked piano',
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

  testWidgets('Use in Writer reuses a root Piano save and can update it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    await saveSystem.hydrate();
    final projectId = saveSystem.createProject(
      'Piano project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'Verse', lengthBars: 4);
    final snapshot = PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [],
      selectedNotes: const [],
      viewMode: PianoViewMode.exact,
    );
    final saveId = saveSystem.saveSnapshot('Piano idea', projectId, snapshot)!;

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piano idea'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('useWriterSaveButton')));
    await tester.pumpAndSettle();
    final sectionId = container.read(songwriterProvider).sections.single.id;
    await tester.tap(find.byKey(Key('writerHandoffBar_${sectionId}_0')));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piano idea'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed piano idea');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId)
          .name,
      'Renamed piano idea',
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

    container.read(pianoProvider.notifier).setRange(PianoRangeName.key88);
    await tester.pumpWidget(_wrap(container, linkedEditSaveId: saveId));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updateLinkedSaveButton')));
    await tester.pumpAndSettle();
    final canonical = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((save) => save.id == saveId);
    expect(
      (canonical.snapshot as PianoSnapshot).currentRange,
      PianoRangeName.key88,
    );
    await container.read(songwriterSessionsProvider.notifier).flush();
  });

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
        'Piano project',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'Verse', lengthBars: 4);
      final snapshot = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const [],
        viewMode: PianoViewMode.exact,
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

      container.read(pianoProvider.notifier).setRange(PianoRangeName.key88);
      await tester.pumpWidget(_wrap(container, linkedEditSaveId: saveId));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('updateLinkedSaveButton')));
      await tester.pumpAndSettle();

      final canonical = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      expect(
        (canonical.snapshot as PianoSnapshot).currentRange,
        PianoRangeName.key88,
      );
      await container.read(songwriterSessionsProvider.notifier).flush();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
