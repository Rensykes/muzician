import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/profile_writer_playback.dart'
    show
        ProfileViewMode,
        WriterPlaybackProfileApp,
        buildWriterPlaybackProfileManifest,
        buildWriterPlaybackProfileProviderOverrides,
        verifyWriterPlaybackProfileFixtureVoices,
        verifyWriterPlaybackProfileFixtures;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers.global/events'),
  ];
  setUp(() {
    for (final channel in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
  });
  tearDown(() {
    for (final channel in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test('isolated Writer fixtures flatten to their expected note counts', () {
    expect(verifyWriterPlaybackProfileFixtures(), {
      'plain_harmony': 32,
      'piano_harmony': 32,
      'six_note_strum': 144,
      'strum_metronome': 816,
      'drums_metronome': 160,
      'strum_drums': 976,
      'strum_drums_metronome': 976,
      'melody': 64,
      'recorded_clip': 4,
    });
  });

  test('a strum stroke is one voice however many strings it carries', () {
    expect(verifyWriterPlaybackProfileFixtureVoices(), {
      'plain_harmony': 32,
      'piano_harmony': 32,
      // 8 bars: 16 strokes replace 96 string notes.
      'six_note_strum': 64,
      // 8 bars x 16 strokes replace 768 string notes.
      'strum_metronome': 176,
      'drums_metronome': 160,
      'strum_drums': 336,
      'strum_drums_metronome': 336,
      'melody': 64,
      'recorded_clip': 4,
    });
  });

  test('load scenarios schedule dense strum, drum, and metronome settings', () {
    final strumDrums = buildWriterPlaybackProfileManifest(
      scenario: 'strum_drums_metronome',
      tempo: 160,
    );
    expect(strumDrums['bars'], 8);
    expect(strumDrums['metronome_enabled'], isTrue);
    expect(strumDrums['expected_drum_hit_count'], 160);
    // Per bar: one harmony stab + 16 strokes + 16 hats + 2 kicks + 2 snares.
    expect(strumDrums['expected_event_count'], 8 * 16);
    expect(strumDrums['expected_note_count'], 8 * (6 + 96));
    expect(strumDrums['expected_stroke_count'], 8 * 16);
    expect(strumDrums['expected_string_note_count'], 8 * 96);
    expect(strumDrums['expected_voice_count'], 8 * (6 + 16));

    final drums = buildWriterPlaybackProfileManifest(
      scenario: 'drums_metronome',
    );
    expect(drums['metronome_enabled'], isTrue);
    expect(drums['expected_voice_count'], 0);
    expect(drums['expected_drum_hit_count'], 160);

    final strum = buildWriterPlaybackProfileManifest(
      scenario: 'strum_metronome',
    );
    expect(strum['metronome_enabled'], isTrue);
    expect(strum['expected_drum_hit_count'], 0);

    final noClick = buildWriterPlaybackProfileManifest(scenario: 'strum_drums');
    expect(noClick['metronome_enabled'], isFalse);
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
    // 30 bars x 2 six-string strokes: 360 strings sound as 60 voices.
    expect(manifest['expected_note_count'], 540);
    expect(manifest['expected_stroke_count'], 60);
    expect(manifest['expected_string_note_count'], 360);
    expect(manifest['expected_voice_count'], 540 - 360 + 60);
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
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildWriterPlaybackProfileProviderOverrides(
            repository: repository,
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
      switch (view) {
        case ProfileViewMode.writer:
          expect(find.text('Writer'), findsOneWidget);
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
}
