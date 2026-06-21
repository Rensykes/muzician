/// Song Project Riverpod Store
library;

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano_roll.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../models/song_project.dart';
import '../schema/rules/song_from_writer_rules.dart';
import '../schema/rules/song_audio_rules.dart'
    show audioClipLengthTicks, audioTickToMs;
import '../schema/rules/song_import_rules.dart' as import_rules;
import '../schema/rules/song_rules.dart' as rules;
import '../schema/rules/song_split_rules.dart' as split_rules;
import '../utils/note_utils.dart';
import 'save_system_store.dart';
import 'song_audio_repository.dart';
import 'song_sessions_store.dart';
import 'songwriter_store.dart';

class SongProjectNotifier extends Notifier<SongProject> {
  bool _hydrating = false;

  @override
  SongProject build() {
    // React to project selection changes.
    ref.listen<String?>(
      saveSystemProvider.select((s) => s.selectedProjectId),
      (prev, next) {
        // Persist outgoing immediately.
        if (prev != null && prev != next) {
          ref.read(songSessionsProvider.notifier).put(prev, state);
        }
        if (next == null) {
          _hydrating = true;
          state = rules.getDefaultSongProject();
          _hydrating = false;
          return;
        }
        _hydrating = true;
        final session = ref.read(songSessionsProvider.notifier).get(next);
        if (session != null) {
          state = session;
        } else {
          state = _defaultFor(next);
        }
        _hydrating = false;
      },
    );

    return rules.getDefaultSongProject();
  }

  @override
  set state(SongProject value) {
    super.state = value;
    _schedulePersist(value);
  }

  SongProject _defaultFor(String projectId) {
    final folder = ref.read(saveSystemProvider).folders.firstWhere((f) => f.id == projectId);
    final cfg = folder.projectConfig ?? const ProjectConfig();
    final base = rules.getDefaultSongProject();
    return base.copyWith(
      config: base.config.copyWith(
        tempo: cfg.tempo,
        timeSignature: TimeSignature(beatsPerMeasure: cfg.beatsPerBar, beatUnit: cfg.beatUnit),
        scaleRoot: () => cfg.keyRootPc == null ? null : chromaticNotes[cfg.keyRootPc!],
        scaleName: () => cfg.keyScaleName,
      ),
    );
  }

  void _schedulePersist(SongProject project) {
    if (_hydrating) return;
    final id = ref.read(saveSystemProvider).selectedProjectId;
    if (id != null) {
      ref.read(songSessionsProvider.notifier).put(id, project);
    }
  }

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

  /// Set or clear the song-level scale.  Passing both [root] and [scaleName]
  /// applies the scale (and propagates it into every note pattern as
  /// `highlightedNotes`); passing nulls clears it and leaves each pattern's
  /// own highlight fallback intact.
  void setScale({String? root, String? scaleName}) {
    state = state.copyWith(
      config: state.config.copyWith(
        scaleRoot: () => root,
        scaleName: () => scaleName,
      ),
    );
  }

  /// Drop every note in every note pattern whose pitch class is in
  /// [pitchClasses].  Used when the user applies a song-level scale that
  /// conflicts with notes already placed in patterns.
  void removeNotesByPitchClassAcrossPatterns(List<String> pitchClasses) {
    if (pitchClasses.isEmpty) return;
    final unwanted = pitchClasses.toSet();
    final pcOf = _pitchClassOfMidi;
    state = state.copyWith(
      notePatterns: state.notePatterns
          .map(
            (p) => p.copyWith(
              notes: p.notes
                  .where((n) => !unwanted.contains(pcOf(n.midiNote)))
                  .toList(),
            ),
          )
          .toList(),
    );
  }

  static const _pitchClasses = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static String _pitchClassOfMidi(int midi) => _pitchClasses[midi % 12];

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

  void setTrackVolume(String trackId, double volume) {
    final v = volume.clamp(0.0, 1.0);
    state = state.copyWith(
      tracks: state.tracks
          .map((t) => t.id == trackId ? t.copyWith(volume: v) : t)
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
    final removedClips = state.clips
        .where((c) => c.trackId == trackId)
        .toList();
    final keptClips = state.clips.where((c) => c.trackId != trackId).toList();
    final removedAudioPatternIds = removedClips
        .where((c) => c.patternType == SongPatternType.audio)
        .map((c) => c.patternId)
        .toSet();
    final removedAudioAssetIds = state.audioPatterns
        .where((p) => removedAudioPatternIds.contains(p.id))
        .map((p) => p.assetId)
        .toSet();

    state = state.copyWith(
      tracks: state.tracks.where((t) => t.id != trackId).toList(),
      clips: keptClips,
      audioPatterns: state.audioPatterns
          .where((p) => !removedAudioPatternIds.contains(p.id))
          .toList(),
      audioAssets: state.audioAssets
          .where((a) => !removedAudioAssetIds.contains(a.id))
          .toList(),
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

  /// Moves [clipId] to [targetTrackId] keeping its start tick.
  ///
  /// Returns false (no change) when the target track doesn't exist, has a
  /// different type, or the slot is occupied.
  bool moveClipToTrack(String clipId, String targetTrackId) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    if (clip.trackId == targetTrackId) return true;
    final sourceTrack = state.tracks.firstWhere((t) => t.id == clip.trackId);
    final targetTrack = state.tracks
        .where((t) => t.id == targetTrackId)
        .firstOrNull;
    if (targetTrack == null || targetTrack.type != sourceTrack.type) {
      return false;
    }
    final patternLen = rules.patternLengthForClip(state, clip);
    if (patternLen == null) return false;
    final candidate = clip.copyWith(trackId: targetTrackId);
    if (!rules.canPlaceClipOnTrack(
      state,
      candidate,
      patternLengthTicks: patternLen,
      excludingClipId: clipId,
    )) {
      return false;
    }
    state = state.copyWith(
      clips: state.clips.map((c) => c.id == clipId ? candidate : c).toList(),
    );
    return true;
  }

  /// Transposes every note of the clip's pattern by [semitones].
  ///
  /// Shared patterns transpose all their clip instances (same semantics as
  /// pattern editing). Rejected when any note would leave midi 0..127.
  bool transposeClipPattern(String clipId, int semitones) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    if (clip.patternType != SongPatternType.note) return false;
    final pattern = state.notePatterns
        .where((p) => p.id == clip.patternId)
        .firstOrNull;
    if (pattern == null || pattern.notes.isEmpty) return false;
    for (final note in pattern.notes) {
      final next = note.midiNote + semitones;
      if (next < 0 || next > 127) return false;
    }
    final next = pattern.copyWith(
      notes: [
        for (final note in pattern.notes)
          note.copyWith(midiNote: note.midiNote + semitones),
      ],
    );
    state = state.copyWith(
      notePatterns: state.notePatterns
          .map((p) => p.id == pattern.id ? next : p)
          .toList(),
    );
    return true;
  }

  /// Splits the clip at global [tick] into two clips with **unique** sliced
  /// patterns (Make-Unique semantics — shared siblings keep the original
  /// pattern). Audio clips split via trim windows on two patterns sharing
  /// the asset. Returns false when [tick] is not strictly inside the clip.
  bool splitClipAtTick(String clipId, int tick) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    final patternLen = rules.patternLengthForClip(state, clip);
    if (patternLen == null) return false;
    final local = tick - clip.startTick;
    if (local <= 0 || local >= patternLen) return false;

    final leftClip = clip.copyWith(patternId: _id('np'));
    final rightClip = SongClipInstance(
      id: _id('sci'),
      trackId: clip.trackId,
      patternId: _id('np'),
      patternType: clip.patternType,
      startTick: tick,
    );

    switch (clip.patternType) {
      case SongPatternType.note:
        final pattern = state.notePatterns.firstWhere(
          (p) => p.id == clip.patternId,
        );
        final parts = split_rules.splitNotePattern(
          pattern,
          local,
          leftId: leftClip.patternId,
          rightId: rightClip.patternId,
        );
        if (parts == null) return false;
        state = state.copyWith(
          notePatterns: [...state.notePatterns, parts.left, parts.right],
        );
      case SongPatternType.drum:
        final pattern = state.drumPatterns.firstWhere(
          (p) => p.id == clip.patternId,
        );
        final parts = split_rules.splitDrumPattern(
          pattern,
          local,
          leftId: leftClip.patternId,
          rightId: rightClip.patternId,
        );
        if (parts == null) return false;
        state = state.copyWith(
          drumPatterns: [...state.drumPatterns, parts.left, parts.right],
        );
      case SongPatternType.audio:
        final pattern = state.audioPatterns.firstWhere(
          (p) => p.id == clip.patternId,
        );
        final asset = state.audioAssets
            .where((a) => a.id == pattern.assetId)
            .firstOrNull;
        if (asset == null) return false;
        final cutMs = audioTickToMs(local, state.config);
        final playable =
            asset.durationMs - pattern.trimStartMs - pattern.trimEndMs;
        if (cutMs <= 0 || cutMs >= playable) return false;
        state = state.copyWith(
          audioPatterns: [
            ...state.audioPatterns,
            pattern.copyWith(
              id: leftClip.patternId,
              name: '${pattern.name} ◂',
              trimEndMs: pattern.trimEndMs + (playable - cutMs),
            ),
            pattern.copyWith(
              id: rightClip.patternId,
              name: '${pattern.name} ▸',
              trimStartMs: pattern.trimStartMs + cutMs,
            ),
          ],
        );
    }

    // Swap in the two halves, then drop the original pattern if orphaned.
    final originalPatternId = clip.patternId;
    state = state.copyWith(
      clips: [
        for (final c in state.clips)
          if (c.id == clipId) leftClip else c,
        rightClip,
      ],
    );
    final stillReferenced = state.clips.any(
      (c) => c.patternId == originalPatternId,
    );
    if (!stillReferenced) {
      state = switch (clip.patternType) {
        SongPatternType.note => state.copyWith(
          notePatterns: state.notePatterns
              .where((p) => p.id != originalPatternId)
              .toList(),
        ),
        SongPatternType.drum => state.copyWith(
          drumPatterns: state.drumPatterns
              .where((p) => p.id != originalPatternId)
              .toList(),
        ),
        SongPatternType.audio => state.copyWith(
          audioPatterns: state.audioPatterns
              .where((p) => p.id != originalPatternId)
              .toList(),
        ),
      };
    }
    return true;
  }

  /// Sets an audio clip pattern's head/tail trim, clamped so at least 1 ms
  /// of audio remains.
  void setAudioClipTrim(
    String patternId, {
    required int trimStartMs,
    required int trimEndMs,
  }) {
    final pattern = state.audioPatterns
        .where((p) => p.id == patternId)
        .firstOrNull;
    if (pattern == null) return;
    final asset = state.audioAssets
        .where((a) => a.id == pattern.assetId)
        .firstOrNull;
    if (asset == null) return;
    var start = trimStartMs.clamp(0, asset.durationMs - 1);
    var end = trimEndMs.clamp(0, asset.durationMs - 1);
    if (start + end >= asset.durationMs) {
      end = (asset.durationMs - start - 1).clamp(0, asset.durationMs - 1);
    }
    state = state.copyWith(
      audioPatterns: state.audioPatterns
          .map(
            (p) => p.id == patternId
                ? p.copyWith(trimStartMs: start, trimEndMs: end)
                : p,
          )
          .toList(),
    );
  }

  /// Adds a new clip referencing an existing pattern (shared link) — the
  /// paste half of copy/paste. Returns the new clip id, or null when the
  /// track type doesn't match the pattern or the slot is occupied.
  String? addClipReference({
    required String patternId,
    required SongPatternType patternType,
    required String trackId,
    required int startTick,
  }) {
    final track = state.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return null;
    final matches = switch (patternType) {
      SongPatternType.note => track.type == SongTrackType.note,
      SongPatternType.drum => track.type == SongTrackType.drum,
      SongPatternType.audio => track.type == SongTrackType.audio,
    };
    if (!matches) return null;
    final newClip = SongClipInstance(
      id: _id('sci'),
      trackId: trackId,
      patternId: patternId,
      patternType: patternType,
      startTick: startTick < 0 ? 0 : startTick,
    );
    final patternLen = rules.patternLengthForClip(
      state.copyWith(clips: [...state.clips, newClip]),
      newClip,
    );
    if (patternLen == null) return null;
    if (!rules.canPlaceClipOnTrack(
      state,
      newClip,
      patternLengthTicks: patternLen,
    )) {
      return null;
    }
    state = state.copyWith(clips: [...state.clips, newClip]);
    state = rules.ensureProjectCoversEndTick(
      state,
      newClip.startTick + patternLen,
    );
    return newClip.id;
  }

  /// Replaces the current song with a skeleton generated from the Writer's
  /// arrangement (sections → measures + markers, harmony → chord stabs,
  /// drum lanes → drum tracks, save lanes → voicing tracks).
  void importFromSongwriter() {
    final writer = ref.read(songwriterProvider);
    final saves = ref.read(saveSystemProvider).saves;
    state = songFromSongwriter(writer, saves);
  }

  // ── Markers ─────────────────────────────────────────────────────────────────

  String addMarker(int tick, String label) {
    final marker = SongMarker(
      id: _id('mk'),
      tick: tick < 0 ? 0 : tick,
      label: label,
    );
    state = state.copyWith(
      markers: [...state.markers, marker]
        ..sort((a, b) => a.tick.compareTo(b.tick)),
    );
    return marker.id;
  }

  void updateMarker(String id, {int? tick, String? label}) {
    state = state.copyWith(
      markers: [
        for (final m in state.markers)
          if (m.id == id) m.copyWith(tick: tick, label: label) else m,
      ]..sort((a, b) => a.tick.compareTo(b.tick)),
    );
  }

  void removeMarker(String id) {
    state = state.copyWith(
      markers: state.markers.where((m) => m.id != id).toList(),
    );
  }

  /// Moves a track up/down the lane order by [delta] positions (clamped).
  void moveTrack(String trackId, int delta) {
    final ordered = [...state.tracks]
      ..sort((a, b) => a.order.compareTo(b.order));
    final from = ordered.indexWhere((t) => t.id == trackId);
    if (from < 0) return;
    final to = (from + delta).clamp(0, ordered.length - 1);
    if (to == from) return;
    final track = ordered.removeAt(from);
    ordered.insert(to, track);
    state = state.copyWith(
      tracks: [
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(order: i),
      ],
    );
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

  // ── Audio Clip Mutations ────────────────────────────────────────────────────

  String addAudioClip({
    required String trackId,
    required int startTick,
    required AudioAsset asset,
    String? clipName,
  }) {
    final patternId = _id('ap');
    final effectiveName =
        clipName ??
        (asset.sourceLabel.isNotEmpty ? asset.sourceLabel : 'Audio');
    final pattern = AudioClipPattern(
      id: patternId,
      name: effectiveName,
      assetId: asset.id,
    );
    final clipId = _id('sci');
    final clip = SongClipInstance(
      id: clipId,
      trackId: trackId,
      patternId: patternId,
      patternType: SongPatternType.audio,
      startTick: startTick,
    );

    state = state.copyWith(
      audioAssets: [...state.audioAssets, asset],
      audioPatterns: [...state.audioPatterns, pattern],
      clips: [...state.clips, clip],
    );

    final lengthTicks = audioClipLengthTicks(asset, state.config);
    state = rules.ensureProjectCoversEndTick(state, startTick + lengthTicks);
    return clipId;
  }

  void removeAudioClip(String clipId) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    if (clip.patternType != SongPatternType.audio) return;
    final pattern = state.audioPatterns.firstWhere(
      (p) => p.id == clip.patternId,
    );

    state = state.copyWith(
      clips: state.clips.where((c) => c.id != clipId).toList(),
      audioPatterns: state.audioPatterns
          .where((p) => p.id != pattern.id)
          .toList(),
      audioAssets: state.audioAssets
          .where((a) => a.id != pattern.assetId)
          .toList(),
    );
  }

  void renameAudioClip(String clipId, String name) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    if (clip.patternType != SongPatternType.audio) return;
    final trimmed = name.trim();
    final effective = trimmed.isEmpty ? 'Audio' : trimmed;
    state = state.copyWith(
      audioPatterns: state.audioPatterns
          .map((p) => p.id == clip.patternId ? p.copyWith(name: effective) : p)
          .toList(),
    );
  }

  // ── Project Load ────────────────────────────────────────────────────────────

  Future<void> loadProject(SongProject project) async {
    state = project;
    final repo = ref.read(songAudioRepositoryProvider);
    final referenced = {for (final a in state.audioAssets) a.id};
    await repo.reconcileOrphans(referencedAssetIds: referenced);
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

/// Copied clip reference — paste creates a new clip sharing the pattern.
final songClipClipboardProvider =
    StateProvider<({String patternId, SongPatternType patternType})?>(
      (_) => null,
    );

/// When true, clip create/move/resize snap to beats instead of measures.
final songSnapToBeatProvider = StateProvider<bool>((_) => false);

/// Horizontal timeline zoom (1.0 = 4 dp per tick). Pinch on the timeline.
final songTimelineZoomProvider = StateProvider<double>((_) => 1.0);
