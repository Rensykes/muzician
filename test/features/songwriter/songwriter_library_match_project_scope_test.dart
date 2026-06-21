import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('searchableSavesForLibraryMatch only returns selected project subtree', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();

    final p1 = c.read(saveSystemProvider.notifier).createProject('A', const ProjectConfig())!;
    final p2 = c.read(saveSystemProvider.notifier).createProject('B', const ProjectConfig())!;

    // Insert saves under both projects.
    c.read(saveSystemProvider.notifier).saveSnapshot(
      's1',
      p1,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      ),
    );
    c.read(saveSystemProvider.notifier).saveSnapshot(
      's2',
      p2,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const [],
        viewMode: FretboardViewMode.exact,
      ),
    );

    c.read(saveSystemProvider.notifier).selectProject(p1);

    final notifier = c.read(songwriterProvider.notifier);
    final hits = notifier.searchableSavesForLibraryMatch();
    expect(hits.every((s) => s.folderId == p1), isTrue);
    expect(hits.length, 1);
  });
}
