import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/schema/rules/save_system_rules.dart';

SaveFolder _folder(String id,
    {String? parent,
    SaveFolderKind kind = SaveFolderKind.normal,
    int order = 0,
    String name = 'f'}) =>
    SaveFolder(
      id: id,
      name: name,
      parentId: parent,
      createdAt: 0,
      order: order,
      kind: kind,
      projectConfig: kind == SaveFolderKind.project ? const ProjectConfig() : null,
    );

SaveEntry _save(String id, String folderId) => SaveEntry(
      id: id,
      name: id,
      folderId: folderId,
      snapshot: FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      ),
      createdAt: 0,
      updatedAt: 0,
      order: 0,
    );

void main() {
  group('project + dump + subtree helpers', () {
    test('getProjectFolders returns only kind==project root folders, sorted', () {
      final folders = [
        _folder('a', kind: SaveFolderKind.project, order: 1, name: 'A'),
        _folder('b', kind: SaveFolderKind.dump, order: 2, name: 'Dump'),
        _folder('c', kind: SaveFolderKind.project, order: 0, name: 'C'),
        _folder('d', parent: 'a', name: 'sub'),
      ];
      final projects = getProjectFolders(folders);
      expect(projects.map((f) => f.id), ['c', 'a']);
    });

    test('getDumpFolder returns the dump folder or null', () {
      final folders = [
        _folder('a', kind: SaveFolderKind.project),
        _folder('b', kind: SaveFolderKind.dump),
      ];
      expect(getDumpFolder(folders)?.id, 'b');
      expect(getDumpFolder([_folder('a', kind: SaveFolderKind.project)]), isNull);
    });

    test('getSubtreeFolderIds includes root + descendants', () {
      final folders = [
        _folder('p', kind: SaveFolderKind.project),
        _folder('v', parent: 'p'),
        _folder('c', parent: 'p'),
        _folder('v1', parent: 'v'),
      ];
      expect(getSubtreeFolderIds(folders, 'p'), {'p', 'v', 'c', 'v1'});
    });

    test('getSavesInSubtree filters saves by subtree membership', () {
      final folders = [
        _folder('p', kind: SaveFolderKind.project),
        _folder('v', parent: 'p'),
        _folder('o', kind: SaveFolderKind.project),
      ];
      final saves = [_save('s1', 'p'), _save('s2', 'v'), _save('s3', 'o')];
      final ids = getSavesInSubtree(folders, saves, 'p').map((s) => s.id).toSet();
      expect(ids, {'s1', 's2'});
    });

    test('isProjectRoot / isDumpRoot', () {
      expect(isProjectRoot(_folder('a', kind: SaveFolderKind.project)), isTrue);
      expect(isProjectRoot(_folder('a')), isFalse);
      expect(isDumpRoot(_folder('a', kind: SaveFolderKind.dump)), isTrue);
      expect(isDumpRoot(_folder('a')), isFalse);
    });
  });
}
