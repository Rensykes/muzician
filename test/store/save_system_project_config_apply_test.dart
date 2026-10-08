import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applyProjectConfig retrofits PianoRollSnapshot fields', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    final pid = c
        .read(saveSystemProvider.notifier)
        .createProject(
          'A',
          const ProjectConfig(keyRootPc: 0, keyScaleName: 'major'),
        )!;

    c
        .read(saveSystemProvider.notifier)
        .saveSnapshot(
          'roll1',
          pid,
          PianoRollSnapshot(
            tempo: 140,
            key: 'D',
            numerator: 3,
            denominator: 4,
            totalMeasures: 8,
            notes: [],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            selectedColumnTick: null,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        );

    await c
        .read(saveSystemProvider.notifier)
        .applyProjectConfig(
          pid,
          const ProjectConfig(keyRootPc: 9, keyScaleName: 'minor', tempo: 100),
          retrofit: true,
        );

    final retrofitted =
        c
                .read(saveSystemProvider)
                .saves
                .firstWhere((s) => s.folderId == pid)
                .snapshot
            as PianoRollSnapshot;
    expect(retrofitted.tempo, 100);
    expect(retrofitted.key, 'A');
    expect(retrofitted.numerator, 4);
    expect(retrofitted.denominator, 4);
  });

  test('project config retrofit preserves Fretboard input mode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final saves = c.read(saveSystemProvider.notifier);
    await saves.hydrate();
    final projectId = saves.createProject('A', const ProjectConfig())!;
    saves.saveSnapshot(
      'chord mode',
      projectId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C'],
        viewMode: FretboardViewMode.exact,
        inputMode: FretboardInputMode.chord,
      ),
    );

    await saves.applyProjectConfig(
      projectId,
      const ProjectConfig(keyRootPc: 9, keyScaleName: 'minor'),
      retrofit: true,
    );

    final retrofitted =
        c
                .read(saveSystemProvider)
                .saves
                .singleWhere((save) => save.folderId == projectId)
                .snapshot
            as FretboardSnapshot;
    expect(retrofitted.inputMode, FretboardInputMode.chord);
  });
}
