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

Future<String> _selectedProject(ProviderContainer container) async {
  final saves = container.read(saveSystemProvider.notifier);
  await saves.hydrate();
  final id = saves.createProject('Writer project', const ProjectConfig())!;
  saves.selectProject(id);
  return id;
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
      final saveId = saves.saveSnapshot('Shared idea', projectId, _snapshot())!;
      final current = container.read(saveSystemProvider);
      final next = current.copyWith(
        folders: [...current.folders, sectionFolder],
        writerLinks: [
          WriterSaveLink(
            blockId: 'block',
            sectionId: 'section',
            folderId: sectionFolder.id,
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
      final next = current.copyWith(
        folders: [...current.folders, sectionFolder],
        writerLinks: [
          WriterSaveLink(
            blockId: 'linked-block',
            sectionId: 'verse',
            folderId: sectionFolder.id,
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
    },
  );

  test(
    'Writer-origin saves move to their earliest link and return to root',
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
      final entry = createWriterSaveEntry(
        'Writer idea',
        sectionFolder.id,
        _snapshot(),
        0,
      );
      final link = WriterSaveLink(
        blockId: 'writer-block',
        sectionId: 'section',
        folderId: sectionFolder.id,
        saveId: entry.id,
        laneKind: SongLaneKind.harmony,
      );
      final linked = current.copyWith(
        folders: [...current.folders, sectionFolder],
        saves: [...current.saves, entry],
        writerLinks: [link],
      );
      expect(saves.commitWriterStructure(projectId, linked), isTrue);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .firstWhere((save) => save.id == entry.id)
            .folderId,
        sectionFolder.id,
      );

      final linkedState = container.read(saveSystemProvider);
      final removedSection = linkedState.copyWith(
        folders: linkedState.folders
            .where((folder) => folder.id != sectionFolder.id)
            .toList(),
        writerLinks: const [],
      );
      expect(saves.commitWriterStructure(projectId, removedSection), isTrue);
      final rehomed = container
          .read(saveSystemProvider)
          .saves
          .firstWhere((save) => save.id == entry.id);
      expect(rehomed.folderId, projectId);
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
    final next = current.copyWith(
      folders: [...current.folders, sectionFolder],
      writerLinks: [
        WriterSaveLink(
          blockId: 'block',
          sectionId: 'section',
          folderId: sectionFolder.id,
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
