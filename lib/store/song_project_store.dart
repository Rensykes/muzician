/// Song Project Riverpod Store
library;

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano_roll.dart';
import '../models/save_system.dart';
import '../models/song_project.dart';
import '../schema/rules/song_import_rules.dart' as import_rules;
import '../schema/rules/song_rules.dart' as rules;

class SongProjectNotifier extends Notifier<SongProject> {
  @override
  SongProject build() => rules.getDefaultSongProject();

  // ── ID Generation ───────────────────────────────────────────────────────────

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999).toString().padLeft(6, '0')}';

  // ── Config Mutations ────────────────────────────────────────────────────────

  void setTempo(int tempo) {
    state = state.copyWith(
      config: state.config.copyWith(tempo: tempo.clamp(20, 300)),
    );
  }

  void setTimeSignature(TimeSignature ts) {
    state = state.copyWith(config: state.config.copyWith(timeSignature: ts));
  }

  void setTotalMeasures(int measures) {
    state = state.copyWith(
      config: state.config.copyWith(totalMeasures: measures.clamp(1, 32)),
    );
  }

  // ── Track Mutations ─────────────────────────────────────────────────────────

  String addTrack(SongTrackType type, {String? name}) {
    final defaultName = switch (type) {
      SongTrackType.note => 'Note Track',
      SongTrackType.drum => 'Drum Track',
      SongTrackType.audio => 'Audio Track',
    };
    final trackId = _id('trk');
    final track = SongTrack(
      id: trackId,
      name: name ?? defaultName,
      type: type,
      order: state.tracks.length,
    );
    state = state.copyWith(tracks: [...state.tracks, track]);
    return trackId;
  }

  void renameTrack(String trackId, String name) {
    final trimmed = name.trim();
    final track = state.tracks.firstWhere((t) => t.id == trackId);
    final fallbackName = switch (track.type) {
      SongTrackType.note => 'Note Track',
      SongTrackType.drum => 'Drum Track',
      SongTrackType.audio => 'Audio Track',
    };
    final effectiveName = trimmed.isEmpty ? fallbackName : trimmed;
    state = state.copyWith(
      tracks: state.tracks
          .map((t) => t.id == trackId ? t.copyWith(name: effectiveName) : t)
          .toList(),
    );
  }

  void toggleMute(String trackId) {
    state = state.copyWith(
      tracks: state.tracks
          .map((t) => t.id == trackId ? t.copyWith(isMuted: !t.isMuted) : t)
          .toList(),
    );
  }

  void toggleSolo(String trackId) {
    state = state.copyWith(
      tracks: state.tracks
          .map((t) => t.id == trackId ? t.copyWith(isSolo: !t.isSolo) : t)
          .toList(),
    );
  }

  void deleteTrack(String trackId) {
    final keptClips = state.clips.where((c) => c.trackId != trackId).toList();

    state = state.copyWith(
      tracks: state.tracks.where((t) => t.id != trackId).toList(),
      clips: keptClips,
    );

    _removeOrphanedPatterns();
  }

  // ── Clip Mutations ──────────────────────────────────────────────────────────

  String createEmptyNotePatternClip({
    required String trackId,
    required int startTick,
    int? lengthTicks,
    String? patternName,
  }) {
    final patternLen =
        lengthTicks ?? rules.songTicksPerMeasure(state.config.timeSignature);
    final patternId = _id('np');
    final pattern = NotePattern(
      id: patternId,
      name: patternName ?? 'Pattern',
      lengthTicks: patternLen,
      notes: const [],
      pitchRangeStart: 21,
      pitchRangeEnd: 108,
      snapTicks: 4,
      highlightedNotes: const [],
    );

    final clipId = _id('sci');
    final clip = SongClipInstance(
      id: clipId,
      trackId: trackId,
      patternId: patternId,
      patternType: SongPatternType.note,
      startTick: startTick,
    );

    state = state.copyWith(
      notePatterns: [...state.notePatterns, pattern],
      clips: [...state.clips, clip],
    );

    state = rules.ensureProjectCoversEndTick(state, startTick + patternLen);

    return clipId;
  }

  String createEmptyDrumPatternClip({
    required String trackId,
    required int startTick,
    int? lengthTicks,
    String? patternName,
  }) {
    final patternLen =
        lengthTicks ?? rules.songTicksPerMeasure(state.config.timeSignature);
    final patternId = _id('dp');
    final pattern = rules.createEmptyDrumPattern(
      id: patternId,
      name: patternName ?? 'Pattern',
      lengthTicks: patternLen,
    );

    final clipId = _id('sci');
    final clip = SongClipInstance(
      id: clipId,
      trackId: trackId,
      patternId: patternId,
      patternType: SongPatternType.drum,
      startTick: startTick,
    );

    state = state.copyWith(
      drumPatterns: [...state.drumPatterns, pattern],
      clips: [...state.clips, clip],
    );

    state = rules.ensureProjectCoversEndTick(state, startTick + patternLen);

    return clipId;
  }

  String createImportedNotePatternClip({
    required String trackId,
    required int startTick,
    required InstrumentSnapshot snapshot,
    String? patternName,
    int? fallbackLengthTicks,
  }) {
    final patternId = _id('note_pattern');
    final pattern = import_rules.notePatternFromSnapshot(
      snapshot,
      patternId: patternId,
      patternName: patternName ?? 'Imported Pattern',
      songMeasureTicks: rules.songTicksPerMeasure(state.config.timeSignature),
      fallbackLengthTicks:
          fallbackLengthTicks ??
          rules.songTicksPerMeasure(state.config.timeSignature),
    );
    final clip = SongClipInstance(
      id: _id('song_clip'),
      trackId: trackId,
      patternId: pattern.id,
      patternType: SongPatternType.note,
      startTick: startTick,
    );
    if (!rules.canPlaceClipOnTrack(
      state,
      clip,
      patternLengthTicks: pattern.lengthTicks,
    )) {
      throw StateError(
        'Imported clip would overlap an existing clip on the track',
      );
    }
    final expanded = rules.ensureProjectCoversEndTick(
      state,
      clip.startTick + pattern.lengthTicks,
    );
    state = expanded.copyWith(
      notePatterns: [...expanded.notePatterns, pattern],
      clips: [...expanded.clips, clip],
    );
    return clip.id;
  }

  void moveClip(String clipId, int newStartTick) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    final patternLen = rules.patternLengthForClip(state, clip);
    if (patternLen == null) return;

    final maxSongTicks =
        rules.songTicksPerMeasure(state.config.timeSignature) * 32;
    final maxStartTick = max(0, maxSongTicks - patternLen);
    final clampedTick = newStartTick.clamp(0, maxStartTick);

    // No-op if the tick hasn't changed
    if (clampedTick == clip.startTick) return;

    final candidate = clip.copyWith(startTick: clampedTick);

    if (!rules.canPlaceClipOnTrack(
      state,
      candidate,
      patternLengthTicks: patternLen,
      excludingClipId: clipId,
    )) {
      return; // overlap rejected
    }

    state = state.copyWith(
      clips: state.clips.map((c) => c.id == clipId ? candidate : c).toList(),
    );

    state = rules.ensureProjectCoversEndTick(state, clampedTick + patternLen);
  }

  String duplicateClip(String clipId) {
    final source = state.clips.firstWhere((c) => c.id == clipId);
    final patternLen = rules.patternLengthForClip(state, source);
    if (patternLen == null) {
      // Fallback: place at 0
      final newClip = SongClipInstance(
        id: _id('sci'),
        trackId: source.trackId,
        patternId: source.patternId,
        patternType: source.patternType,
        startTick: 0,
      );
      state = state.copyWith(clips: [...state.clips, newClip]);
      return newClip.id;
    }

    final startTick = rules.firstAvailableDuplicateStartTick(
      state,
      source,
      patternLengthTicks: patternLen,
    );

    final newClip = SongClipInstance(
      id: _id('sci'),
      trackId: source.trackId,
      patternId: source.patternId,
      patternType: source.patternType,
      startTick: startTick,
    );

    state = state.copyWith(clips: [...state.clips, newClip]);
    state = rules.ensureProjectCoversEndTick(state, startTick + patternLen);

    return newClip.id;
  }

  void deleteClip(String clipId) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);

    state = state.copyWith(
      clips: state.clips.where((c) => c.id != clipId).toList(),
    );

    // Remove orphaned pattern
    final stillReferenced = state.clips.any(
      (c) => c.patternId == clip.patternId,
    );
    if (!stillReferenced) {
      state = switch (clip.patternType) {
        SongPatternType.note => state.copyWith(
          notePatterns: state.notePatterns
              .where((p) => p.id != clip.patternId)
              .toList(),
        ),
        SongPatternType.drum => state.copyWith(
          drumPatterns: state.drumPatterns
              .where((p) => p.id != clip.patternId)
              .toList(),
        ),
        SongPatternType.audio => state.copyWith(
          audioPatterns: state.audioPatterns
              .where((p) => p.id != clip.patternId)
              .toList(),
        ),
      };
    }
  }

  void makeClipPatternUnique(String clipId, {String? patternName}) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    final newPatternId = _id(
      clip.patternType == SongPatternType.note ? 'np' : 'dp',
    );
    final newName = patternName ?? 'Pattern';

    if (clip.patternType == SongPatternType.note) {
      final result = rules.cloneNotePatternForClip(
        state,
        clipId: clipId,
        newPatternId: newPatternId,
        newPatternName: newName,
      );
      state = state.copyWith(
        clips: state.clips
            .map((c) => c.id == clipId ? result.updatedClip : c)
            .toList(),
        notePatterns: [...state.notePatterns, result.clonedPattern],
      );
    } else {
      final result = rules.cloneDrumPatternForClip(
        state,
        clipId: clipId,
        newPatternId: newPatternId,
        newPatternName: newName,
      );
      state = state.copyWith(
        clips: state.clips
            .map((c) => c.id == clipId ? result.updatedClip : c)
            .toList(),
        drumPatterns: [...state.drumPatterns, result.clonedPattern],
      );
    }
  }

  // ── Pattern Mutations ───────────────────────────────────────────────────────

  bool applyNotePattern(String patternId, NotePattern nextPattern) {
    if (!rules.canApplyPatternLength(
      state,
      patternId,
      nextPattern.lengthTicks,
    )) {
      return false;
    }

    state = state.copyWith(
      notePatterns: state.notePatterns
          .map((p) => p.id == patternId ? nextPattern : p)
          .toList(),
    );
    return true;
  }

  bool applyDrumPattern(String patternId, DrumPattern nextPattern) {
    if (!rules.canApplyPatternLength(
      state,
      patternId,
      nextPattern.lengthTicks,
    )) {
      return false;
    }

    state = state.copyWith(
      drumPatterns: state.drumPatterns
          .map((p) => p.id == patternId ? nextPattern : p)
          .toList(),
    );
    return true;
  }

  void toggleDrumStep({
    required String patternId,
    required DrumLaneId laneId,
    required int tick,
  }) {
    state = state.copyWith(
      drumPatterns: [
        for (final pattern in state.drumPatterns)
          if (pattern.id == patternId)
            pattern.copyWith(
              lanes: [
                for (final lane in pattern.lanes)
                  if (lane.laneId == laneId)
                    () {
                      final activeTicks = lane.activeTicks.toList();
                      if (activeTicks.contains(tick)) {
                        activeTicks.remove(tick);
                      } else {
                        activeTicks.add(tick);
                        activeTicks.sort();
                      }
                      return lane.copyWith(activeTicks: activeTicks);
                    }()
                  else
                    lane,
              ],
            )
          else
            pattern,
      ],
    );
  }

  // ── Project Load ────────────────────────────────────────────────────────────

  void loadProject(SongProject project) {
    state = project;
  }

  // ── Orphan Cleanup ──────────────────────────────────────────────────────────

  void _removeOrphanedPatterns() {
    final activeNotePatternIds = state.clips
        .where((c) => c.patternType == SongPatternType.note)
        .map((c) => c.patternId)
        .toSet();
    final activeDrumPatternIds = state.clips
        .where((c) => c.patternType == SongPatternType.drum)
        .map((c) => c.patternId)
        .toSet();

    state = state.copyWith(
      notePatterns: state.notePatterns
          .where((p) => activeNotePatternIds.contains(p.id))
          .toList(),
      drumPatterns: state.drumPatterns
          .where((p) => activeDrumPatternIds.contains(p.id))
          .toList(),
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final songProjectProvider = NotifierProvider<SongProjectNotifier, SongProject>(
  SongProjectNotifier.new,
);

final songSelectedTrackIdProvider = StateProvider<String?>((_) => null);

final songSelectedClipIdProvider = StateProvider<String?>((_) => null);
