import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/project_config_sync.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'no-key projects clear the previous project key across instruments',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      final keyedProject = saveSystem.createProject(
        'Keyed',
        const ProjectConfig(keyRootPc: 0, keyScaleName: 'major'),
      )!;
      final noKeyProject = saveSystem.createProject(
        'No key',
        const ProjectConfig(),
      )!;

      saveSystem.selectProject(keyedProject);
      container.read(projectConfigSyncProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeScaleProvider), (
        root: 'C',
        scaleName: 'major',
      ));

      container.read(pendingScaleProvider.notifier).state = (
        root: 'D',
        scaleName: 'minor',
      );
      container.read(pianoPendingScaleProvider.notifier).state = (
        root: 'D',
        scaleName: 'minor',
      );
      container.read(pianoRollPendingScaleProvider.notifier).state = (
        root: 'D',
        scaleName: 'minor',
      );
      container.read(fretboardProvider.notifier).setHighlightedNotes([
        'C',
        'E',
      ]);
      container.read(pianoProvider.notifier).setHighlightedNotes(['C', 'E']);
      container.read(pianoRollProvider.notifier).setKey('C');
      container.read(pianoRollProvider.notifier).setHighlightedNotes([
        'C',
        'E',
      ]);

      saveSystem.selectProject(noKeyProject);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(fretboardProvider).highlightedNotes, isEmpty);
      expect(container.read(pianoProvider).highlightedNotes, isEmpty);
      expect(container.read(pianoRollProvider).config.key, isNull);
      expect(container.read(pianoRollProvider).highlightedNotes, isEmpty);
      expect(container.read(activeScaleProvider), isNull);
      expect(container.read(pendingScaleProvider), isNull);
      expect(container.read(pianoActiveScaleProvider), isNull);
      expect(container.read(pianoPendingScaleProvider), isNull);
      expect(container.read(pianoRollActiveScaleProvider), isNull);
      expect(container.read(pianoRollPendingScaleProvider), isNull);
      expect(container.read(songwriterProvider).config.keyRoot, isNull);
      expect(container.read(songProjectProvider).config.scaleRoot, isNull);
    },
  );

  test(
    'a delayed selection sync cannot restore an older project key',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      final first = saveSystem.createProject(
        'First',
        const ProjectConfig(keyRootPc: 0, keyScaleName: 'major'),
      )!;
      final second = saveSystem.createProject(
        'Second',
        const ProjectConfig(keyRootPc: 7, keyScaleName: 'minor'),
      )!;

      container.read(projectConfigSyncProvider);
      saveSystem.selectProject(first);
      saveSystem.selectProject(second);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(activeProjectKeyProvider), (
        root: 'G',
        scaleName: 'minor',
      ));
      expect(container.read(pianoRollProvider).config.key, 'G');
      expect(container.read(songwriterProvider).config.keyRoot, 7);
      expect(container.read(songProjectProvider).config.scaleRoot, 'G');
    },
  );

  test('Dump clears a key left by the previously selected project', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final project = saveSystem.createProject(
      'Project',
      const ProjectConfig(keyRootPc: 2, keyScaleName: 'minor'),
    )!;
    final dump = saveSystem.ensureDumpFolder();

    saveSystem.selectProject(project);
    container.read(projectConfigSyncProvider);
    await Future<void>.delayed(Duration.zero);
    saveSystem.selectProject(dump);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(activeProjectKeyProvider), isNull);
    expect(container.read(fretboardProvider).highlightedNotes, isEmpty);
    expect(container.read(pianoProvider).highlightedNotes, isEmpty);
    expect(container.read(pianoRollProvider).config.key, isNull);
    expect(container.read(pianoRollProvider).highlightedNotes, isEmpty);
    expect(container.read(songwriterProvider).config.keyRoot, isNull);
    expect(container.read(songProjectProvider).config.scaleRoot, isNull);
  });
}
