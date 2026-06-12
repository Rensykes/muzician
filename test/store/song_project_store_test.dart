import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  test('addTrack appends a note track with deterministic order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note, name: 'Lead');
    final state = container.read(songProjectProvider);
    expect(state.tracks.single.id, trackId);
    expect(state.tracks.single.name, 'Lead');
    expect(state.tracks.single.order, 0);
  });

  test('createEmptyNotePatternClip creates a track clip and note pattern', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note, name: 'Lead');
    notifier.createEmptyNotePatternClip(trackId: trackId, startTick: 0);
    final state = container.read(songProjectProvider);
    expect(state.clips, hasLength(1));
    expect(state.notePatterns, hasLength(1));
  });

  test('makeClipPatternUnique clones the pattern for one clip only', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note, name: 'Lead');
    final originalClipId = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
      patternName: 'Shared',
    );
    final duplicateClipId = notifier.duplicateClip(originalClipId);

    final before = container.read(songProjectProvider);
    expect(before.notePatterns, hasLength(1));
    expect(before.clips.map((clip) => clip.patternId).toSet(), hasLength(1));

    notifier.makeClipPatternUnique(duplicateClipId);

    final after = container.read(songProjectProvider);
    expect(after.notePatterns, hasLength(2));
    final originalClip = after.clips.firstWhere(
      (clip) => clip.id == originalClipId,
    );
    final duplicateClip = after.clips.firstWhere(
      (clip) => clip.id == duplicateClipId,
    );
    expect(originalClip.patternId == duplicateClip.patternId, isFalse);
  });

  test('addTrack for drum type creates with correct name', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    notifier.addTrack(SongTrackType.drum);
    final state = container.read(songProjectProvider);
    expect(state.tracks.single.name, 'Drum Track');
    expect(state.tracks.single.type, SongTrackType.drum);
  });

  test('deleteTrack removes track and its clips', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    notifier.createEmptyNotePatternClip(trackId: trackId, startTick: 0);
    expect(container.read(songProjectProvider).clips, hasLength(1));
    notifier.deleteTrack(trackId);
    final state = container.read(songProjectProvider);
    expect(state.tracks, isEmpty);
    expect(state.clips, isEmpty);
    // Pattern should be cleaned up (orphaned)
    expect(state.notePatterns, isEmpty);
  });

  test('moveClip rejects overlap', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    final clip1Id = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
    );
    notifier.createEmptyNotePatternClip(trackId: trackId, startTick: 16);
    // Try to move clip1 to overlap with clip2
    notifier.moveClip(clip1Id, 8);
    // Should be rejected, clip1 stays at 0
    final clip1 = container
        .read(songProjectProvider)
        .clips
        .firstWhere((c) => c.id == clip1Id);
    expect(clip1.startTick, 0);
  });

  test('toggleMute and toggleSolo work', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    notifier.toggleMute(trackId);
    expect(container.read(songProjectProvider).tracks.single.isMuted, true);
    notifier.toggleSolo(trackId);
    expect(container.read(songProjectProvider).tracks.single.isSolo, true);
    notifier.toggleMute(trackId);
    expect(container.read(songProjectProvider).tracks.single.isMuted, false);
  });

  test('setTrackVolume clamps and persists; fromJson defaults to 1.0', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);

    expect(container.read(songProjectProvider).tracks.single.volume, 1.0);

    notifier.setTrackVolume(trackId, 0.5);
    expect(container.read(songProjectProvider).tracks.single.volume, 0.5);

    notifier.setTrackVolume(trackId, 1.4);
    expect(container.read(songProjectProvider).tracks.single.volume, 1.0);

    notifier.setTrackVolume(trackId, -0.2);
    expect(container.read(songProjectProvider).tracks.single.volume, 0.0);

    final legacy = SongTrack.fromJson({
      'id': 't1',
      'name': 'Lead',
      'type': 'note',
      'order': 0,
    });
    expect(legacy.volume, 1.0);

    final roundTrip = SongTrack.fromJson(
      legacy.copyWith(volume: 0.25).toJson(),
    );
    expect(roundTrip.volume, 0.25);
  });

  test('transposeClipPattern shifts all notes; rejects out-of-range', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
    );
    final pattern = container.read(songProjectProvider).notePatterns.single;
    notifier.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(
              id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4),
          NotePatternNote(
              id: 'n2', midiNote: 64, startTick: 4, durationTicks: 4),
        ],
      ),
    );

    expect(notifier.transposeClipPattern(clipId, 12), isTrue);
    var notes = container.read(songProjectProvider).notePatterns.single.notes;
    expect(notes.map((n) => n.midiNote), [72, 76]);

    expect(notifier.transposeClipPattern(clipId, -1), isTrue);
    notes = container.read(songProjectProvider).notePatterns.single.notes;
    expect(notes.map((n) => n.midiNote), [71, 75]);

    // 71 + 60 = 131 > 127 → rejected, unchanged.
    expect(notifier.transposeClipPattern(clipId, 60), isFalse);
    notes = container.read(songProjectProvider).notePatterns.single.notes;
    expect(notes.map((n) => n.midiNote), [71, 75]);
  });

  test('moveClipToTrack moves between same-type tracks only', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final a = notifier.addTrack(SongTrackType.note, name: 'A');
    final b = notifier.addTrack(SongTrackType.note, name: 'B');
    final d = notifier.addTrack(SongTrackType.drum, name: 'D');
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: a,
      startTick: 0,
    );

    expect(notifier.moveClipToTrack(clipId, d), isFalse); // type mismatch
    expect(notifier.moveClipToTrack(clipId, b), isTrue);
    expect(
      container
          .read(songProjectProvider)
          .clips
          .single
          .trackId,
      b,
    );

    // Occupied target slot → rejected.
    notifier.createEmptyNotePatternClip(trackId: a, startTick: 0);
    final blocking = notifier.createEmptyNotePatternClip(
      trackId: b,
      startTick: 0,
    );
    expect(blocking, isNotEmpty);
    final clipOnA = container
        .read(songProjectProvider)
        .clips
        .firstWhere((c) => c.trackId == a);
    expect(notifier.moveClipToTrack(clipOnA.id, b), isFalse);
  });

  test('addClipReference pastes a shared-pattern clip', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final a = notifier.addTrack(SongTrackType.note, name: 'A');
    final b = notifier.addTrack(SongTrackType.note, name: 'B');
    notifier.createEmptyNotePatternClip(trackId: a, startTick: 0);
    final pattern = container.read(songProjectProvider).notePatterns.single;

    final pasted = notifier.addClipReference(
      patternId: pattern.id,
      patternType: SongPatternType.note,
      trackId: b,
      startTick: 16,
    );
    expect(pasted, isNotNull);
    final clips = container.read(songProjectProvider).clips;
    expect(clips, hasLength(2));
    expect(clips.map((c) => c.patternId).toSet(), hasLength(1));

    // Type mismatch → null.
    final d = notifier.addTrack(SongTrackType.drum, name: 'D');
    expect(
      notifier.addClipReference(
        patternId: pattern.id,
        patternType: SongPatternType.note,
        trackId: d,
        startTick: 0,
      ),
      isNull,
    );
  });

  test('moveTrack reorders tracks by delta', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final a = notifier.addTrack(SongTrackType.note, name: 'A');
    final b = notifier.addTrack(SongTrackType.note, name: 'B');
    final c = notifier.addTrack(SongTrackType.note, name: 'C');

    notifier.moveTrack(c, -1);
    List<String> ordered() {
      final tracks = [...container.read(songProjectProvider).tracks]
        ..sort((x, y) => x.order.compareTo(y.order));
      return tracks.map((t) => t.name).toList();
    }

    expect(ordered(), ['A', 'C', 'B']);
    notifier.moveTrack(a, 2);
    expect(ordered(), ['C', 'B', 'A']);
    notifier.moveTrack(b, -5); // clamped to top
    expect(ordered(), ['B', 'C', 'A']);
  });

  test('splitClipAtTick splits a note clip into two unique clips', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 16,
    );
    final pattern = container.read(songProjectProvider).notePatterns.single;
    notifier.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(
              id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4),
          NotePatternNote(
              id: 'n2', midiNote: 64, startTick: 12, durationTicks: 4),
        ],
      ),
    );

    // Split at global tick 24 = local tick 8.
    expect(notifier.splitClipAtTick(clipId, 24), isTrue);
    final state = container.read(songProjectProvider);
    expect(state.clips, hasLength(2));
    final ordered = [...state.clips]
      ..sort((a, b) => a.startTick.compareTo(b.startTick));
    expect(ordered[0].startTick, 16);
    expect(ordered[1].startTick, 24);
    expect(ordered[0].patternId == ordered[1].patternId, isFalse);
    expect(state.notePatterns, hasLength(2));

    // Out-of-range split rejected.
    expect(notifier.splitClipAtTick(ordered[0].id, 16), isFalse);
  });

  test('splitClipAtTick keeps shared siblings on the original pattern', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
    );
    final siblingId = notifier.duplicateClip(clipId);
    final sharedPatternId =
        container.read(songProjectProvider).clips.first.patternId;

    expect(notifier.splitClipAtTick(clipId, 8), isTrue);
    final state = container.read(songProjectProvider);
    final sibling = state.clips.firstWhere((c) => c.id == siblingId);
    expect(sibling.patternId, sharedPatternId,
        reason: 'shared sibling keeps the original pattern');
    expect(state.notePatterns.any((p) => p.id == sharedPatternId), isTrue);
    expect(state.clips, hasLength(3));
  });

  test('setAudioClipTrim adjusts schedulable window', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.audio);
    notifier.addAudioClip(
      trackId: trackId,
      startTick: 0,
      asset: const AudioAsset(
        id: 'a1',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      ),
    );
    final pattern =
        container.read(songProjectProvider).audioPatterns.single;

    notifier.setAudioClipTrim(pattern.id, trimStartMs: 100, trimEndMs: 200);
    final updated =
        container.read(songProjectProvider).audioPatterns.single;
    expect(updated.trimStartMs, 100);
    expect(updated.trimEndMs, 200);

    // Trim wider than the asset is clamped to keep ≥1 ms of audio.
    notifier.setAudioClipTrim(pattern.id, trimStartMs: 900, trimEndMs: 900);
    final clamped =
        container.read(songProjectProvider).audioPatterns.single;
    expect(clamped.trimStartMs + clamped.trimEndMs, lessThan(1000));
  });

  test('deleteClip cleans up orphaned pattern', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
    );
    expect(container.read(songProjectProvider).notePatterns, hasLength(1));
    notifier.deleteClip(clipId);
    expect(container.read(songProjectProvider).notePatterns, isEmpty);
  });

  test('applyNotePattern rejects if resized pattern would overlap', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
      patternName: 'P1',
    );
    notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 16,
      patternName: 'P2',
    );

    final pattern = container.read(songProjectProvider).notePatterns.first;
    // Try to expand pattern to overlap with clip2
    final expanded = pattern.copyWith(lengthTicks: 20);
    final applied = notifier.applyNotePattern(pattern.id, expanded);
    // Should be rejected
    expect(applied, isFalse);
    expect(
      container.read(songProjectProvider).notePatterns.first.lengthTicks,
      16,
    );
  });

  test('solo persists across state changes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    notifier.toggleSolo(trackId);
    expect(container.read(songProjectProvider).tracks.single.isSolo, true);
    // Solo should persist after other mutations
    notifier.setTempo(140);
    expect(container.read(songProjectProvider).tracks.single.isSolo, true);
  });

  test('moveClip allows positions beyond tick 511 within 32-measure limit', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    notifier.setTimeSignature(
      const TimeSignature(beatsPerMeasure: 12, beatUnit: 8),
    );
    final trackId = notifier.addTrack(SongTrackType.note);
    final clipId = notifier.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
    );

    notifier.moveClip(clipId, 700);

    final clip = container
        .read(songProjectProvider)
        .clips
        .firstWhere((c) => c.id == clipId);
    expect(clip.startTick, 700);
  });

  test('createImportedNotePatternClip imports PianoRollSnapshot notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);

    final snapshot = PianoRollSnapshot(
      tempo: 100,
      key: 'C',
      numerator: 4,
      denominator: 4,
      totalMeasures: 1,
      notes: const [
        {'midiNote': 60, 'startTick': 0, 'durationTicks': 4},
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      snapTicks: 1,
      highlightedNotes: const [],
    );

    final clipId = notifier.createImportedNotePatternClip(
      trackId: trackId,
      startTick: 0,
      snapshot: snapshot,
    );

    final state = container.read(songProjectProvider);
    expect(state.clips.single.id, clipId);
    expect(state.notePatterns.single.notes.single.midiNote, 60);
  });

  test('createImportedNotePatternClip rejects overlapping placement', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.note);
    notifier.createEmptyNotePatternClip(trackId: trackId, startTick: 0);

    final snapshot = PianoRollSnapshot(
      tempo: 100,
      key: 'C',
      numerator: 4,
      denominator: 4,
      totalMeasures: 1,
      notes: const [
        {'midiNote': 60, 'startTick': 0, 'durationTicks': 4},
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      snapTicks: 1,
      highlightedNotes: const [],
    );

    expect(
      () => notifier.createImportedNotePatternClip(
        trackId: trackId,
        startTick: 0,
        snapshot: snapshot,
      ),
      throwsStateError,
    );
  });

  group('SongProjectNotifier audio clips', () {
    test('addAudioClip places a clip, pattern, and asset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);

      final trackId = notifier.addTrack(SongTrackType.audio);
      const asset = AudioAsset(
        id: 'asset-1',
        durationMs: 2000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30],
        sourceLabel: 'Recording',
      );

      final clipId = notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: asset,
        clipName: 'Take 1',
      );

      final p = container.read(songProjectProvider);
      expect(p.audioAssets, hasLength(1));
      expect(p.audioPatterns, hasLength(1));
      expect(p.clips, hasLength(1));
      expect(p.clips.first.patternType, SongPatternType.audio);
      expect(p.clips.first.id, clipId);
      expect(p.audioPatterns.first.assetId, 'asset-1');
      expect(p.audioPatterns.first.name, 'Take 1');
    });

    test('removeAudioClip cascades pattern + asset deletion', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);

      final trackId = notifier.addTrack(SongTrackType.audio);
      const asset = AudioAsset(
        id: 'asset-1',
        durationMs: 2000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30],
        sourceLabel: 'Recording',
      );
      final clipId = notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: asset,
      );

      notifier.removeAudioClip(clipId);

      final p = container.read(songProjectProvider);
      expect(p.clips, isEmpty);
      expect(p.audioPatterns, isEmpty);
      expect(p.audioAssets, isEmpty);
    });

    test('deleteTrack on audio track removes its clips + assets', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);
      final trackId = notifier.addTrack(SongTrackType.audio);
      notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: const AudioAsset(
          id: 'a1',
          durationMs: 1000,
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [0],
          sourceLabel: '',
        ),
      );
      notifier.deleteTrack(trackId);
      final p = container.read(songProjectProvider);
      expect(p.tracks, isEmpty);
      expect(p.clips, isEmpty);
      expect(p.audioPatterns, isEmpty);
      expect(p.audioAssets, isEmpty);
    });

    test('loadProject reconciles orphan audio files', () async {
      final tmp = await Directory.systemTemp.createTemp('reconcile_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SongAudioRepository.testWith(rootDirectory: tmp);
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final orphan = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );

      final container = ProviderContainer(
        overrides: [songAudioRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(songProjectProvider.notifier)
          .loadProject(
            const SongProject(
              config: SongProjectConfig(
                tempo: 120,
                timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
                totalMeasures: 4,
              ),
              tracks: [],
              clips: [],
              notePatterns: [],
              drumPatterns: [],
              audioAssets: [],
              audioPatterns: [],
            ),
          );

      final file = await repo.resolvePath(orphan.id, orphan.format);
      expect(file.existsSync(), isFalse);
    });

    test('renameAudioClip updates only the targeted pattern name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);
      final trackId = notifier.addTrack(SongTrackType.audio);
      final clipId = notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: const AudioAsset(
          id: 'a1',
          durationMs: 1000,
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [0],
          sourceLabel: '',
        ),
        clipName: 'First',
      );

      notifier.renameAudioClip(clipId, 'Renamed');

      final p = container.read(songProjectProvider);
      expect(p.audioPatterns.first.name, 'Renamed');
    });
  });
}
