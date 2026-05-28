import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';

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
}
