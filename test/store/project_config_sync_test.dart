import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/song_rules.dart';
import 'package:muzician/store/project_config_sync.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/song_sessions_store.dart';
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
      final projectId = saveSystem.createProject('Song', authoritative)!;
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
      final songSessions = container.read(songSessionsProvider.notifier);
      final emptySong = getDefaultSongProject();
      songSessions.put(
        projectId,
        emptySong.copyWith(
          config: emptySong.config.copyWith(
            tempo: 137,
            timeSignature: const TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
            scaleRoot: () => 'D',
            scaleName: () => 'minor',
          ),
        ),
      );

      final writer = container.read(songwriterProvider.notifier);
      final song = container.read(songProjectProvider.notifier);
      expect(container.read(songwriterProvider).config.tempo, 137);
      expect(container.read(songProjectProvider).config.tempo, 137);

      container.read(projectConfigSyncProvider);
      await Future<void>.delayed(Duration.zero);

      final writerConfig = container.read(songwriterProvider).config;
      expect(writerConfig.tempo, 120);
      expect(writerConfig.beatsPerBar, 4);
      expect(writerConfig.keyRoot, 0);
      expect(writerConfig.keyScaleName, 'major');
      final songConfig = container.read(songProjectProvider).config;
      expect(songConfig.tempo, 120);
      expect(songConfig.timeSignature.beatsPerMeasure, 4);
      expect(songConfig.scaleRoot, 'C');
      expect(songConfig.scaleName, 'major');
      expect(writer.canUndo, isFalse);
      expect(song.canUndo, isFalse);
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
      final projectId = saveSystem.createProject('Song', initial)!;
      saveSystem.selectProject(projectId);
      container.read(projectConfigSyncProvider);
      await Future<void>.delayed(Duration.zero);

      final writer = container.read(songwriterProvider.notifier);
      final song = container.read(songProjectProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      song.addTrack(SongTrackType.note, name: 'Verse');
      expect(writer.canUndo, isTrue);
      expect(song.canUndo, isTrue);

      saveSystem.updateProjectConfig(projectId, initial);
      await Future<void>.delayed(Duration.zero);
      expect(writer.canUndo, isTrue);
      expect(song.canUndo, isTrue);

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
      expect(container.read(songProjectProvider).config.tempo, 96);
      expect(
        container
            .read(songProjectProvider)
            .config
            .timeSignature
            .beatsPerMeasure,
        3,
      );
      expect(container.read(songProjectProvider).config.scaleRoot, 'D');
      expect(writer.canUndo, isFalse);
      expect(song.canUndo, isFalse);
      expect(writer.undo(), isFalse);
      expect(song.undo(), isFalse);
    },
  );
}
