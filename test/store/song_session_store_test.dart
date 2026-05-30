import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/song_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSongSessionKey = '@muzician/song_session/v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer makeContainer({Directory? rootDirectory}) {
    final dir =
        rootDirectory ?? Directory.systemTemp.createTempSync('song_session_');
    final container = ProviderContainer(
      overrides: [
        songAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(rootDirectory: dir),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return container;
  }

  test('hydrate restores a previously persisted song project', () async {
    final saved = SongProject(
      config: const SongProjectConfig(
        tempo: 96,
        timeSignature: TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
        totalMeasures: 6,
      ),
      tracks: const [
        SongTrack(id: 't1', name: 'Lead', type: SongTrackType.note, order: 0),
      ],
      clips: const [],
      notePatterns: const [],
      drumPatterns: const [],
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      _kSongSessionKey: jsonEncode(saved.toJson()),
    });

    final container = makeContainer();
    await container.read(songSessionProvider).hydrate();

    final restored = container.read(songProjectProvider);
    expect(restored.config.tempo, 96);
    expect(restored.tracks, hasLength(1));
    expect(restored.tracks.first.name, 'Lead');
  });

  test(
    'debounced persist writes the latest state to SharedPreferences',
    () async {
      final container = makeContainer();
      final session = container.read(songSessionProvider);
      await session.hydrate();

      final notifier = container.read(songProjectProvider.notifier);
      notifier.setTempo(140);
      notifier.addTrack(SongTrackType.audio, name: 'Vocals');

      // Wait past the debounce window.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSongSessionKey);
      expect(raw, isNotNull);
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final reloaded = SongProject.fromJson(json);
      expect(reloaded.config.tempo, 140);
      expect(reloaded.tracks.any((t) => t.name == 'Vocals'), isTrue);
    },
  );

  test(
    'clearAndReset wipes the persisted blob and resets to default',
    () async {
      final saved = SongProject(
        config: const SongProjectConfig(
          tempo: 200,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 8,
        ),
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'Synth',
            type: SongTrackType.note,
            order: 0,
          ),
        ],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kSongSessionKey: jsonEncode(saved.toJson()),
      });

      final container = makeContainer();
      await container.read(songSessionProvider).hydrate();
      expect(container.read(songProjectProvider).tracks, hasLength(1));

      await container.read(songSessionProvider).clearAndReset();

      expect(container.read(songProjectProvider).tracks, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kSongSessionKey), isNull);
    },
  );

  test('hydrate drops a corrupt blob instead of throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _kSongSessionKey: 'not-json',
    });
    final container = makeContainer();
    await container.read(songSessionProvider).hydrate();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_kSongSessionKey), isNull);
    expect(container.read(songProjectProvider).tracks, isEmpty);
  });
}
