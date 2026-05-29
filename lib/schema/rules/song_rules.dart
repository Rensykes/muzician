/// Song Project Pure Arrangement Rules
/// Timeline math, overlap detection, pattern cloning, and project expansion.
library;

import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'song_audio_rules.dart' show audioClipLengthTicks;

// ── Defaults ──────────────────────────────────────────────────────────────────

SongProject getDefaultSongProject() => const SongProject(
  config: SongProjectConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 4,
  ),
  tracks: [],
  clips: [],
  notePatterns: [],
  drumPatterns: [],
);

// ── Tick math ─────────────────────────────────────────────────────────────────

int songTicksPerMeasure(TimeSignature ts) {
  final beatTicks = ts.beatUnit == 8 ? 2 : 4;
  return ts.beatsPerMeasure * beatTicks;
}

int songTotalTicks(SongProjectConfig config) {
  return songTicksPerMeasure(config.timeSignature) * config.totalMeasures;
}

// ── Pattern lookup ────────────────────────────────────────────────────────────

int? patternLengthForClip(SongProject project, SongClipInstance clip) {
  switch (clip.patternType) {
    case SongPatternType.note:
      return project.notePatterns
          .where((p) => p.id == clip.patternId)
          .firstOrNull
          ?.lengthTicks;
    case SongPatternType.drum:
      return project.drumPatterns
          .where((p) => p.id == clip.patternId)
          .firstOrNull
          ?.lengthTicks;
    case SongPatternType.audio:
      final pattern = project.audioPatterns
          .where((p) => p.id == clip.patternId)
          .firstOrNull;
      if (pattern == null) return null;
      final asset = project.audioAssets
          .where((a) => a.id == pattern.assetId)
          .firstOrNull;
      if (asset == null) return null;
      return audioClipLengthTicks(asset, project.config);
  }
}

// ── Overlap detection ─────────────────────────────────────────────────────────

bool canPlaceClipOnTrack(
  SongProject project,
  SongClipInstance candidate, {
  required int patternLengthTicks,
  String? excludingClipId,
}) {
  final candidateEnd = candidate.startTick + patternLengthTicks;

  final siblings = project.clips.where(
    (c) =>
        c.trackId == candidate.trackId &&
        c.id != excludingClipId &&
        c.id != candidate.id,
  );

  for (final sibling in siblings) {
    final siblingLength = patternLengthForClip(project, sibling);
    if (siblingLength == null) continue;
    final siblingEnd = sibling.startTick + siblingLength;

    if (candidate.startTick < siblingEnd && sibling.startTick < candidateEnd) {
      return false;
    }
  }

  return true;
}

// ── Duplicate placement ───────────────────────────────────────────────────────

int firstAvailableDuplicateStartTick(
  SongProject project,
  SongClipInstance source, {
  required int patternLengthTicks,
}) {
  var tick = source.startTick + patternLengthTicks;
  final total = songTotalTicks(project.config);

  while (tick + patternLengthTicks <= total) {
    final candidate = SongClipInstance(
      id: '',
      trackId: source.trackId,
      patternId: source.patternId,
      patternType: source.patternType,
      startTick: tick,
    );
    if (canPlaceClipOnTrack(
      project,
      candidate,
      patternLengthTicks: patternLengthTicks,
    )) {
      return tick;
    }
    tick += patternLengthTicks;
  }

  return tick; // fallback: first tick after source, may need project expansion
}

// ── Project expansion ─────────────────────────────────────────────────────────

SongProject ensureProjectCoversEndTick(
  SongProject project,
  int endTickExclusive,
) {
  final currentTotal = songTotalTicks(project.config);
  if (endTickExclusive <= currentTotal) return project;

  final measureTicks = songTicksPerMeasure(project.config.timeSignature);
  final requiredMeasures =
      ((endTickExclusive + measureTicks - 1) ~/ measureTicks).clamp(1, 32);

  return project.copyWith(
    config: project.config.copyWith(totalMeasures: requiredMeasures),
  );
}

// ── Pattern cloning ───────────────────────────────────────────────────────────

({SongClipInstance updatedClip, NotePattern clonedPattern})
cloneNotePatternForClip(
  SongProject project, {
  required String clipId,
  required String newPatternId,
  required String newPatternName,
}) {
  final clip = project.clips.firstWhere((c) => c.id == clipId);
  final original = project.notePatterns.firstWhere(
    (p) => p.id == clip.patternId,
  );

  final clonedNotes = original.notes
      .map(
        (n) => NotePatternNote(
          id: '${newPatternId}_${n.id}',
          midiNote: n.midiNote,
          startTick: n.startTick,
          durationTicks: n.durationTicks,
        ),
      )
      .toList();

  final clonedPattern = NotePattern(
    id: newPatternId,
    name: newPatternName,
    lengthTicks: original.lengthTicks,
    notes: clonedNotes,
    pitchRangeStart: original.pitchRangeStart,
    pitchRangeEnd: original.pitchRangeEnd,
    snapTicks: original.snapTicks,
    highlightedNotes: List<String>.from(original.highlightedNotes),
  );

  final updatedClip = clip.copyWith(patternId: newPatternId);

  return (updatedClip: updatedClip, clonedPattern: clonedPattern);
}

({SongClipInstance updatedClip, DrumPattern clonedPattern})
cloneDrumPatternForClip(
  SongProject project, {
  required String clipId,
  required String newPatternId,
  required String newPatternName,
}) {
  final clip = project.clips.firstWhere((c) => c.id == clipId);
  final original = project.drumPatterns.firstWhere(
    (p) => p.id == clip.patternId,
  );

  final clonedLanes = original.lanes
      .map(
        (l) => DrumLaneSequence(
          laneId: l.laneId,
          activeTicks: List<int>.from(l.activeTicks),
        ),
      )
      .toList();

  final clonedPattern = DrumPattern(
    id: newPatternId,
    name: newPatternName,
    lengthTicks: original.lengthTicks,
    lanes: clonedLanes,
  );

  final updatedClip = clip.copyWith(patternId: newPatternId);

  return (updatedClip: updatedClip, clonedPattern: clonedPattern);
}

// ── Empty drum pattern factory ────────────────────────────────────────────────

DrumPattern createEmptyDrumPattern({
  required String id,
  required String name,
  required int lengthTicks,
}) {
  final lanes = DrumLaneId.values
      .map((laneId) => DrumLaneSequence(laneId: laneId, activeTicks: const []))
      .toList();

  return DrumPattern(
    id: id,
    name: name,
    lengthTicks: lengthTicks,
    lanes: lanes,
  );
}

// ── Pattern length validation ─────────────────────────────────────────────────

bool canApplyPatternLength(
  SongProject project,
  String patternId,
  int nextLengthTicks,
) {
  final clipsUsingPattern = project.clips.where(
    (c) => c.patternId == patternId,
  );

  for (final clip in clipsUsingPattern) {
    if (!canPlaceClipOnTrack(
      project,
      clip,
      patternLengthTicks: nextLengthTicks,
      excludingClipId: clip.id,
    )) {
      return false;
    }
  }

  return true;
}
