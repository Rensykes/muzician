import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/profile_writer_playback.dart'
    show
        ProfileViewMode,
        WriterPlaybackProfileApp,
        buildSongPlaybackProfileManifest,
        buildWriterPlaybackProfileManifest,
        buildWriterPlaybackProfileProviderOverrides,
        verifyWriterPlaybackProfileFixtures;
import 'package:muzician/models/song_project.dart' show SongPatternType;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  test('isolated Writer fixtures flatten to their expected voice counts', () {
    expect(verifyWriterPlaybackProfileFixtures(), {
      'plain_harmony': 32,
      'piano_harmony': 32,
      'six_note_strum': 144,
      'melody': 64,
      'recorded_clip': 4,
    });
  });

  test('60-second schedule manifest records exact score and voice counts', () {
    final manifest = buildWriterPlaybackProfileManifest(
      scenario: 'plain_harmony',
      tempo: 120,
      durationSeconds: 60,
      runTag: 'unit-test-run',
    );

    expect(manifest['run_tag'], 'unit-test-run');
    expect(manifest['tempo_bpm'], 120);
    expect(manifest['bars'], 30);
    expect(manifest['score_tick_count'], 480);
    expect(manifest['score_duration_us'], 60000000);
    expect(manifest['expected_event_count'], 30);
    expect(manifest['expected_voice_count'], 120);
    final voices = manifest['scheduled_voices']! as List<Map<String, Object?>>;
    expect(voices, hasLength(120));
    expect(voices.first['midi'], isA<int>());
    expect(voices.first['duration_us'], 700000);
    expect(voices.first['onset_offset_us'], 0);
  });

  test('six-note strum manifest preserves per-note offsets and overlap', () {
    final manifest = buildWriterPlaybackProfileManifest(
      scenario: 'six_note_strum',
      tempo: 120,
      durationSeconds: 60,
    );

    final voices = manifest['scheduled_voices']! as List<Map<String, Object?>>;
    final offsets = manifest['onset_offset_counts']! as Map<String, int>;
    expect(voices, hasLength(540));
    expect(offsets.keys, contains('0'));
    expect(offsets.length, greaterThan(1));
    expect(offsets.values.fold<int>(0, (sum, count) => sum + count), 540);
    expect(manifest['expected_max_note_overlap'], greaterThanOrEqualTo(6));
  });

  test(
    'Song comparator mirrors Writer MIDI ticks, offsets, and voice count',
    () {
      final manifest = buildSongPlaybackProfileManifest(
        scenario: 'plain_harmony',
        tempo: 120,
        durationSeconds: 60,
      );

      expect(manifest['midi_tick_offset_count_match'], isTrue);
      expect(manifest['writer_midi_voice_count'], 120);
      expect(manifest['song_midi_voice_count'], 120);
      expect(manifest['writer_event_count'], 30);
      expect(manifest['song_event_count'], 30);
      expect(manifest['song_track_count'], 1);
      expect(manifest['song_note_clip_count'], 30);
      expect(manifest['writer_audio_transfer_note'], contains('excluded'));
      final writer = manifest['writer_midi_schedule']! as List;
      final song = manifest['song_midi_schedule']! as List;
      expect(
        writer
            .map(
              (voice) => [
                (voice as Map)['score_tick'],
                voice['midi'],
                voice['onset_offset_us'],
              ],
            )
            .toList(),
        song
            .map(
              (voice) => [
                (voice as Map)['score_tick'],
                voice['midi'],
                voice['onset_offset_us'],
              ],
            )
            .toList(),
      );
      expect(manifest['duration_comparison_note'], contains('700ms'));
    },
  );

  test('recorded clip comparator retains the isolated Song audio fixture', () {
    final manifest = buildSongPlaybackProfileManifest(
      scenario: 'recorded_clip',
      tempo: 120,
      durationSeconds: 60,
    );

    expect(manifest['song_audio_asset_count'], 1);
    expect(manifest['song_audio_clip_count'], 1);
    expect(manifest['song_audio_clip_sink'], 'AudioPlayersClipSink');
    expect(
      manifest['song_audio_fixture_storage'],
      contains('isolated temporary song_audio repository'),
    );
  });

  for (final view in ProfileViewMode.values.where(
    (view) => view != ProfileViewMode.minimal,
  )) {
    testWidgets('isolated ${view.name} profile view mounts production UI', (
      tester,
    ) async {
      final runDirectory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('muzician-profile-view-'),
      ))!;
      final repository = SongAudioRepository.testWith(
        rootDirectory: runDirectory,
        subdir: 'songwriter_audio',
      );
      final songRepository = SongAudioRepository.testWith(
        rootDirectory: runDirectory,
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildWriterPlaybackProfileProviderOverrides(
            repository: repository,
            songRepository: songRepository,
          ),
          child: WriterPlaybackProfileApp(
            runDirectory: runDirectory,
            viewMode: view,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(runDirectory.listSync(), isEmpty);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(
        container.read(songwriterProvider).name,
        'Isolated playback profile fixture',
      );
      expect(
        container.read(saveSystemProvider).selectedProjectId,
        'writer_profile_qa_project',
      );
      expect(container.read(settingsProvider).metronomeEnabled, isFalse);
      expect(container.read(songProjectProvider).config.tempo, 120);
      if (view == ProfileViewMode.song) {
        expect(
          container.read(songAudioRepositoryProvider),
          same(songRepository),
        );
      }
      switch (view) {
        case ProfileViewMode.writer:
          expect(find.text('Writer'), findsOneWidget);
        case ProfileViewMode.song:
          expect(find.text('Song'), findsOneWidget);
        case ProfileViewMode.fretboard:
          expect(find.text('Fretboard'), findsOneWidget);
        case ProfileViewMode.piano:
          expect(find.text('Piano'), findsOneWidget);
        case ProfileViewMode.minimal:
          fail('The minimal view is covered by the existing harness tests.');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() => runDirectory.delete(recursive: true));
    });
  }

  testWidgets('recorded clip Song fixture uses its isolated real-sink source', (
    tester,
  ) async {
    final runDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('muzician-profile-song-clip-'),
    ))!;
    final writerRepository = SongAudioRepository.testWith(
      rootDirectory: runDirectory,
      subdir: 'songwriter_audio',
    );
    final songRepository = SongAudioRepository.testWith(
      rootDirectory: runDirectory,
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: buildWriterPlaybackProfileProviderOverrides(
          repository: writerRepository,
          songRepository: songRepository,
          scenario: 'recorded_clip',
        ),
        child: WriterPlaybackProfileApp(
          runDirectory: runDirectory,
          viewMode: ProfileViewMode.song,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final song = container.read(songProjectProvider);
    final writer = container.read(songwriterProvider);
    expect(song.audioAssets.single.id, _qaAssetIdForTest);
    expect(writer.audioAssets.single.id, song.audioAssets.single.id);
    expect(song.audioPatterns.single.assetId, song.audioAssets.single.id);
    expect(
      song.clips.where((clip) => clip.patternType == SongPatternType.audio),
      hasLength(1),
    );
    expect(container.read(songAudioRepositoryProvider), same(songRepository));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
    await tester.runAsync(() => runDirectory.delete(recursive: true));
  });
}

const _qaAssetIdForTest = 'writer_profile_controlled_clip';
