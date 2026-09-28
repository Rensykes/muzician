import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/song_rules.dart' as song_rules;
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('track edit can be undone and redone', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);

    notifier.addTrack(SongTrackType.note, name: 'Verse');
    expect(container.read(songProjectProvider).tracks.single.name, 'Verse');
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).tracks, isEmpty);
    expect(notifier.redo(), isTrue);
    expect(container.read(songProjectProvider).tracks.single.name, 'Verse');
  });

  test('clip and marker edits undo compound model changes in one step', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final noteTrack = notifier.addTrack(SongTrackType.note);
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: noteTrack,
      startTick: 0,
      lengthTicks: 16,
    );
    expect(notifier.undoCount, 2);
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).clips, isEmpty);
    expect(container.read(songProjectProvider).notePatterns, isEmpty);
    expect(notifier.redo(), isTrue);

    notifier.moveClip(clipId, 32);
    expect(notifier.undoCount, 3);
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).clips.single.startTick, 0);
    expect(notifier.redo(), isTrue);

    final duplicateId = notifier.duplicateClip(clipId);
    expect(notifier.undoCount, 4);
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).clips, hasLength(1));
    expect(notifier.redo(), isTrue);
    notifier.makeClipPatternUnique(duplicateId, patternName: 'Unique');
    expect(notifier.undoCount, 5);
    expect(
      container
          .read(songProjectProvider)
          .clips
          .map((clip) => clip.patternId)
          .toSet(),
      hasLength(2),
    );
    expect(notifier.undo(), isTrue);
    expect(
      container
          .read(songProjectProvider)
          .clips
          .map((clip) => clip.patternId)
          .toSet(),
      hasLength(1),
    );

    final markerId = notifier.addMarker(12, 'Verse');
    expect(notifier.undoCount, 5);
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).markers, isEmpty);
    expect(notifier.redo(), isTrue);
    notifier.updateMarker(markerId, label: 'Chorus');
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).markers.single.label, 'Verse');
  });

  test('creating a drum clip and pattern is one undoable edit', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final drumTrack = notifier.addTrack(SongTrackType.drum);
    final beforeClip = notifier.undoCount;
    notifier.createEmptyDrumPatternClip(
      trackId: drumTrack,
      startTick: 0,
      lengthTicks: 16,
    );
    expect(notifier.undoCount, beforeClip + 1);
    expect(notifier.undo(), isTrue);
    expect(container.read(songProjectProvider).clips, isEmpty);
    expect(container.read(songProjectProvider).drumPatterns, isEmpty);
  });

  test('project switch, New Song, and named load clear Song history', () async {
    final root = await Directory.systemTemp.createTemp('song-history-switch-');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final container = ProviderContainer(
      overrides: [
        songAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(rootDirectory: root),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final first = saveSystem.createProject('First', const ProjectConfig())!;
    final second = saveSystem.createProject('Second', const ProjectConfig())!;

    saveSystem.selectProject(first);
    notifier.addTrack(SongTrackType.note, name: 'First track');
    expect(notifier.canUndo, isTrue);

    saveSystem.selectProject(second);
    expect(notifier.canUndo, isFalse);
    expect(notifier.canRedo, isFalse);

    notifier.addTrack(SongTrackType.note, name: 'Second track');
    await notifier.newSong();
    expect(notifier.canUndo, isFalse);
    expect(container.read(songProjectProvider).tracks, isEmpty);

    notifier.addTrack(SongTrackType.note, name: 'Before load');
    await notifier.loadProject(
      song_rules.getDefaultSongProject().copyWith(
        markers: const [SongMarker(id: 'named', tick: 0, label: 'Named')],
      ),
    );
    expect(notifier.canUndo, isFalse);
    expect(container.read(songProjectProvider).markers.single.label, 'Named');
  });

  test('continuous edits grouped at release undo as one snapshot', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);

    notifier.beginHistoryGroup();
    notifier.setTempo(140);
    notifier.setTimeSignature(
      const TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
    );
    notifier.endHistoryGroup();

    expect(notifier.undoCount, 1);
    expect(notifier.undo(), isTrue);
    final restored = container.read(songProjectProvider).config;
    expect(restored.tempo, 120);
    expect(restored.timeSignature.beatsPerMeasure, 4);
  });

  test(
    'clip delete undo restores a shared pattern link and audio reference',
    () async {
      final root = await Directory.systemTemp.createTemp('song-history-test-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final repository = SongAudioRepository.testWith(rootDirectory: root);
      final audioAsset = AudioAsset(
        id: 'audio-history',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: const [],
        sourceLabel: 'Take',
      );
      final file = await repository.resolvePath(audioAsset.id, 'wav');
      await file.writeAsBytes([1, 2, 3]);
      final audioPattern = AudioClipPattern(
        id: 'audio-pattern',
        name: 'Take',
        assetId: audioAsset.id,
      );
      const initial = SongProject(
        config: SongProjectConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: [
          SongTrack(
            id: 'audio-track',
            name: 'Audio',
            type: SongTrackType.audio,
            order: 0,
          ),
        ],
        clips: [
          SongClipInstance(
            id: 'audio-clip',
            trackId: 'audio-track',
            patternId: 'audio-pattern',
            patternType: SongPatternType.audio,
            startTick: 0,
          ),
        ],
        notePatterns: [],
        drumPatterns: [],
        audioPatterns: [],
        audioAssets: [],
      );
      final project = initial.copyWith(
        audioPatterns: [audioPattern],
        audioAssets: [audioAsset],
      );
      final container = ProviderContainer(
        overrides: [songAudioRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);
      await notifier.loadProject(project);

      notifier.deleteClip('audio-clip');
      expect(container.read(songProjectProvider).audioPatterns, isEmpty);
      expect(
        container.read(songProjectProvider).audioAssets.single.id,
        'audio-history',
      );
      expect(file.existsSync(), isTrue);
      expect(notifier.undo(), isTrue);
      final restored = container.read(songProjectProvider);
      expect(restored.clips.single.patternId, 'audio-pattern');
      expect(restored.audioPatterns.single.assetId, 'audio-history');
      expect(restored.audioAssets.single.id, 'audio-history');
      expect(file.existsSync(), isTrue);
    },
  );

  test('Writer import is one undoable Song replacement', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final songNotifier = container.read(songProjectProvider.notifier);
    songNotifier.addTrack(SongTrackType.note, name: 'Before import');
    final before = container.read(songProjectProvider);
    final undoCountBeforeImport = songNotifier.undoCount;
    final writerNotifier = container.read(songwriterProvider.notifier);
    writerNotifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.harmony)
        .id;
    writerNotifier.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 4,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );

    songNotifier.importFromSongwriter();

    expect(songNotifier.undoCount, undoCountBeforeImport + 1);
    expect(container.read(songProjectProvider).tracks, isNotEmpty);
    expect(songNotifier.undo(), isTrue);
    expect(
      container.read(songProjectProvider).tracks.single.name,
      'Before import',
    );
    expect(
      identical(container.read(songProjectProvider).config, before.config),
      isTrue,
    );
  });
}
