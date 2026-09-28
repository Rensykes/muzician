import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $finder.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'edit target clears after loading another save or switching project',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MuzicianApp(),
        ),
      );
      await _pumpUntil(tester, find.byType(IndexedStack));

      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'Instrument project',
        const ProjectConfig(),
      )!;
      final otherProjectId = saves.createProject(
        'Other project',
        const ProjectConfig(),
      )!;
      saves.selectProject(projectId);
      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final linkedSnapshot = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      );
      final linkedSaveId = saves.saveSnapshot(
        'Linked shape',
        projectId,
        linkedSnapshot,
      )!;
      saves.saveSnapshot(
        'Other shape',
        projectId,
        FretboardSnapshot(
          tuning: TuningName.standard,
          numFrets: 12,
          capo: 2,
          selectedCells: const [],
          selectedNotes: const [],
          viewMode: FretboardViewMode.exact,
        ),
      );
      expect(
        writer.insertInstrumentSelectionAtBar(
          sectionId: sectionId,
          startBar: 0,
          snapshot: linkedSnapshot,
          saveName: 'Linked shape',
          reuseSaveId: linkedSaveId,
        ),
        isTrue,
      );
      final block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save)
          .blocks
          .single;
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('saveCell_${block.id}_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barActionEditInstrument')));
      await tester.pumpAndSettle();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsOneWidget);
      await tester.tap(find.text('Other shape'));
      await tester.pumpAndSettle();
      final loadOtherSave = find.text('Load').last;
      await tester.ensureVisible(loadOtherSave);
      await tester.pumpAndSettle();
      await tester.tap(loadOtherSave);
      await tester.pumpAndSettle();
      expect(
        container.read(saveSystemProvider).activeSession?.saveId,
        isNot(linkedSaveId),
      );
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav_Writer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('saveCell_${block.id}_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barActionEditInstrument')));
      await tester.pumpAndSettle();
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

      saves.selectProject(otherProjectId);
      await tester.pumpAndSettle();
      saves.selectProject(projectId);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsNothing);
    },
  );

  testWidgets(
    'shell clears edit target when a link is removed while saves are closed',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MuzicianApp(),
        ),
      );
      await _pumpUntil(tester, find.byType(IndexedStack));

      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'Instrument project',
        const ProjectConfig(),
      )!;
      saves.selectProject(projectId);
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
      final saveId = saves.saveSnapshot('Linked shape', projectId, snapshot)!;
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

      var block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save)
          .blocks
          .single;
      final lane = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('saveCell_${block.id}_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barActionEditInstrument')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav_Writer')));
      await tester.pumpAndSettle();
      writer.removeBlock(
        sectionId: sectionId,
        laneId: lane.id,
        blockId: block.id,
      );
      await tester.pumpAndSettle();
      expect(container.read(saveSystemProvider).writerLinks, isEmpty);

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
      block = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.kind == SongLaneKind.save)
          .blocks
          .single;
      expect(block.saveId, saveId);
      expect(container.read(saveSystemProvider).writerLinks, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('nav_Fretboard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLinkedSaveButton')), findsNothing);
    },
  );
}
