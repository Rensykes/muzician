// test/store/songwriter_project_folder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer freshContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(saveSystemProvider.notifier);
    return c;
  }

  InstrumentSnapshot stubSnapshot() => FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      );

  test('setProjectName updates the project name', () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    expect(c.read(songwriterProvider).name, 'Untitled song');
    sw.setProjectName('Song A');
    expect(c.read(songwriterProvider).name, 'Song A');
  });

  test('setProjectName rejects empty/whitespace', () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');
    sw.setProjectName('');
    sw.setProjectName('   ');
    expect(c.read(songwriterProvider).name, 'Song A');
  });

  test('setProjectName renames the project folder if it exists', () {
    final c = freshContainer();
    final saves = c.read(saveSystemProvider.notifier);
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');
    saves.createSaveFolder('Song A', null);
    sw.setProjectName('Song B');
    final folder = c
        .read(saveSystemProvider)
        .folders
        .singleWhere((f) => f.parentId == null);
    expect(folder.name, 'Song B');
  });

  test('searchableSavesForLibraryMatch is empty when project folder is missing',
      () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');
    expect(sw.searchableSavesForLibraryMatch(), isEmpty);
    expect(c.read(saveSystemProvider).folders, isEmpty,
        reason: 'must not auto-create the project folder');
  });

  test('searchableSavesForLibraryMatch walks descendant folders', () {
    final c = freshContainer();
    final saves = c.read(saveSystemProvider.notifier);
    final sw = c.read(songwriterProvider.notifier);
    sw.setProjectName('Song A');

    final rootId = saves.createSaveFolder('Song A', null)!;
    final innerId = saves.createSaveFolder('Verse', rootId)!;
    final deeperId = saves.createSaveFolder('Chord palette', innerId)!;
    final unrelatedId = saves.createSaveFolder('Other song', null)!;

    saves.saveSnapshot('rootSave', rootId, stubSnapshot());
    saves.saveSnapshot('innerSave', innerId, stubSnapshot());
    saves.saveSnapshot('deeperSave', deeperId, stubSnapshot());
    saves.saveSnapshot('outsideSave', unrelatedId, stubSnapshot());

    final names = sw
        .searchableSavesForLibraryMatch()
        .map((s) => s.name)
        .toSet();
    expect(names, {'rootSave', 'innerSave', 'deeperSave'});
  });

  test('setProjectName with no prior folder does not create one', () {
    final c = freshContainer();
    final sw = c.read(songwriterProvider.notifier);
    expect(() => sw.setProjectName('Song A'), returnsNormally);
    expect(c.read(saveSystemProvider).folders, isEmpty);
  });
}
