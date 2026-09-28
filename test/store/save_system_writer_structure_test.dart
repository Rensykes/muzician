import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/save_system_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

FretboardSnapshot _snapshot() => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [],
  selectedNotes: const ['A', 'C', 'E'],
  viewMode: FretboardViewMode.exact,
);

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

ProviderContainer _containerWithState(SaveSystemState state) {
  final container = ProviderContainer(
    overrides: [
      saveSystemProvider.overrideWith(() => _SeededSaveSystemNotifier(state)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<String> _selectedProject(ProviderContainer container) async {
  final saves = container.read(saveSystemProvider.notifier);
  await saves.hydrate();
  final id = saves.createProject('Writer project', const ProjectConfig())!;
  saves.selectProject(id);
  return id;
}

SaveFolder _laneFolder(
  SaveSystemState state, {
  required String projectId,
  required SaveFolder sectionFolder,
  required String sectionId,
  required SongLaneKind laneKind,
}) {
  final staged = state.copyWith(folders: [...state.folders, sectionFolder]);
  return getOrCreateWriterLaneFolder(
    staged,
    projectId: projectId,
    sectionId: sectionId,
    laneKind: laneKind,
    sectionFolder: sectionFolder,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Save System refuses ordinary mutations of linked Writer saves',
    () async {
      final container = _container();
      final projectId = await _selectedProject(container);
      final saves = container.read(saveSystemProvider.notifier);
      final sectionFolder = createWriterSectionFolder(
        container.read(saveSystemProvider),
        projectId: projectId,
        sectionId: 'section',
        name: 'Verse',
        order: 0,
      );
      final laneFolder = _laneFolder(
        container.read(saveSystemProvider),
        projectId: projectId,
        sectionFolder: sectionFolder,
        sectionId: 'section',
        laneKind: SongLaneKind.save,
      );
      final saveId = saves.saveSnapshot('Shared idea', projectId, _snapshot())!;
      final current = container.read(saveSystemProvider);
      final next = current.copyWith(
        folders: [...current.folders, sectionFolder, laneFolder],
        writerLinks: [
          WriterSaveLink(
            blockId: 'block',
            sectionId: 'section',
            folderId: laneFolder.id,
            saveId: saveId,
            laneKind: SongLaneKind.save,
          ),
        ],
      );
      final prepared = saves.buildWriterStructure(projectId, next)!;
      expect(container.read(saveSystemProvider).writerLinks, isEmpty);
      expect(
        deserialiseState(serialiseSaveSystemState(prepared))!.writerLinks,
        hasLength(1),
      );
      expect(
        saves.commitWriterStructure(projectId, prepared, persist: false),
        isTrue,
      );

      expect(saves.deleteSave(saveId), isFalse);
      expect(saves.lastMutationError, contains('Writer blocks'));
      expect(saves.updateSnapshot(saveId, _snapshot()), isFalse);
      expect(saves.lastMutationError, contains('Writer'));
      expect(saves.deleteFolder(sectionFolder.id), isFalse);
      expect(saves.lastMutationError, contains('Writer'));
      expect(saves.renameFolder(laneFolder.id, 'Changed'), isFalse);
      expect(saves.renameFolder(sectionFolder.id, 'Changed'), isFalse);
      expect(saves.createSaveFolder('Manual child', sectionFolder.id), isNull);
      expect(
        saves.saveSnapshot('Manual save', sectionFolder.id, _snapshot()),
        isNull,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .any((save) => save.id == saveId),
        isTrue,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == saveId)
            .folderId,
        projectId,
      );
    },
  );

  test(
    'ordinary folder cascade is blocked when it contains a linked save',
    () async {
      final container = _container();
      final projectId = await _selectedProject(container);
      final saves = container.read(saveSystemProvider.notifier);
      final ordinaryFolder = saves.createSaveFolder('Ideas', projectId)!;
      final saveId = saves.saveSnapshot(
        'Linked idea',
        ordinaryFolder,
        _snapshot(),
      )!;
      final current = container.read(saveSystemProvider);
      final sectionFolder = createWriterSectionFolder(
        current,
        projectId: projectId,
        sectionId: 'verse',
        name: 'Verse',
        order: 0,
      );
      final laneFolder = _laneFolder(
        current,
        projectId: projectId,
        sectionFolder: sectionFolder,
        sectionId: 'verse',
        laneKind: SongLaneKind.harmony,
      );
      final next = current.copyWith(
        folders: [...current.folders, sectionFolder, laneFolder],
        writerLinks: [
          WriterSaveLink(
            blockId: 'linked-block',
            sectionId: 'verse',
            folderId: laneFolder.id,
            saveId: saveId,
            laneKind: SongLaneKind.harmony,
          ),
        ],
      );
      expect(saves.commitWriterStructure(projectId, next), isTrue);

      expect(saves.deleteFolder(ordinaryFolder), isFalse);
      expect(saves.lastMutationError, contains('Linked idea'));
      expect(
        container
            .read(saveSystemProvider)
            .folders
            .any((folder) => folder.id == ordinaryFolder),
        isTrue,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == saveId)
            .folderId,
        ordinaryFolder,
      );
    },
  );

  test(
    'Writer-origin saves retain their source folder and rehome after owner deletion',
    () async {
      final container = _container();
      final projectId = await _selectedProject(container);
      final saves = container.read(saveSystemProvider.notifier);
      final current = container.read(saveSystemProvider);
      final sourceSection = createWriterSectionFolder(
        current,
        projectId: projectId,
        sectionId: 'later-section',
        name: 'Chorus',
        order: 1,
      );
      final sourceLane = _laneFolder(
        current,
        projectId: projectId,
        sectionFolder: sourceSection,
        sectionId: 'later-section',
        laneKind: SongLaneKind.harmony,
      );
      final earlierSection = createWriterSectionFolder(
        current,
        projectId: projectId,
        sectionId: 'earlier-section',
        name: 'Verse',
        order: 0,
      );
      final earlierLane = _laneFolder(
        current,
        projectId: projectId,
        sectionFolder: earlierSection,
        sectionId: 'earlier-section',
        laneKind: SongLaneKind.harmony,
      );
      final folders = [
        ...current.folders,
        sourceSection,
        sourceLane,
        earlierSection,
        earlierLane,
      ];
      final entry = createWriterSaveEntry(
        'Writer idea',
        sourceLane.id,
        _snapshot(),
        0,
      );
      final sourceLink = WriterSaveLink(
        blockId: 'writer-block',
        sectionId: 'later-section',
        folderId: sourceLane.id,
        saveId: entry.id,
        laneKind: SongLaneKind.harmony,
      );
      final earlierLink = WriterSaveLink(
        blockId: 'earlier-writer-block',
        sectionId: 'earlier-section',
        folderId: earlierLane.id,
        saveId: entry.id,
        laneKind: SongLaneKind.harmony,
      );
      final linked = current.copyWith(
        folders: folders,
        saves: [...current.saves, entry],
        writerLinks: [sourceLink],
      );
      expect(
        saves.commitWriterStructure(projectId, linked),
        isTrue,
        reason: saves.lastMutationError,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .firstWhere((save) => save.id == entry.id)
            .folderId,
        sourceLane.id,
      );

      final sourceState = container.read(saveSystemProvider);
      final reversedLinks = sourceState.copyWith(
        writerLinks: [earlierLink, sourceLink],
      );
      expect(
        saves.commitWriterStructure(projectId, reversedLinks),
        isTrue,
        reason: saves.lastMutationError,
      );
      var retained = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == entry.id);
      expect(retained.id, entry.id);
      expect(retained.folderId, sourceLane.id);

      final linkedState = container.read(saveSystemProvider);
      final sourceSubtreeIds = getSubtreeFolderIds(
        linkedState.folders,
        sourceSection.id,
      );
      final removedOwner = linkedState.copyWith(
        folders: linkedState.folders
            .where((folder) => !sourceSubtreeIds.contains(folder.id))
            .toList(),
        writerLinks: [earlierLink],
      );
      expect(
        saves.commitWriterStructure(projectId, removedOwner),
        isTrue,
        reason: saves.lastMutationError,
      );
      retained = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == entry.id);
      expect(retained.id, entry.id);
      expect(retained.folderId, earlierLane.id);

      final rehomedState = container.read(saveSystemProvider);
      final earlierSubtreeIds = getSubtreeFolderIds(
        rehomedState.folders,
        earlierSection.id,
      );
      final noOwnerNoLinks = rehomedState.copyWith(
        folders: rehomedState.folders
            .where((folder) => !earlierSubtreeIds.contains(folder.id))
            .toList(),
        writerLinks: const [],
      );
      expect(
        saves.commitWriterStructure(projectId, noOwnerNoLinks),
        isTrue,
        reason: saves.lastMutationError,
      );
      retained = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == entry.id);
      expect(retained.id, entry.id);
      expect(retained.folderId, projectId);
    },
  );

  test(
    'Writer links require their direct matching section lane category',
    () async {
      final container = _container();
      final projectId = await _selectedProject(container);
      final saves = container.read(saveSystemProvider.notifier);
      final current = container.read(saveSystemProvider);
      final sectionFolder = createWriterSectionFolder(
        current,
        projectId: projectId,
        sectionId: 'section',
        name: 'Verse',
        order: 0,
      );
      final laneFolder = _laneFolder(
        current,
        projectId: projectId,
        sectionFolder: sectionFolder,
        sectionId: 'section',
        laneKind: SongLaneKind.harmony,
      );
      final saveId = saves.saveSnapshot('Idea', projectId, _snapshot())!;
      final next = current.copyWith(
        folders: [...current.folders, sectionFolder, laneFolder],
        writerLinks: [
          WriterSaveLink(
            blockId: 'block',
            sectionId: 'section',
            folderId: laneFolder.id,
            saveId: saveId,
            laneKind: SongLaneKind.save,
          ),
        ],
      );

      expect(saves.buildWriterStructure(projectId, next), isNull);
      expect(saves.lastMutationError, contains('invalid'));
      expect(container.read(saveSystemProvider).writerLinks, isEmpty);

      final nestedFolder = createFolder('Nested', laneFolder.id, 0);
      final nestedTarget = current.copyWith(
        folders: [...current.folders, sectionFolder, laneFolder, nestedFolder],
        writerLinks: [
          WriterSaveLink(
            blockId: 'nested-block',
            sectionId: 'section',
            folderId: nestedFolder.id,
            saveId: saveId,
            laneKind: SongLaneKind.harmony,
          ),
        ],
      );
      expect(saves.buildWriterStructure(projectId, nestedTarget), isNull);
      expect(saves.lastMutationError, contains('invalid'));
    },
  );

  test(
    'manual saves stay put on link changes and rehome when a managed ancestor is deleted',
    () async {
      const projectId = 'project';
      const project = SaveFolder(
        id: projectId,
        name: 'Project',
        createdAt: 1,
        order: 0,
        kind: SaveFolderKind.project,
        projectConfig: ProjectConfig(),
      );
      const sectionFolder = SaveFolder(
        id: 'section-folder',
        name: 'Verse',
        parentId: projectId,
        createdAt: 2,
        order: 0,
        writerSectionId: 'section',
      );
      const laneFolder = SaveFolder(
        id: 'harmony-category',
        name: 'Harmony',
        parentId: 'section-folder',
        createdAt: 3,
        order: 0,
        writerSectionId: 'section',
        writerLaneKind: SongLaneKind.harmony,
      );
      const nested = SaveFolder(
        id: 'nested-folder',
        name: 'Nested',
        parentId: 'harmony-category',
        createdAt: 4,
        order: 0,
      );
      final snapshot = _snapshot();
      final manualSave = SaveEntry(
        id: 'manual-save',
        name: 'Keep this idea',
        folderId: nested.id,
        snapshot: snapshot,
        createdAt: 5,
        updatedAt: 5,
        order: 0,
      );
      final link = WriterSaveLink(
        blockId: 'block',
        sectionId: 'section',
        folderId: laneFolder.id,
        saveId: manualSave.id,
        laneKind: SongLaneKind.harmony,
      );
      final seed = SaveSystemState(
        folders: const [project, sectionFolder, laneFolder, nested],
        saves: [manualSave],
        writerLinks: [link],
        hydrated: true,
        selectedProjectId: projectId,
      );
      final container = _containerWithState(seed);
      final saves = container.read(saveSystemProvider.notifier);
      final unlinkOnly = seed.copyWith(writerLinks: const []);
      expect(
        saves.commitWriterStructure(projectId, unlinkOnly, persist: false),
        isTrue,
      );
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == manualSave.id)
            .folderId,
        nested.id,
      );

      final unlinkedState = container.read(saveSystemProvider);
      final categorySubtreeIds = getSubtreeFolderIds(
        unlinkedState.folders,
        laneFolder.id,
      );
      final deleteCategory = unlinkedState.copyWith(
        folders: unlinkedState.folders
            .where((folder) => !categorySubtreeIds.contains(folder.id))
            .toList(),
      );

      final removeCategory = seed.copyWith(
        folders: deleteCategory.folders,
        saves: deleteCategory.saves,
        writerLinks: deleteCategory.writerLinks,
      );
      expect(
        saves.commitWriterStructure(projectId, removeCategory, persist: false),
        isTrue,
      );
      final rehomed = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == manualSave.id);
      expect(rehomed.folderId, projectId);
      expect(rehomed.id, manualSave.id);
      expect(rehomed.name, manualSave.name);
      expect(rehomed.snapshot, same(manualSave.snapshot));
    },
  );

  test('Writer sync rejects a save from another project', () async {
    final container = _container();
    final projectId = await _selectedProject(container);
    final saves = container.read(saveSystemProvider.notifier);
    final foreignProjectId = saves.createProject(
      'Foreign project',
      const ProjectConfig(),
    )!;
    final foreignSaveId = saves.saveSnapshot(
      'Foreign idea',
      foreignProjectId,
      _snapshot(),
    )!;
    saves.selectProject(projectId);
    final current = container.read(saveSystemProvider);
    final sectionFolder = createWriterSectionFolder(
      current,
      projectId: projectId,
      sectionId: 'section',
      name: 'Verse',
      order: 0,
    );
    final laneFolder = _laneFolder(
      current,
      projectId: projectId,
      sectionFolder: sectionFolder,
      sectionId: 'section',
      laneKind: SongLaneKind.save,
    );
    final next = current.copyWith(
      folders: [...current.folders, sectionFolder, laneFolder],
      writerLinks: [
        WriterSaveLink(
          blockId: 'block',
          sectionId: 'section',
          folderId: laneFolder.id,
          saveId: foreignSaveId,
          laneKind: SongLaneKind.save,
        ),
      ],
    );

    expect(saves.commitWriterStructure(projectId, next), isFalse);
    expect(saves.lastMutationError, contains('invalid'));
    expect(container.read(saveSystemProvider).writerLinks, isEmpty);
  });
}

class _SeededSaveSystemNotifier extends SaveSystemNotifier {
  final SaveSystemState seed;

  _SeededSaveSystemNotifier(this.seed);

  @override
  SaveSystemState build() => seed;
}
