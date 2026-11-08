import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/project_config_sync.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fire-immediate startup sync replaces stale config without history',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      const authoritative = ProjectConfig(
        tempo: 120,
        beatsPerBar: 4,
        beatUnit: 4,
        keyRootPc: 0,
        keyScaleName: 'major',
      );
      final projectId = saveSystem.createProject('Writer', authoritative)!;
      saveSystem.selectProject(projectId);

      final writerSessions = container.read(
        songwriterSessionsProvider.notifier,
      );
      writerSessions.put(
        projectId,
        const SongwriterProjectSnapshot(
          config: SongwriterConfig(
            tempo: 137,
            beatsPerBar: 3,
            beatUnit: 4,
            keyRoot: 2,
            keyScaleName: 'minor',
          ),
        ),
      );

      final writer = container.read(songwriterProvider.notifier);
      expect(container.read(songwriterProvider).config.tempo, 137);

      container.read(projectConfigSyncProvider);
      await Future<void>.delayed(Duration.zero);

      final writerConfig = container.read(songwriterProvider).config;
      expect(writerConfig.tempo, 120);
      expect(writerConfig.beatsPerBar, 4);
      expect(writerConfig.keyRoot, 0);
      expect(writerConfig.keyScaleName, 'major');
      expect(writer.canUndo, isFalse);
    },
  );

  test(
    'config changes clear old history, equal sync preserves new history',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saveSystem = container.read(saveSystemProvider.notifier);
      const initial = ProjectConfig(
        tempo: 120,
        keyRootPc: 0,
        keyScaleName: 'major',
      );
      final projectId = saveSystem.createProject('Writer', initial)!;
      saveSystem.selectProject(projectId);
      container.read(projectConfigSyncProvider);
      await Future<void>.delayed(Duration.zero);

      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      expect(writer.canUndo, isTrue);

      saveSystem.updateProjectConfig(projectId, initial);
      await Future<void>.delayed(Duration.zero);
      expect(writer.canUndo, isTrue);

      const changed = ProjectConfig(
        tempo: 96,
        beatsPerBar: 3,
        beatUnit: 4,
        keyRootPc: 2,
        keyScaleName: 'minor',
      );
      saveSystem.updateProjectConfig(projectId, changed);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(songwriterProvider).config.tempo, 96);
      expect(container.read(songwriterProvider).config.beatsPerBar, 3);
      expect(container.read(songwriterProvider).config.keyRoot, 2);
      expect(writer.canUndo, isFalse);
      expect(writer.undo(), isFalse);
    },
  );
}
