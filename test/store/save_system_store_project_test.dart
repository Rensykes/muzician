import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('createProject adds a kind=project root folder with config', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    final id = c.read(saveSystemProvider.notifier).createProject(
          'My song',
          const ProjectConfig(tempo: 100, keyRootPc: 0, keyScaleName: 'major'),
        );
    expect(id, isNotNull);
    final folder = c.read(saveSystemProvider).folders.firstWhere((f) => f.id == id);
    expect(folder.kind, SaveFolderKind.project);
    expect(folder.parentId, isNull);
    expect(folder.projectConfig?.tempo, 100);
    expect(folder.projectConfig?.keyRootPc, 0);
  });

  test('renameProject mutates only the named folder; trims whitespace', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    final id = c.read(saveSystemProvider.notifier).createProject('A', const ProjectConfig())!;
    c.read(saveSystemProvider.notifier).renameProject(id, '  B  ');
    expect(c.read(saveSystemProvider).folders.firstWhere((f) => f.id == id).name, 'B');
  });

  test('deleteProject removes folder, its saves, and clears selection if matching', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    final id = c.read(saveSystemProvider.notifier).createProject('A', const ProjectConfig())!;
    c.read(saveSystemProvider.notifier).selectProject(id);
    c.read(saveSystemProvider.notifier).deleteProject(id);
    expect(c.read(saveSystemProvider).folders.any((f) => f.id == id), isFalse);
    expect(c.read(saveSystemProvider).selectedProjectId, isNull);
  });

  test('updateProjectConfig overwrites projectConfig on the project folder', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    final id = c.read(saveSystemProvider.notifier).createProject('A', const ProjectConfig())!;
    c.read(saveSystemProvider.notifier).updateProjectConfig(
          id,
          const ProjectConfig(tempo: 90, keyRootPc: 9, keyScaleName: 'minor'),
        );
    final folder = c.read(saveSystemProvider).folders.firstWhere((f) => f.id == id);
    expect(folder.projectConfig?.tempo, 90);
    expect(folder.projectConfig?.keyRootPc, 9);
  });

  test('deleteFolder refuses to delete a dump root', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    final dumpId = c.read(saveSystemProvider.notifier).ensureDumpFolder();
    c.read(saveSystemProvider.notifier).deleteFolder(dumpId);
    expect(c.read(saveSystemProvider).folders.any((f) => f.id == dumpId), isTrue);
  });

  test('selectedProjectProvider tracks selected folder', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    expect(c.read(selectedProjectProvider), isNull);
    final id = c.read(saveSystemProvider.notifier).createProject('A', const ProjectConfig())!;
    c.read(saveSystemProvider.notifier).selectProject(id);
    expect(c.read(selectedProjectProvider)?.id, id);
  });

  test('projectsListProvider returns ordered project folders', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    c.read(saveSystemProvider.notifier).createProject('A', const ProjectConfig());
    c.read(saveSystemProvider.notifier).createProject('B', const ProjectConfig());
    final list = c.read(projectsListProvider);
    expect(list.map((f) => f.name), ['A', 'B']);
  });

  test('dumpFolderProvider null until ensureDumpFolder', () async {
    final c = makeContainer();
    await c.read(saveSystemProvider.notifier).hydrate();
    expect(c.read(dumpFolderProvider), isNull);
    c.read(saveSystemProvider.notifier).ensureDumpFolder();
    expect(c.read(dumpFolderProvider), isNotNull);
  });
}
