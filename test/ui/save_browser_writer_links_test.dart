import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/ui/save_browser_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Writer links appear in their section folder once', (
    tester,
  ) async {
    final state = _stateWithSectionSave();
    final container = ProviderContainer(
      overrides: [
        saveSystemProvider.overrideWith(() => _SeededSaveSystemNotifier(state)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SaveBrowserPanel(
              rootFolderId: 'project',
              allowedInstruments: const {'writer_block'},
              onRenameLinkedSave: (_, _) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verse'));
    await tester.pumpAndSettle();

    expect(find.text('Shared chord'), findsOneWidget);
    expect(find.text('Writer link'), findsOneWidget);
  });

  testWidgets('managed folder controls stay locked and linked rename routes', (
    tester,
  ) async {
    final state = _stateWithSectionSave();
    final container = ProviderContainer(
      overrides: [
        saveSystemProvider.overrideWith(() => _SeededSaveSystemNotifier(state)),
      ],
    );
    addTearDown(container.dispose);

    String? renamedId;
    String? renamedName;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SaveBrowserPanel(
              rootFolderId: 'project',
              allowedInstruments: const {'writer_block'},
              onRenameLinkedSave: (saveId, name) {
                renamedId = saveId;
                renamedName = name;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.tap(find.text('Verse'));
    await tester.pumpAndSettle();
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'managed folder names are controlled by Writer',
    );

    await tester.tap(find.text('Shared chord'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed chord');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(renamedId, 'save');
    expect(renamedName, 'Renamed chord');
  });

  testWidgets('ordinary folder delete control is tappable and at least 44px', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        saveSystemProvider.overrideWith(
          () => _SeededSaveSystemNotifier(_stateWithOrdinaryFolder()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SaveBrowserPanel(rootFolderId: 'project')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final deleteButton = find.ancestor(
      of: find.byIcon(Icons.delete_outline),
      matching: find.byType(IconButton),
    );
    expect(deleteButton, findsOneWidget);
    final buttonSize = tester.getSize(deleteButton);
    expect(buttonSize.width, greaterThanOrEqualTo(44));
    expect(buttonSize.height, greaterThanOrEqualTo(44));

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      container.read(saveSystemProvider).folders.map((folder) => folder.id),
      ['project'],
    );
  });

  testWidgets('linked saves explain Writer-owned rename and delete guards', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        saveSystemProvider.overrideWith(
          () => _SeededSaveSystemNotifier(_stateWithSectionSave()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SaveBrowserPanel(
              rootFolderId: 'project',
              allowedInstruments: const {'writer_block'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Writer link · rename in Writer'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.startsWith('Remove linked Writer blocks') ??
                false),
      ),
      findsOneWidget,
    );
  });
}

SaveSystemState _stateWithOrdinaryFolder() {
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const ordinaryFolder = SaveFolder(
    id: 'ordinary-folder',
    name: 'Ordinary folder',
    parentId: 'project',
    createdAt: 2,
    order: 0,
  );
  return const SaveSystemState(
    folders: [project, ordinaryFolder],
    saves: [],
    hydrated: true,
    selectedProjectId: 'project',
  );
}

SaveSystemState _stateWithSectionSave() {
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const sectionFolder = SaveFolder(
    id: 'section-folder',
    name: 'Verse',
    parentId: 'project',
    createdAt: 2,
    order: 0,
    writerSectionId: 'section',
  );
  const block = WriterBlockSnapshot(
    laneKind: SongLaneKind.harmony,
    chordSymbol: 'Am7',
    chordNotes: ['A', 'C', 'E', 'G'],
  );
  const save = SaveEntry(
    id: 'save',
    name: 'Shared chord',
    folderId: 'section-folder',
    snapshot: block,
    createdAt: 3,
    updatedAt: 3,
    order: 0,
    origin: SaveOrigin.writer,
  );
  const link = WriterSaveLink(
    blockId: 'block',
    sectionId: 'section',
    folderId: 'section-folder',
    saveId: 'save',
    laneKind: SongLaneKind.harmony,
  );
  return const SaveSystemState(
    folders: [project, sectionFolder],
    saves: [save],
    writerLinks: [link],
    hydrated: true,
    selectedProjectId: 'project',
  );
}

class _SeededSaveSystemNotifier extends SaveSystemNotifier {
  final SaveSystemState seed;

  _SeededSaveSystemNotifier(this.seed);

  @override
  SaveSystemState build() => seed;
}
