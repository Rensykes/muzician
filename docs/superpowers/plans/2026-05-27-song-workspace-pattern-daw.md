# Song Workspace, Pattern Tracks, And Drum Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a new `Song` tab that provides a pattern-based clip arranger with reusable note and drum patterns, isolated note-pattern editing built from existing piano-roll infrastructure, step-sequencer drum editing, first-class Song save/load, import from existing instrument saves, and deterministic multi-track playback.

**Architecture:** Keep `SongProject` as a new canonical arrangement domain, separate from `PianoRollState`. Reuse the piano-roll grid and related provider-backed widgets only inside an isolated note-pattern editor bridge. Treat note and drum clips as instances of shared patterns, enforce non-overlap on the same track, validate pattern-length changes across every linked clip instance, and add a dedicated Song transport that expands patterns into absolute playback events.

**Tech Stack:** Flutter, Riverpod `NotifierProvider` and `StateProvider`, existing `PianoRollState` / `TimeSignature` models, shared save system, `flutter_test`, shared `NotePlayer`, and the specialist agents declared in `.agents/`.

---

## Multi-Agent Execution Model

### Required execution order

1. Task 1: Song domain models and pure arrangement rules
2. Task 2: Song project store and state wiring
3. Task 3: Song persistence and shared save-browser integration
4. Task 4: Snapshot import rules and store import entry points
5. Task 5: Song playback rules, transport store, and drum synthesis
6. Task 6: Song tab shell, arranger timeline, and track controls
7. Task 7: Note-pattern bridge and isolated piano-roll editor host
8. Task 8: Drum-machine editor and clip-edit integration
9. Task 9: Docs, review sweep, and full verification

### Review protocol

- Every implementation task gets a `code-quality` review before the next task starts.
- UI tasks (`6`, `7`, `8`) also get an `accessibility-ux` review before the next task starts.
- State-heavy tasks (`2`, `5`, `7`) should be checked against `.agents/state-architect.md` even when another specialist owns the implementation.
- Save/persistence tasks (`3`, `4`) should be checked against `.agents/save-system.md`.
- Do not batch multiple tasks into one subagent. One task, one fresh implementer, then review.

### Shared implementation constraints

- Do not mutate `PianoRollState` into a Song-arranger model.
- Do not let Song pattern editing reuse the standalone Roll session container.
- Do not allow same-track clip overlap in v1.
- Do not silently auto-shift other clips when a create, move, duplicate, or pattern-resize operation would overlap.
- Reuse `TimeSignature` and piano-roll tick semantics (`1 tick = 1/16`) rather than inventing a second timing grid.
- Reuse `piano_roll_import_rules.dart` for snapshot-to-MIDI extraction where possible; do not duplicate import math in Song code.
- Preserve the existing bottom-nav tabs and add `Song` as a new entry rather than replacing `Roll`.

---

## File Structure

### Create

- `lib/models/song_project.dart`
- `lib/models/song_playback.dart`
- `lib/schema/rules/song_rules.dart`
- `lib/schema/rules/song_import_rules.dart`
- `lib/schema/rules/song_playback_rules.dart`
- `lib/schema/rules/song_pattern_bridge_rules.dart`
- `lib/store/song_project_store.dart`
- `lib/store/song_playback_store.dart`
- `lib/features/song/song_feature.dart`
- `lib/features/song/song_screen.dart`
- `lib/features/song/song_arranger_timeline.dart`
- `lib/features/song/song_track_header.dart`
- `lib/features/song/song_save_panel.dart`
- `lib/features/song/song_pattern_editor_launcher.dart`
- `lib/features/song/song_note_pattern_editor.dart`
- `lib/features/song/drum_machine_editor.dart`
- `test/schema/rules/song_rules_test.dart`
- `test/schema/rules/song_import_rules_test.dart`
- `test/schema/rules/song_playback_rules_test.dart`
- `test/schema/rules/song_pattern_bridge_rules_test.dart`
- `test/store/song_project_store_test.dart`
- `test/store/song_playback_store_test.dart`
- `test/features/song/song_screen_test.dart`
- `test/features/song/song_save_panel_test.dart`
- `test/features/song/song_note_pattern_editor_test.dart`
- `test/features/song/drum_machine_editor_test.dart`

### Modify

- `lib/models/save_system.dart`
- `lib/store/save_system_store.dart`
- `lib/ui/save_browser_panel.dart`
- `lib/utils/note_player.dart`
- `lib/main.dart`
- `test/store/save_system_store_test.dart`
- `docs/save_system.md`
- `docs/piano_roll.md`

---

## Task 1: Song Domain Models And Pure Arrangement Rules

**Owner:** `state-architect`

**Required reviewers after implementation:** `code-quality`

**Files:**

- Create: `lib/models/song_project.dart`
- Create: `lib/schema/rules/song_rules.dart`
- Test: `test/schema/rules/song_rules_test.dart`

- [ ] **Step 1: Write the failing pure tests for the Song domain**

```dart
// test/schema/rules/song_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_rules.dart' as rules;

void main() {
  test('songTotalTicks uses shared time-signature math', () {
    const config = SongProjectConfig(
      tempo: 120,
      timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
      totalMeasures: 4,
    );

    expect(rules.songTotalTicks(config), 64);
  });

  test('canPlaceClipOnTrack rejects same-track overlap', () {
    final project = rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(
          id: 't1',
          name: 'Track 1',
          type: SongTrackType.note,
          order: 0,
        ),
      ],
      clips: const [
        SongClipInstance(
          id: 'c1',
          trackId: 't1',
          patternId: 'p1',
          patternType: SongPatternType.note,
          startTick: 0,
        ),
      ],
      notePatterns: const [
        NotePattern(
          id: 'p1',
          name: 'Pattern 1',
          lengthTicks: 16,
          notes: [],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
    );

    final candidate = const SongClipInstance(
      id: 'c2',
      trackId: 't1',
      patternId: 'p2',
      patternType: SongPatternType.note,
      startTick: 8,
    );

    expect(
      rules.canPlaceClipOnTrack(project, candidate, patternLengthTicks: 16),
      isFalse,
    );
  });

  test('clonePatternForClip creates a new pattern id and relinks only one clip', () {
    final project = rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(id: 't1', name: 'Track 1', type: SongTrackType.note, order: 0),
      ],
      clips: const [
        SongClipInstance(
          id: 'c1',
          trackId: 't1',
          patternId: 'p1',
          patternType: SongPatternType.note,
          startTick: 0,
        ),
        SongClipInstance(
          id: 'c2',
          trackId: 't1',
          patternId: 'p1',
          patternType: SongPatternType.note,
          startTick: 16,
        ),
      ],
      notePatterns: const [
        NotePattern(
          id: 'p1',
          name: 'Shared Pattern',
          lengthTicks: 16,
          notes: [
            NotePatternNote(id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
    );

    final result = rules.cloneNotePatternForClip(
      project,
      clipId: 'c2',
      newPatternId: 'p2',
      newPatternName: 'Shared Pattern Copy',
    );

    expect(result.clonedPattern.id, 'p2');
    expect(result.updatedClip.patternId, 'p2');
    expect(project.clips.first.patternId, 'p1');
  });
}
```

- [ ] **Step 2: Run the rule tests and confirm they fail**

Run: `flutter test test/schema/rules/song_rules_test.dart`

Expected: FAIL with missing Song-domain types and helpers such as `SongProjectConfig`, `SongClipInstance`, or `songTotalTicks`.

- [ ] **Step 3: Add the canonical Song domain models**

```dart
// lib/models/song_project.dart
import 'piano_roll.dart';

enum SongTrackType { note, drum }
enum SongPatternType { note, drum }
enum DrumLaneId {
  kick,
  snare,
  closedHiHat,
  openHiHat,
  clap,
  lowTom,
  highTom,
  crash,
}

class SongProjectConfig {
  final int tempo;
  final TimeSignature timeSignature;
  final int totalMeasures;

  const SongProjectConfig({
    required this.tempo,
    required this.timeSignature,
    required this.totalMeasures,
  });

  SongProjectConfig copyWith({
    int? tempo,
    TimeSignature? timeSignature,
    int? totalMeasures,
  }) => SongProjectConfig(
    tempo: tempo ?? this.tempo,
    timeSignature: timeSignature ?? this.timeSignature,
    totalMeasures: totalMeasures ?? this.totalMeasures,
  );

  Map<String, dynamic> toJson() => {
    'tempo': tempo,
    'timeSignature': timeSignature.toJson(),
    'totalMeasures': totalMeasures,
  };

  factory SongProjectConfig.fromJson(Map<String, dynamic> json) =>
      SongProjectConfig(
        tempo: json['tempo'] as int,
        timeSignature: TimeSignature.fromJson(
          json['timeSignature'] as Map<String, dynamic>,
        ),
        totalMeasures: json['totalMeasures'] as int,
      );
}

class SongTrack {
  final String id;
  final String name;
  final SongTrackType type;
  final int order;
  final bool isMuted;
  final bool isSolo;

  const SongTrack({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
    this.isMuted = false,
    this.isSolo = false,
  });

  SongTrack copyWith({
    String? name,
    int? order,
    bool? isMuted,
    bool? isSolo,
  }) => SongTrack(
    id: id,
    name: name ?? this.name,
    type: type,
    order: order ?? this.order,
    isMuted: isMuted ?? this.isMuted,
    isSolo: isSolo ?? this.isSolo,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'order': order,
    'isMuted': isMuted,
    'isSolo': isSolo,
  };

  factory SongTrack.fromJson(Map<String, dynamic> json) => SongTrack(
    id: json['id'] as String,
    name: json['name'] as String,
    type: SongTrackType.values.firstWhere((value) => value.name == json['type']),
    order: json['order'] as int,
    isMuted: json['isMuted'] as bool? ?? false,
    isSolo: json['isSolo'] as bool? ?? false,
  );
}

class SongClipInstance {
  final String id;
  final String trackId;
  final String patternId;
  final SongPatternType patternType;
  final int startTick;

  const SongClipInstance({
    required this.id,
    required this.trackId,
    required this.patternId,
    required this.patternType,
    required this.startTick,
  });

  SongClipInstance copyWith({
    String? trackId,
    String? patternId,
    SongPatternType? patternType,
    int? startTick,
  }) => SongClipInstance(
    id: id,
    trackId: trackId ?? this.trackId,
    patternId: patternId ?? this.patternId,
    patternType: patternType ?? this.patternType,
    startTick: startTick ?? this.startTick,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackId': trackId,
    'patternId': patternId,
    'patternType': patternType.name,
    'startTick': startTick,
  };

  factory SongClipInstance.fromJson(Map<String, dynamic> json) =>
      SongClipInstance(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        patternId: json['patternId'] as String,
        patternType: SongPatternType.values.firstWhere(
          (value) => value.name == json['patternType'],
        ),
        startTick: json['startTick'] as int,
      );
}

class NotePatternNote {
  final String id;
  final int midiNote;
  final int startTick;
  final int durationTicks;

  const NotePatternNote({
    required this.id,
    required this.midiNote,
    required this.startTick,
    required this.durationTicks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'midiNote': midiNote,
    'startTick': startTick,
    'durationTicks': durationTicks,
  };

  factory NotePatternNote.fromJson(Map<String, dynamic> json) =>
      NotePatternNote(
        id: json['id'] as String,
        midiNote: json['midiNote'] as int,
        startTick: json['startTick'] as int,
        durationTicks: json['durationTicks'] as int,
      );
}

class NotePattern {
  final String id;
  final String name;
  final int lengthTicks;
  final List<NotePatternNote> notes;
  final int pitchRangeStart;
  final int pitchRangeEnd;
  final int snapTicks;
  final List<String> highlightedNotes;

  const NotePattern({
    required this.id,
    required this.name,
    required this.lengthTicks,
    required this.notes,
    required this.pitchRangeStart,
    required this.pitchRangeEnd,
    required this.snapTicks,
    required this.highlightedNotes,
  });

  NotePattern copyWith({
    String? name,
    int? lengthTicks,
    List<NotePatternNote>? notes,
    int? pitchRangeStart,
    int? pitchRangeEnd,
    int? snapTicks,
    List<String>? highlightedNotes,
  }) => NotePattern(
    id: id,
    name: name ?? this.name,
    lengthTicks: lengthTicks ?? this.lengthTicks,
    notes: notes ?? this.notes,
    pitchRangeStart: pitchRangeStart ?? this.pitchRangeStart,
    pitchRangeEnd: pitchRangeEnd ?? this.pitchRangeEnd,
    snapTicks: snapTicks ?? this.snapTicks,
    highlightedNotes: highlightedNotes ?? this.highlightedNotes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lengthTicks': lengthTicks,
    'notes': notes.map((note) => note.toJson()).toList(),
    'pitchRangeStart': pitchRangeStart,
    'pitchRangeEnd': pitchRangeEnd,
    'snapTicks': snapTicks,
    'highlightedNotes': highlightedNotes,
  };

  factory NotePattern.fromJson(Map<String, dynamic> json) => NotePattern(
    id: json['id'] as String,
    name: json['name'] as String,
    lengthTicks: json['lengthTicks'] as int,
    notes: (json['notes'] as List)
        .map((value) => NotePatternNote.fromJson(value as Map<String, dynamic>))
        .toList(),
    pitchRangeStart: json['pitchRangeStart'] as int,
    pitchRangeEnd: json['pitchRangeEnd'] as int,
    snapTicks: json['snapTicks'] as int,
    highlightedNotes:
        (json['highlightedNotes'] as List).map((value) => value as String).toList(),
  );
}

class DrumLaneSequence {
  final DrumLaneId laneId;
  final List<int> activeTicks;

  const DrumLaneSequence({
    required this.laneId,
    required this.activeTicks,
  });

  DrumLaneSequence copyWith({List<int>? activeTicks}) => DrumLaneSequence(
    laneId: laneId,
    activeTicks: activeTicks ?? this.activeTicks,
  );

  Map<String, dynamic> toJson() => {
    'laneId': laneId.name,
    'activeTicks': activeTicks,
  };

  factory DrumLaneSequence.fromJson(Map<String, dynamic> json) =>
      DrumLaneSequence(
        laneId: DrumLaneId.values.firstWhere(
          (value) => value.name == json['laneId'],
        ),
        activeTicks:
            (json['activeTicks'] as List).map((value) => value as int).toList(),
      );
}

class DrumPattern {
  final String id;
  final String name;
  final int lengthTicks;
  final List<DrumLaneSequence> lanes;

  const DrumPattern({
    required this.id,
    required this.name,
    required this.lengthTicks,
    required this.lanes,
  });

  DrumPattern copyWith({
    String? name,
    int? lengthTicks,
    List<DrumLaneSequence>? lanes,
  }) => DrumPattern(
    id: id,
    name: name ?? this.name,
    lengthTicks: lengthTicks ?? this.lengthTicks,
    lanes: lanes ?? this.lanes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lengthTicks': lengthTicks,
    'lanes': lanes.map((lane) => lane.toJson()).toList(),
  };

  factory DrumPattern.fromJson(Map<String, dynamic> json) => DrumPattern(
    id: json['id'] as String,
    name: json['name'] as String,
    lengthTicks: json['lengthTicks'] as int,
    lanes: (json['lanes'] as List)
        .map((value) => DrumLaneSequence.fromJson(value as Map<String, dynamic>))
        .toList(),
  );
}

class SongProject {
  final SongProjectConfig config;
  final List<SongTrack> tracks;
  final List<SongClipInstance> clips;
  final List<NotePattern> notePatterns;
  final List<DrumPattern> drumPatterns;

  const SongProject({
    required this.config,
    required this.tracks,
    required this.clips,
    required this.notePatterns,
    required this.drumPatterns,
  });

  SongProject copyWith({
    SongProjectConfig? config,
    List<SongTrack>? tracks,
    List<SongClipInstance>? clips,
    List<NotePattern>? notePatterns,
    List<DrumPattern>? drumPatterns,
  }) => SongProject(
    config: config ?? this.config,
    tracks: tracks ?? this.tracks,
    clips: clips ?? this.clips,
    notePatterns: notePatterns ?? this.notePatterns,
    drumPatterns: drumPatterns ?? this.drumPatterns,
  );

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'tracks': tracks.map((track) => track.toJson()).toList(),
    'clips': clips.map((clip) => clip.toJson()).toList(),
    'notePatterns': notePatterns.map((pattern) => pattern.toJson()).toList(),
    'drumPatterns': drumPatterns.map((pattern) => pattern.toJson()).toList(),
  };

  factory SongProject.fromJson(Map<String, dynamic> json) => SongProject(
    config: SongProjectConfig.fromJson(json['config'] as Map<String, dynamic>),
    tracks: (json['tracks'] as List)
        .map((value) => SongTrack.fromJson(value as Map<String, dynamic>))
        .toList(),
    clips: (json['clips'] as List)
        .map((value) => SongClipInstance.fromJson(value as Map<String, dynamic>))
        .toList(),
    notePatterns: (json['notePatterns'] as List)
        .map((value) => NotePattern.fromJson(value as Map<String, dynamic>))
        .toList(),
    drumPatterns: (json['drumPatterns'] as List)
        .map((value) => DrumPattern.fromJson(value as Map<String, dynamic>))
        .toList(),
  );
}
```

- [ ] **Step 4: Add pure arrangement helpers**

```dart
// lib/schema/rules/song_rules.dart
import '../../models/piano_roll.dart';
import '../../models/song_project.dart';

SongProject getDefaultSongProject() => SongProject(
  config: const SongProjectConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 4,
  ),
  tracks: const [],
  clips: const [],
  notePatterns: const [],
  drumPatterns: const [],
);

int songTicksPerMeasure(TimeSignature ts) {
  final beatTicks = ts.beatUnit == 8 ? 2 : 4;
  return ts.beatsPerMeasure * beatTicks;
}

int songTotalTicks(SongProjectConfig config) =>
    songTicksPerMeasure(config.timeSignature) * config.totalMeasures;

int patternLengthForClip(SongProject project, SongClipInstance clip) {
  if (clip.patternType == SongPatternType.note) {
    return project.notePatterns
        .firstWhere((pattern) => pattern.id == clip.patternId)
        .lengthTicks;
  }
  return project.drumPatterns
      .firstWhere((pattern) => pattern.id == clip.patternId)
      .lengthTicks;
}

bool canPlaceClipOnTrack(
  SongProject project,
  SongClipInstance candidate, {
  required int patternLengthTicks,
  String? excludingClipId,
}) {
  final candidateEnd = candidate.startTick + patternLengthTicks;
  final siblings = project.clips.where(
    (clip) =>
        clip.trackId == candidate.trackId &&
        clip.id != excludingClipId,
  );
  for (final clip in siblings) {
    final clipLength = patternLengthForClip(project, clip);
    final clipEnd = clip.startTick + clipLength;
    final overlaps = candidate.startTick < clipEnd && clip.startTick < candidateEnd && clip.startTick < candidateEnd;
    if (overlaps && candidateEnd > clip.startTick) {
      return false;
    }
  }
  return true;
}

int firstAvailableDuplicateStartTick(
  SongProject project,
  SongClipInstance source, {
  required int patternLengthTicks,
}) {
  var start = source.startTick + patternLengthTicks;
  while (!canPlaceClipOnTrack(
    project,
    source.copyWith(startTick: start),
    patternLengthTicks: patternLengthTicks,
    excludingClipId: source.id,
  )) {
    start += patternLengthTicks;
  }
  return start;
}

SongProject ensureProjectCoversEndTick(
  SongProject project,
  int endTickExclusive,
) {
  final measureTicks = songTicksPerMeasure(project.config.timeSignature);
  final requiredMeasures =
      ((endTickExclusive + measureTicks - 1) ~/ measureTicks).clamp(1, 32);
  if (requiredMeasures <= project.config.totalMeasures) {
    return project;
  }
  return project.copyWith(
    config: project.config.copyWith(totalMeasures: requiredMeasures),
  );
}

({SongClipInstance updatedClip, NotePattern clonedPattern}) cloneNotePatternForClip(
  SongProject project, {
  required String clipId,
  required String newPatternId,
  required String newPatternName,
}) {
  final clip = project.clips.firstWhere((value) => value.id == clipId);
  final pattern = project.notePatterns.firstWhere(
    (value) => value.id == clip.patternId,
  );
  final clonedPattern = NotePattern(
    id: newPatternId,
    name: newPatternName,
    lengthTicks: pattern.lengthTicks,
    notes: [
      for (final note in pattern.notes)
        NotePatternNote(
          id: '${newPatternId}_${note.id}',
          midiNote: note.midiNote,
          startTick: note.startTick,
          durationTicks: note.durationTicks,
        ),
    ],
    pitchRangeStart: pattern.pitchRangeStart,
    pitchRangeEnd: pattern.pitchRangeEnd,
    snapTicks: pattern.snapTicks,
    highlightedNotes: List<String>.from(pattern.highlightedNotes),
  );
  return (
    updatedClip: clip.copyWith(patternId: newPatternId),
    clonedPattern: clonedPattern,
  );
}

({SongClipInstance updatedClip, DrumPattern clonedPattern}) cloneDrumPatternForClip(
  SongProject project, {
  required String clipId,
  required String newPatternId,
  required String newPatternName,
}) {
  final clip = project.clips.firstWhere((value) => value.id == clipId);
  final pattern = project.drumPatterns.firstWhere(
    (value) => value.id == clip.patternId,
  );
  return (
    updatedClip: clip.copyWith(patternId: newPatternId),
    clonedPattern: DrumPattern(
      id: newPatternId,
      name: newPatternName,
      lengthTicks: pattern.lengthTicks,
      lanes: [
        for (final lane in pattern.lanes)
          DrumLaneSequence(
            laneId: lane.laneId,
            activeTicks: List<int>.from(lane.activeTicks),
          ),
      ],
    ),
  );
}

DrumPattern createEmptyDrumPattern({
  required String id,
  required String name,
  required int lengthTicks,
}) {
  return DrumPattern(
    id: id,
    name: name,
    lengthTicks: lengthTicks,
    lanes: const [
      DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.closedHiHat, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.openHiHat, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.clap, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.lowTom, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.highTom, activeTicks: []),
      DrumLaneSequence(laneId: DrumLaneId.crash, activeTicks: []),
    ],
  );
}

bool canApplyPatternLength(
  SongProject project,
  String patternId,
  int nextLengthTicks,
) {
  final linkedClips =
      project.clips.where((clip) => clip.patternId == patternId).toList();
  for (final clip in linkedClips) {
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
```

- [ ] **Step 5: Re-run the targeted rule tests**

Run: `flutter test test/schema/rules/song_rules_test.dart`

Expected: PASS

- [ ] **Step 6: Run a focused review pass**

Run: `dart analyze lib/models/song_project.dart lib/schema/rules/song_rules.dart test/schema/rules/song_rules_test.dart`

Expected: PASS with no analyzer issues.

- [ ] **Step 7: Commit the task**

```bash
git add \
  lib/models/song_project.dart \
  lib/schema/rules/song_rules.dart \
  test/schema/rules/song_rules_test.dart
git commit -m "feat: add song project domain and arrangement rules"
```

---

## Task 2: Song Project Store And UI-Scoped Selection Providers

**Owner:** `state-architect`

**Required reviewers after implementation:** `code-quality`

**Files:**

- Create: `lib/store/song_project_store.dart`
- Test: `test/store/song_project_store_test.dart`
- Modify: `lib/schema/rules/song_rules.dart`

- [ ] **Step 1: Write the failing store tests**

```dart
// test/store/song_project_store_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final originalClip = after.clips.firstWhere((clip) => clip.id == originalClipId);
    final duplicateClip = after.clips.firstWhere((clip) => clip.id == duplicateClipId);
    expect(originalClip.patternId == duplicateClip.patternId, isFalse);
  });
}
```

- [ ] **Step 2: Run the store tests and confirm they fail**

Run: `flutter test test/store/song_project_store_test.dart`

Expected: FAIL with missing `songProjectProvider` and related methods.

- [ ] **Step 3: Add the Song store and selection providers**

```dart
// lib/store/song_project_store.dart
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/piano_roll.dart';
import '../models/song_project.dart';
import '../schema/rules/song_rules.dart' as rules;

class SongProjectNotifier extends Notifier<SongProject> {
  @override
  SongProject build() => rules.getDefaultSongProject();

  String _id(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999).toString().padLeft(6, '0')}';

  void setTempo(int tempo) {
    state = state.copyWith(config: state.config.copyWith(tempo: tempo.clamp(20, 300)));
  }

  void setTimeSignature(TimeSignature timeSignature) {
    state = state.copyWith(config: state.config.copyWith(timeSignature: timeSignature));
  }

  void setTotalMeasures(int totalMeasures) {
    state = state.copyWith(
      config: state.config.copyWith(totalMeasures: totalMeasures.clamp(1, 32)),
    );
  }

  String addTrack(SongTrackType type, {String? name}) {
    final track = SongTrack(
      id: _id('song_track'),
      name: name ?? (type == SongTrackType.note ? 'Note Track' : 'Drum Track'),
      type: type,
      order: state.tracks.length,
    );
    state = state.copyWith(tracks: [...state.tracks, track]);
    return track.id;
  }

  String createEmptyNotePatternClip({
    required String trackId,
    required int startTick,
    int? lengthTicks,
    String? patternName,
  }) {
    final pattern = NotePattern(
      id: _id('note_pattern'),
      name: patternName ?? 'Pattern',
      lengthTicks: lengthTicks ?? rules.songTicksPerMeasure(state.config.timeSignature),
      notes: const [],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 1,
      highlightedNotes: const [],
    );
    final clip = SongClipInstance(
      id: _id('song_clip'),
      trackId: trackId,
      patternId: pattern.id,
      patternType: SongPatternType.note,
      startTick: startTick,
    );
    state = state.copyWith(
      notePatterns: [...state.notePatterns, pattern],
      clips: [...state.clips, clip],
    );
    return clip.id;
  }

  String createEmptyDrumPatternClip({
    required String trackId,
    required int startTick,
    int? lengthTicks,
    String? patternName,
  }) {
    final pattern = rules.createEmptyDrumPattern(
      id: _id('drum_pattern'),
      name: patternName ?? 'Drum Pattern',
      lengthTicks: lengthTicks ?? rules.songTicksPerMeasure(state.config.timeSignature),
    );
    final clip = SongClipInstance(
      id: _id('song_clip'),
      trackId: trackId,
      patternId: pattern.id,
      patternType: SongPatternType.drum,
      startTick: startTick,
    );
    state = state.copyWith(
      drumPatterns: [...state.drumPatterns, pattern],
      clips: [...state.clips, clip],
    );
    return clip.id;
  }
}

final songProjectProvider =
    NotifierProvider<SongProjectNotifier, SongProject>(SongProjectNotifier.new);

final songSelectedTrackIdProvider = StateProvider<String?>((_) => null);
final songSelectedClipIdProvider = StateProvider<String?>((_) => null);
```

- [ ] **Step 4: Add the rest of the clip and track mutations**

```dart
String _normaliseTrackName(String value, SongTrackType type) {
  final trimmed = value.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return type == SongTrackType.note ? 'Note Track' : 'Drum Track';
}

void renameTrack(String trackId, String name) {
  state = state.copyWith(
    tracks: [
      for (final track in state.tracks)
        track.id == trackId
            ? track.copyWith(name: _normaliseTrackName(name, track.type))
            : track,
    ],
  );
}

void toggleMute(String trackId) {
  state = state.copyWith(
    tracks: [
      for (final track in state.tracks)
        track.id == trackId
            ? track.copyWith(isMuted: !track.isMuted)
            : track,
    ],
  );
}

void toggleSolo(String trackId) {
  state = state.copyWith(
    tracks: [
      for (final track in state.tracks)
        track.id == trackId
            ? track.copyWith(isSolo: !track.isSolo)
            : track,
    ],
  );
}

void deleteTrack(String trackId) {
  final removedPatternIds = state.clips
      .where((clip) => clip.trackId == trackId)
      .map((clip) => clip.patternId)
      .toSet();
  final survivingClips = state.clips.where((clip) => clip.trackId != trackId).toList();
  final survivingPatternIds = survivingClips.map((clip) => clip.patternId).toSet();

  state = state.copyWith(
    tracks: state.tracks.where((track) => track.id != trackId).toList(),
    clips: survivingClips,
    notePatterns: state.notePatterns
        .where((pattern) => !removedPatternIds.contains(pattern.id) || survivingPatternIds.contains(pattern.id))
        .toList(),
    drumPatterns: state.drumPatterns
        .where((pattern) => !removedPatternIds.contains(pattern.id) || survivingPatternIds.contains(pattern.id))
        .toList(),
  );
}

void duplicateTrack(String trackId) {
  final source = state.tracks.firstWhere((track) => track.id == trackId);
  final newTrackId = _id('song_track');
  final duplicatedTrack = SongTrack(
    id: newTrackId,
    name: '${source.name} Copy',
    type: source.type,
    order: state.tracks.length,
    isMuted: false,
    isSolo: false,
  );
  final sourceClips = state.clips.where((clip) => clip.trackId == trackId).toList();
  final duplicatedClips = [
    for (final clip in sourceClips)
      SongClipInstance(
        id: _id('song_clip'),
        trackId: newTrackId,
        patternId: clip.patternId,
        patternType: clip.patternType,
        startTick: clip.startTick,
      ),
  ];
  state = state.copyWith(
    tracks: [...state.tracks, duplicatedTrack],
    clips: [...state.clips, ...duplicatedClips],
  );
}

void moveClip(String clipId, int newStartTick) {
  final clip = state.clips.firstWhere((value) => value.id == clipId);
  final patternLength = rules.patternLengthForClip(state, clip);
  final candidate = clip.copyWith(startTick: newStartTick.clamp(0, 511));
  if (!rules.canPlaceClipOnTrack(
    state,
    candidate,
    patternLengthTicks: patternLength,
    excludingClipId: clipId,
  )) {
    return;
  }
  final expanded = rules.ensureProjectCoversEndTick(
    state,
    candidate.startTick + patternLength,
  );
  state = expanded.copyWith(
    clips: [
      for (final value in expanded.clips)
        value.id == clipId ? candidate : value,
    ],
  );
}

String duplicateClip(String clipId) {
  final clip = state.clips.firstWhere((value) => value.id == clipId);
  final patternLength = rules.patternLengthForClip(state, clip);
  final startTick = rules.firstAvailableDuplicateStartTick(
    state,
    clip,
    patternLengthTicks: patternLength,
  );
  final newClip = SongClipInstance(
    id: _id('song_clip'),
    trackId: clip.trackId,
    patternId: clip.patternId,
    patternType: clip.patternType,
    startTick: startTick,
  );
  final expanded = rules.ensureProjectCoversEndTick(
    state,
    startTick + patternLength,
  );
  state = expanded.copyWith(clips: [...expanded.clips, newClip]);
  return newClip.id;
}

void deleteClip(String clipId) {
  final clip = state.clips.firstWhere((value) => value.id == clipId);
  final survivingClips = state.clips.where((value) => value.id != clipId).toList();
  final survivingPatternIds = survivingClips.map((value) => value.patternId).toSet();
  state = state.copyWith(
    clips: survivingClips,
    notePatterns: state.notePatterns
        .where((pattern) => pattern.id != clip.patternId || survivingPatternIds.contains(pattern.id))
        .toList(),
    drumPatterns: state.drumPatterns
        .where((pattern) => pattern.id != clip.patternId || survivingPatternIds.contains(pattern.id))
        .toList(),
  );
}

void makeClipPatternUnique(String clipId, {String? patternName}) {
  final clip = state.clips.firstWhere((value) => value.id == clipId);
  if (clip.patternType == SongPatternType.note) {
    final result = rules.cloneNotePatternForClip(
      state,
      clipId: clipId,
      newPatternId: _id('note_pattern'),
      newPatternName: patternName ?? 'Pattern Copy',
    );
    state = state.copyWith(
      clips: [
        for (final value in state.clips)
          value.id == clipId ? result.updatedClip : value,
      ],
      notePatterns: [...state.notePatterns, result.clonedPattern],
    );
    return;
  }
  final result = rules.cloneDrumPatternForClip(
    state,
    clipId: clipId,
    newPatternId: _id('drum_pattern'),
    newPatternName: patternName ?? 'Drum Pattern Copy',
  );
  state = state.copyWith(
    clips: [
      for (final value in state.clips)
        value.id == clipId ? result.updatedClip : value,
    ],
    drumPatterns: [...state.drumPatterns, result.clonedPattern],
  );
}

void applyNotePattern(String patternId, NotePattern nextPattern) {
  if (!rules.canApplyPatternLength(state, patternId, nextPattern.lengthTicks)) {
    return;
  }
  state = state.copyWith(
    notePatterns: [
      for (final pattern in state.notePatterns)
        pattern.id == patternId ? nextPattern : pattern,
    ],
  );
}

void applyDrumPattern(String patternId, DrumPattern nextPattern) {
  if (!rules.canApplyPatternLength(state, patternId, nextPattern.lengthTicks)) {
    return;
  }
  state = state.copyWith(
    drumPatterns: [
      for (final pattern in state.drumPatterns)
        pattern.id == patternId ? nextPattern : pattern,
    ],
  );
}

void loadProject(SongProject project) {
  state = project;
}
```

- [ ] **Step 5: Re-run the targeted store tests**

Run: `flutter test test/store/song_project_store_test.dart`

Expected: PASS

- [ ] **Step 6: Analyze the new store surface**

Run: `dart analyze lib/store/song_project_store.dart test/store/song_project_store_test.dart`

Expected: PASS

- [ ] **Step 7: Commit the task**

```bash
git add \
  lib/store/song_project_store.dart \
  test/store/song_project_store_test.dart \
  lib/schema/rules/song_rules.dart
git commit -m "feat: add song project store and clip mutations"
```

---

## Task 3: Song Persistence And Save-Browser Integration

**Owner:** `save-system`

**Required reviewers after implementation:** `code-quality`

**Files:**

- Modify: `lib/models/save_system.dart`
- Modify: `lib/store/save_system_store.dart`
- Modify: `lib/ui/save_browser_panel.dart`
- Create: `lib/features/song/song_save_panel.dart`
- Test: `test/store/save_system_store_test.dart`
- Test: `test/features/song/song_save_panel_test.dart`

- [ ] **Step 1: Write the failing persistence tests**

```dart
// test/store/save_system_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';

test('InstrumentSnapshot.fromJson restores SongProjectSnapshot', () {
  final json = <String, dynamic>{
    'type': 'song',
    'instrument': 'song',
    'project': {
      'config': {
        'tempo': 120,
        'timeSignature': {'beatsPerMeasure': 4, 'beatUnit': 4},
        'totalMeasures': 4,
      },
      'tracks': [],
      'clips': [],
      'notePatterns': [],
      'drumPatterns': [],
    },
  };

  final snapshot = InstrumentSnapshot.fromJson(json);
  expect(snapshot, isA<SongProjectSnapshot>());
});

test('SongProjectSnapshot round-trips track, clip, and pattern counts', () {
  final snapshot = SongProjectSnapshot(
    project: SongProject(
      config: const SongProjectConfig(
        tempo: 128,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 8,
      ),
      tracks: const [
        SongTrack(id: 't1', name: 'Lead', type: SongTrackType.note, order: 0),
        SongTrack(id: 't2', name: 'Drums', type: SongTrackType.drum, order: 1),
      ],
      clips: const [
        SongClipInstance(
          id: 'c1',
          trackId: 't1',
          patternId: 'p1',
          patternType: SongPatternType.note,
          startTick: 0,
        ),
        SongClipInstance(
          id: 'c2',
          trackId: 't2',
          patternId: 'd1',
          patternType: SongPatternType.drum,
          startTick: 16,
        ),
      ],
      notePatterns: const [
        NotePattern(
          id: 'p1',
          name: 'Lead',
          lengthTicks: 16,
          notes: [NotePatternNote(id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4)],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: ['C'],
        ),
      ],
      drumPatterns: const [
        DrumPattern(
          id: 'd1',
          name: 'Beat',
          lengthTicks: 16,
          lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8])],
        ),
      ],
    ),
  );

  final restored = SongProjectSnapshot.fromJson(snapshot.toJson());
  expect(restored.project.tracks, hasLength(2));
  expect(restored.project.clips, hasLength(2));
  expect(restored.project.notePatterns, hasLength(1));
  expect(restored.project.drumPatterns, hasLength(1));
});
```

```dart
// test/features/song/song_save_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_save_panel.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/ui/save_browser_panel.dart';

testWidgets('SongSavePanel captures the current song project and restores it', (
  tester,
) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  container.read(songProjectProvider.notifier).loadProject(
    SongProject(
      config: const SongProjectConfig(
        tempo: 132,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 4,
      ),
      tracks: const [
        SongTrack(id: 't1', name: 'Lead', type: SongTrackType.note, order: 0),
      ],
      clips: const [],
      notePatterns: const [],
      drumPatterns: const [],
    ),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongSavePanel())),
    ),
  );

  final panel = tester.widget<SaveBrowserPanel>(find.byType(SaveBrowserPanel));
  final snapshot = panel.captureSnapshot();
  expect(snapshot, isA<SongProjectSnapshot>());

  panel.onLoad(
    SongProjectSnapshot(
      project: SongProject(
        config: const SongProjectConfig(
          tempo: 90,
          timeSignature: TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
          totalMeasures: 2,
        ),
        tracks: const [
          SongTrack(id: 't2', name: 'Imported', type: SongTrackType.note, order: 0),
        ],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
      ),
    ),
  );
  await tester.pump();

  expect(container.read(songProjectProvider).config.tempo, 90);
  expect(container.read(songProjectProvider).tracks.single.name, 'Imported');
});
```

- [ ] **Step 2: Run the persistence tests and confirm they fail**

Run:

- `flutter test test/store/save_system_store_test.dart`
- `flutter test test/features/song/song_save_panel_test.dart`

Expected: FAIL with missing `SongProjectSnapshot` and `SongSavePanel`.

- [ ] **Step 3: Add SongProjectSnapshot**

```dart
// lib/models/save_system.dart
import 'song_project.dart';

class SongProjectSnapshot extends InstrumentSnapshot {
  @override
  String get instrument => 'song';

  final SongProject project;

  SongProjectSnapshot({required this.project});

  @override
  List<String> get selectedNotes => project.notePatterns
      .expand((pattern) => pattern.notes)
      .map((note) => pr_rules.midiToPitchClass(note.midiNote))
      .toSet()
      .toList();

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'song',
    'instrument': 'song',
    'project': project.toJson(),
  };

  factory SongProjectSnapshot.fromJson(Map<String, dynamic> json) =>
      SongProjectSnapshot(
        project: SongProject.fromJson(
          json['project'] as Map<String, dynamic>,
        ),
      );
}
```

Also update `InstrumentSnapshot.fromJson(...)`:

```dart
if (type == 'song' || instrument == 'song') {
  return SongProjectSnapshot.fromJson(json);
}
```

- [ ] **Step 4: Add SongSavePanel and SaveBrowserPanel Song previews**

```dart
// lib/features/song/song_save_panel.dart
class SongSavePanel extends ConsumerWidget {
  const SongSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SaveBrowserPanel(
      instrumentFilter: 'song',
      captureSnapshot: () =>
          SongProjectSnapshot(project: ref.read(songProjectProvider)),
      onLoad: (snap) {
        if (snap is SongProjectSnapshot) {
          ref.read(songProjectProvider.notifier).loadProject(snap.project);
        }
      },
    );
  }
}
```

Update `SaveBrowserPanel` to:

- show a Song-specific icon
- show Song-specific summary lines like `2 tracks • 4 clips • 3 patterns`
- avoid chord/scale summary fallback for `SongProjectSnapshot`

- [ ] **Step 5: Re-run the targeted persistence tests**

Run:

- `flutter test test/store/save_system_store_test.dart`
- `flutter test test/features/song/song_save_panel_test.dart`

Expected: PASS

- [ ] **Step 6: Run analyzer on persistence files**

Run:

- `dart analyze lib/models/save_system.dart lib/ui/save_browser_panel.dart lib/features/song/song_save_panel.dart`

Expected: PASS

- [ ] **Step 7: Commit the task**

```bash
git add \
  lib/models/save_system.dart \
  lib/ui/save_browser_panel.dart \
  lib/features/song/song_save_panel.dart \
  test/store/save_system_store_test.dart \
  test/features/song/song_save_panel_test.dart
git commit -m "feat: add song project snapshot persistence"
```

---

## Task 4: Snapshot Import Rules And Store Import Entry Points

**Owner:** `save-system`

**Required reviewers after implementation:** `code-quality`

**Files:**

- Create: `lib/schema/rules/song_import_rules.dart`
- Modify: `lib/store/song_project_store.dart`
- Test: `test/schema/rules/song_import_rules_test.dart`
- Test: `test/store/song_project_store_test.dart`

- [ ] **Step 1: Write the failing import-rule tests**

```dart
// test/schema/rules/song_import_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/schema/rules/song_import_rules.dart' as rules;

void main() {
  test('PianoRollSnapshot imports exact note timings into a NotePattern', () {
    final snapshot = PianoRollSnapshot(
      tempo: 90,
      key: 'C',
      numerator: 4,
      denominator: 4,
      totalMeasures: 2,
      notes: const [
        {'midiNote': 60, 'startTick': 0, 'durationTicks': 4},
        {'midiNote': 64, 'startTick': 4, 'durationTicks': 4},
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      snapTicks: 1,
      highlightedNotes: const [],
    );

    final pattern = rules.notePatternFromSnapshot(
      snapshot,
      patternId: 'p1',
      patternName: 'Imported',
      songMeasureTicks: 16,
      fallbackLengthTicks: 16,
    );

    expect(pattern.notes, hasLength(2));
    expect(pattern.lengthTicks, 16);
  });

  test('PianoSnapshot imports as a stacked pattern at tick zero', () {
    final snapshot = PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [
        PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C'),
        PianoCoordinate(keyIndex: 4, midiNote: 64, noteName: 'E'),
        PianoCoordinate(keyIndex: 7, midiNote: 67, noteName: 'G'),
      ],
      selectedNotes: const ['C', 'E', 'G'],
      viewMode: PianoViewMode.exact,
    );

    final pattern = rules.notePatternFromSnapshot(
      snapshot,
      patternId: 'p2',
      patternName: 'Piano Stack',
      songMeasureTicks: 16,
      fallbackLengthTicks: 8,
    );

    expect(pattern.notes.map((note) => note.midiNote), [60, 64, 67]);
    expect(pattern.notes.every((note) => note.startTick == 0), isTrue);
    expect(pattern.notes.every((note) => note.durationTicks == 8), isTrue);
  });

  test('FretboardSnapshot imports exact tuning-based midis', () {
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [
        FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
        FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
      ],
      selectedNotes: const ['E', 'C'],
      viewMode: FretboardViewMode.exact,
    );

    final pattern = rules.notePatternFromSnapshot(
      snapshot,
      patternId: 'p3',
      patternName: 'Fretboard Stack',
      songMeasureTicks: 16,
      fallbackLengthTicks: 4,
    );

    expect(pattern.notes.map((note) => note.midiNote), [64, 60]);
    expect(pattern.notes.every((note) => note.durationTicks == 4), isTrue);
  });
}
```

- [ ] **Step 2: Run the import tests and confirm they fail**

Run: `flutter test test/schema/rules/song_import_rules_test.dart`

Expected: FAIL with missing `notePatternFromSnapshot`.

- [ ] **Step 3: Add the import rule layer**

```dart
// lib/schema/rules/song_import_rules.dart
import '../../models/save_system.dart';
import '../../models/song_project.dart';
import 'piano_roll_import_rules.dart' as piano_roll_import_rules;

NotePattern notePatternFromSnapshot(
  InstrumentSnapshot snapshot, {
  required String patternId,
  required String patternName,
  required int songMeasureTicks,
  required int fallbackLengthTicks,
}) {
  if (snapshot is PianoRollSnapshot) {
    final notes = snapshot.notes.map((note) {
      return NotePatternNote(
        id: '${patternId}_${note['startTick']}_${note['midiNote']}',
        midiNote: note['midiNote'] as int,
        startTick: note['startTick'] as int,
        durationTicks: note['durationTicks'] as int,
      );
    }).toList();
    final furthestEndTick = notes.isEmpty
        ? fallbackLengthTicks
        : notes
              .map((note) => note.startTick + note.durationTicks)
              .reduce((a, b) => a > b ? a : b);
    final roundedLength =
        ((furthestEndTick + songMeasureTicks - 1) ~/ songMeasureTicks) *
            songMeasureTicks;
    return NotePattern(
      id: patternId,
      name: patternName,
      lengthTicks: roundedLength.clamp(songMeasureTicks, 512),
      notes: notes,
      pitchRangeStart: snapshot.pitchRangeStart,
      pitchRangeEnd: snapshot.pitchRangeEnd,
      snapTicks: snapshot.snapTicks,
      highlightedNotes: List<String>.from(snapshot.highlightedNotes),
    );
  }

  final midiStack = piano_roll_import_rules.extractSnapshotImportMidis(
        snapshot,
        exactPitchClassMode: true,
      ) ??
      const <int>[];
  return NotePattern(
    id: patternId,
    name: patternName,
    lengthTicks: fallbackLengthTicks,
    notes: [
      for (final midi in midiStack)
        NotePatternNote(
          id: '${patternId}_$midi',
          midiNote: midi,
          startTick: 0,
          durationTicks: fallbackLengthTicks,
        ),
    ],
    pitchRangeStart: 48,
    pitchRangeEnd: 84,
    snapTicks: 1,
    highlightedNotes: const [],
  );
}
```

- [ ] **Step 4: Add store entry points for imported note clips**

```dart
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
    throw StateError('Imported clip would overlap an existing clip on the track');
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
```

- [ ] **Step 5: Re-run the targeted import tests**

Run:

- `flutter test test/schema/rules/song_import_rules_test.dart`
- `flutter test test/store/song_project_store_test.dart`

Expected: PASS

- [ ] **Step 6: Commit the task**

```bash
git add \
  lib/schema/rules/song_import_rules.dart \
  lib/store/song_project_store.dart \
  test/schema/rules/song_import_rules_test.dart \
  test/store/song_project_store_test.dart
git commit -m "feat: add song snapshot import rules"
```

---

## Task 5: Song Playback Rules, Transport Store, And Drum Synthesis

**Owner:** `state-architect`

**Required reviewers after implementation:** `code-quality`

**Files:**

- Create: `lib/models/song_playback.dart`
- Create: `lib/schema/rules/song_playback_rules.dart`
- Create: `lib/store/song_playback_store.dart`
- Modify: `lib/utils/note_player.dart`
- Test: `test/schema/rules/song_playback_rules_test.dart`
- Test: `test/store/song_playback_store_test.dart`

- [ ] **Step 1: Write the failing playback-rule tests**

```dart
// test/schema/rules/song_playback_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_playback_rules.dart' as rules;
import 'package:muzician/schema/rules/song_rules.dart' as song_rules;

void main() {
  test('buildPlaybackEvents expands note clips to absolute ticks', () {
    final project = song_rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(id: 'noteTrack', name: 'Lead', type: SongTrackType.note, order: 0),
      ],
      clips: const [
        SongClipInstance(
          id: 'clip1',
          trackId: 'noteTrack',
          patternId: 'pattern1',
          patternType: SongPatternType.note,
          startTick: 16,
        ),
      ],
      notePatterns: const [
        NotePattern(
          id: 'pattern1',
          name: 'Lead Pattern',
          lengthTicks: 16,
          notes: [
            NotePatternNote(id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
    );

    final events = rules.buildPlaybackEvents(project);
    expect(events.single.tick, 16);
    expect(events.single.midiNotes, [60]);
  });

  test('mute and solo are applied before event expansion', () {
    final project = song_rules.getDefaultSongProject().copyWith(
      tracks: const [
        SongTrack(id: 't1', name: 'Lead', type: SongTrackType.note, order: 0),
        SongTrack(id: 't2', name: 'Bass', type: SongTrackType.note, order: 1, isMuted: true),
        SongTrack(id: 't3', name: 'Solo', type: SongTrackType.note, order: 2, isSolo: true),
      ],
      clips: const [
        SongClipInstance(id: 'c1', trackId: 't1', patternId: 'p1', patternType: SongPatternType.note, startTick: 0),
        SongClipInstance(id: 'c2', trackId: 't2', patternId: 'p2', patternType: SongPatternType.note, startTick: 0),
        SongClipInstance(id: 'c3', trackId: 't3', patternId: 'p3', patternType: SongPatternType.note, startTick: 0),
      ],
      notePatterns: const [
        NotePattern(
          id: 'p1',
          name: 'Lead Pattern',
          lengthTicks: 16,
          notes: [NotePatternNote(id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4)],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
        NotePattern(
          id: 'p2',
          name: 'Bass Pattern',
          lengthTicks: 16,
          notes: [NotePatternNote(id: 'n2', midiNote: 48, startTick: 0, durationTicks: 4)],
          pitchRangeStart: 36,
          pitchRangeEnd: 72,
          snapTicks: 1,
          highlightedNotes: [],
        ),
        NotePattern(
          id: 'p3',
          name: 'Solo Pattern',
          lengthTicks: 16,
          notes: [NotePatternNote(id: 'n3', midiNote: 72, startTick: 0, durationTicks: 4)],
          pitchRangeStart: 60,
          pitchRangeEnd: 96,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
    );

    final events = rules.buildPlaybackEvents(project);
    expect(events.single.midiNotes, [72]);
  });
}
```

- [ ] **Step 2: Run the playback tests and confirm they fail**

Run:

- `flutter test test/schema/rules/song_playback_rules_test.dart`
- `flutter test test/store/song_playback_store_test.dart`

Expected: FAIL with missing Song playback types and helpers.

- [ ] **Step 3: Add playback models and pure event-expansion rules**

```dart
// lib/models/song_playback.dart
enum SongPlaybackStatus { idle, playing, completed, error }

class SongPlaybackEvent {
  final int tick;
  final List<int> midiNotes;
  final List<DrumLaneId> drumLanes;

  const SongPlaybackEvent({
    required this.tick,
    required this.midiNotes,
    required this.drumLanes,
  });
}

class SongPlaybackState {
  final SongPlaybackStatus status;
  final int? currentTick;
  final int? startTick;
  final int? endTickExclusive;
  final String? message;
  final String? errorMessage;

  const SongPlaybackState({
    this.status = SongPlaybackStatus.idle,
    this.currentTick,
    this.startTick,
    this.endTickExclusive,
    this.message,
    this.errorMessage,
  });
}
```

```dart
// lib/schema/rules/song_playback_rules.dart
List<SongTrack> audibleTracks(SongProject project) {
  final soloed = project.tracks.where((track) => track.isSolo).toList();
  if (soloed.isNotEmpty) return soloed;
  return project.tracks.where((track) => !track.isMuted).toList();
}

List<SongPlaybackEvent> buildPlaybackEvents(SongProject project) {
  final activeTrackIds = audibleTracks(project).map((track) => track.id).toSet();
  final tickMap = <int, ({Set<int> midiNotes, Set<DrumLaneId> drumLanes})>{};

  for (final clip in project.clips.where((clip) => activeTrackIds.contains(clip.trackId))) {
    if (clip.patternType == SongPatternType.note) {
      final pattern = project.notePatterns.firstWhere((pattern) => pattern.id == clip.patternId);
      for (final note in pattern.notes) {
        final tick = clip.startTick + note.startTick;
        final bucket = tickMap.putIfAbsent(
          tick,
          () => (midiNotes: <int>{}, drumLanes: <DrumLaneId>{}),
        );
        bucket.midiNotes.add(note.midiNote);
      }
    } else {
      final pattern = project.drumPatterns.firstWhere((pattern) => pattern.id == clip.patternId);
      for (final lane in pattern.lanes) {
        for (final tick in lane.activeTicks) {
          final absoluteTick = clip.startTick + tick;
          final bucket = tickMap.putIfAbsent(
            absoluteTick,
            () => (midiNotes: <int>{}, drumLanes: <DrumLaneId>{}),
          );
          bucket.drumLanes.add(lane.laneId);
        }
      }
    }
  }

  final sortedTicks = tickMap.keys.toList()..sort();
  return [
    for (final tick in sortedTicks)
      SongPlaybackEvent(
        tick: tick,
        midiNotes: tickMap[tick]!.midiNotes.toList()..sort(),
        drumLanes: tickMap[tick]!.drumLanes.toList(),
      ),
  ];
}
```

- [ ] **Step 4: Add the transport store and drum sinks**

```dart
// lib/store/song_playback_store.dart
typedef SongNotePlaybackSink = Future<void> Function(List<int> midiNotes, double volume);
typedef SongDrumPlaybackSink = Future<void> Function(List<DrumLaneId> lanes, double volume);

final songNotePlaybackSinkProvider = Provider<SongNotePlaybackSink>((ref) {
  return (midiNotes, volume) async {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: volume);
    }
  };
});

final songDrumPlaybackSinkProvider = Provider<SongDrumPlaybackSink>((ref) {
  return (lanes, volume) async {
    for (final lane in lanes) {
      NotePlayer.instance.playDrumLane(lane, volume: volume);
    }
  };
});
```

Add `SongPlaybackNotifier.startPlayback()` mirroring the piano-roll store:

- snapshot `songProjectProvider`
- compute `events = rules.buildPlaybackEvents(project)`
- iterate tick-by-tick from `0` to `songTotalTicks(project.config)`
- fire metronome on beat boundaries when enabled
- fire note sink and drum sink for matching ticks

Extend `NotePlayer`:

```dart
void playDrumLane(DrumLaneId lane, {double volume = 0.8}) {
  if (!_ready) return;
  unawaited(_playDrum(lane, volume));
}
```

Implement lane-specific renderers using short generated waveforms and reserve negative cache keys per lane just like the click cache.

- [ ] **Step 5: Re-run the targeted playback tests**

Run:

- `flutter test test/schema/rules/song_playback_rules_test.dart`
- `flutter test test/store/song_playback_store_test.dart`

Expected: PASS

- [ ] **Step 6: Analyze the transport surface**

Run:

- `dart analyze lib/models/song_playback.dart lib/schema/rules/song_playback_rules.dart lib/store/song_playback_store.dart lib/utils/note_player.dart`

Expected: PASS

- [ ] **Step 7: Commit the task**

```bash
git add \
  lib/models/song_playback.dart \
  lib/schema/rules/song_playback_rules.dart \
  lib/store/song_playback_store.dart \
  lib/utils/note_player.dart \
  test/schema/rules/song_playback_rules_test.dart \
  test/store/song_playback_store_test.dart
git commit -m "feat: add song playback transport and drum voices"
```

---

## Task 6: Song Tab Shell, Arranger Timeline, And Track Controls

**Owner:** `instrument-renderer`

**Required reviewers after implementation:** `code-quality`, `accessibility-ux`

**Files:**

- Create: `lib/features/song/song_feature.dart`
- Create: `lib/features/song/song_screen.dart`
- Create: `lib/features/song/song_arranger_timeline.dart`
- Create: `lib/features/song/song_track_header.dart`
- Modify: `lib/main.dart`
- Test: `test/features/song/song_screen_test.dart`

- [ ] **Step 1: Write the failing Song-screen widget tests**

```dart
// test/features/song/song_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_screen.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  testWidgets('SongScreen renders transport, add track, and empty arranger state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SongScreen()),
      ),
    );

    expect(find.text('Song'), findsOneWidget);
    expect(find.text('Add Track'), findsOneWidget);
  });

  testWidgets('creating a note track renders a track header row', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songProjectProvider.notifier).addTrack(SongTrackType.note);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongScreen()),
      ),
    );

    expect(find.text('Note Track'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the Song-screen tests and confirm they fail**

Run: `flutter test test/features/song/song_screen_test.dart`

Expected: FAIL with missing `SongScreen`.

- [ ] **Step 3: Add the Song shell and bottom-nav entry**

```dart
// lib/features/song/song_screen.dart
class SongScreen extends ConsumerWidget {
  const SongScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songProjectProvider);
    final playback = ref.watch(songPlaybackProvider);
    final measureTicks = song_rules.songTicksPerMeasure(project.config.timeSignature);

    return Theme(
      data: MuzicianTheme.dark(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: MuzicianTheme.gradientColors,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              CompactAppBar(title: 'Song', chipLabel: '${project.tracks.length} tracks'),
              SongTransportBar(
                bpm: project.config.tempo,
                timeSignature: project.config.timeSignature,
                totalMeasures: project.config.totalMeasures,
                playback: playback,
                onAddTrack: () => _showAddTrackSheet(context, ref),
              ),
              Expanded(
                child: SongArrangerTimeline(
                  measureTicks: measureTicks,
                  currentPlaybackTick: playback.currentTick,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SongTransportBar extends StatelessWidget {
  final int bpm;
  final TimeSignature timeSignature;
  final int totalMeasures;
  final SongPlaybackState playback;
  final VoidCallback onAddTrack;

  const SongTransportBar({
    super.key,
    required this.bpm,
    required this.timeSignature,
    required this.totalMeasures,
    required this.playback,
    required this.onAddTrack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Rewind',
          onPressed: () {},
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton(
          tooltip: playback.status == SongPlaybackStatus.playing ? 'Pause' : 'Play',
          onPressed: () {},
          icon: Icon(
            playback.status == SongPlaybackStatus.playing
                ? Icons.pause
                : Icons.play_arrow,
          ),
        ),
        Text('BPM $bpm'),
        const SizedBox(width: 12),
        Text('${timeSignature.beatsPerMeasure}/${timeSignature.beatUnit}'),
        const SizedBox(width: 12),
        Text('$totalMeasures bars'),
        const Spacer(),
        TextButton.icon(
          onPressed: onAddTrack,
          icon: const Icon(Icons.add),
          label: const Text('Add Track'),
        ),
      ],
    );
  }
}
```

Update `main.dart`:

- add `SongScreen()` to `IndexedStack`
- add bottom-nav entry `Song`
- keep `Roll` as a separate tab

- [ ] **Step 4: Add the arranger timeline and track headers**

```dart
// lib/features/song/song_track_header.dart
class SongTrackHeader extends ConsumerWidget {
  final SongTrack track;
  const SongTrackHeader({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(child: Text(track.name)),
        IconButton(
          tooltip: 'Mute',
          onPressed: () =>
              ref.read(songProjectProvider.notifier).toggleMute(track.id),
          icon: Icon(track.isMuted ? Icons.volume_off : Icons.volume_up),
        ),
        IconButton(
          tooltip: 'Solo',
          onPressed: () =>
              ref.read(songProjectProvider.notifier).toggleSolo(track.id),
          icon: Icon(track.isSolo ? Icons.hearing_disabled : Icons.hearing),
        ),
      ],
    );
  }
}
```

```dart
// lib/features/song/song_arranger_timeline.dart
class SongArrangerTimeline extends ConsumerWidget {
  final int measureTicks;
  final int? currentPlaybackTick;

  const SongArrangerTimeline({
    super.key,
    required this.measureTicks,
    required this.currentPlaybackTick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songProjectProvider);
    final orderedTracks = [...project.tracks]..sort((a, b) => a.order.compareTo(b.order));

    return ListView.builder(
      itemCount: orderedTracks.length,
      itemBuilder: (context, index) {
        final track = orderedTracks[index];
        return _TrackLaneRow(track: track, currentPlaybackTick: currentPlaybackTick);
      },
    );
  }
}
```

- [ ] **Step 5: Re-run the Song-screen tests**

Run: `flutter test test/features/song/song_screen_test.dart`

Expected: PASS

- [ ] **Step 6: Review accessibility and layout basics**

Run:

- `dart analyze lib/features/song/song_screen.dart lib/features/song/song_arranger_timeline.dart lib/features/song/song_track_header.dart lib/main.dart`

Expected: PASS

Review focus:

- touch targets for track controls
- compact vs. wide layout behavior
- readable text and button labels

- [ ] **Step 7: Commit the task**

```bash
git add \
  lib/features/song/song_feature.dart \
  lib/features/song/song_screen.dart \
  lib/features/song/song_arranger_timeline.dart \
  lib/features/song/song_track_header.dart \
  lib/main.dart \
  test/features/song/song_screen_test.dart
git commit -m "feat: add song tab and arranger shell"
```

---

## Task 7: Note-Pattern Bridge And Isolated Piano-Roll Editor Host

**Owner:** `state-architect`

**Required reviewers after implementation:** `code-quality`, `accessibility-ux`

**Files:**

- Create: `lib/schema/rules/song_pattern_bridge_rules.dart`
- Create: `lib/features/song/song_pattern_editor_launcher.dart`
- Create: `lib/features/song/song_note_pattern_editor.dart`
- Modify: `lib/features/song/song_arranger_timeline.dart`
- Test: `test/schema/rules/song_pattern_bridge_rules_test.dart`
- Test: `test/features/song/song_note_pattern_editor_test.dart`

- [ ] **Step 1: Write the failing bridge tests**

```dart
// test/schema/rules/song_pattern_bridge_rules_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_pattern_bridge_rules.dart' as rules;

void main() {
  test('pianoRollStateFromNotePattern preserves notes and range', () {
    const pattern = NotePattern(
      id: 'pattern1',
      name: 'Lead',
      lengthTicks: 16,
      notes: [
        NotePatternNote(id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 2,
      highlightedNotes: ['C'],
    );

    final state = rules.pianoRollStateFromNotePattern(
      pattern,
      tempo: 120,
      timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    );

    expect(state.notes.single.midiNote, 60);
    expect(state.snapTicks, 2);
    expect(state.highlightedNotes, ['C']);
  });

  test('notePatternFromPianoRollState strips derived pitch fields', () {
    final state = PianoRollState(
      config: const PianoRollConfig(
        tempo: 120,
        key: null,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 1,
      ),
      notes: const [
        PianoRollNote(
          id: 'n1',
          midiNote: 64,
          pitchClass: 'E',
          noteWithOctave: 'E4',
          startTick: 2,
          durationTicks: 6,
        ),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      selectedNoteIds: <String>{},
      snapTicks: 4,
      highlightedNotes: ['E'],
      latestImportedRange: null,
    );

    final pattern = rules.notePatternFromPianoRollState(
      state,
      patternId: 'pattern2',
      patternName: 'Converted',
    );

    expect(pattern.notes.single.midiNote, 64);
    expect(pattern.notes.single.startTick, 2);
    expect(pattern.notes.single.durationTicks, 6);
    expect(pattern.lengthTicks, 8);
  });
}
```

- [ ] **Step 2: Run the bridge tests and confirm they fail**

Run:

- `flutter test test/schema/rules/song_pattern_bridge_rules_test.dart`
- `flutter test test/features/song/song_note_pattern_editor_test.dart`

Expected: FAIL with missing bridge rules and note editor widgets.

- [ ] **Step 3: Add the pure bridge layer**

```dart
// lib/schema/rules/song_pattern_bridge_rules.dart
import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'piano_roll_rules.dart' as piano_roll_rules;

PianoRollState pianoRollStateFromNotePattern(
  NotePattern pattern, {
  required int tempo,
  required TimeSignature timeSignature,
}) {
  return PianoRollState(
    config: PianoRollConfig(
      tempo: tempo,
      key: null,
      timeSignature: timeSignature,
      totalMeasures: (pattern.lengthTicks / piano_roll_rules.ticksPerMeasure(timeSignature)).ceil().clamp(1, 32),
    ),
    notes: [
      for (final note in pattern.notes)
        PianoRollNote(
          id: note.id,
          midiNote: note.midiNote,
          pitchClass: piano_roll_rules.midiToPitchClass(note.midiNote),
          noteWithOctave: piano_roll_rules.midiToNoteWithOctave(note.midiNote),
          startTick: note.startTick,
          durationTicks: note.durationTicks,
        ),
    ],
    pitchRangeStart: pattern.pitchRangeStart,
    pitchRangeEnd: pattern.pitchRangeEnd,
    selectedColumnTick: null,
    selectedNoteIds: const <String>{},
    snapTicks: pattern.snapTicks,
    highlightedNotes: List<String>.from(pattern.highlightedNotes),
    latestImportedRange: null,
  );
}

NotePattern notePatternFromPianoRollState(
  PianoRollState state, {
  required String patternId,
  required String patternName,
}) {
  final furthestEndTick = state.notes.isEmpty
      ? piano_roll_rules.ticksPerMeasure(state.config.timeSignature)
      : state.notes
            .map((note) => note.startTick + note.durationTicks)
            .reduce((a, b) => a > b ? a : b);
  return NotePattern(
    id: patternId,
    name: patternName,
    lengthTicks: furthestEndTick,
    notes: [
      for (final note in state.notes)
        NotePatternNote(
          id: note.id,
          midiNote: note.midiNote,
          startTick: note.startTick,
          durationTicks: note.durationTicks,
        ),
    ],
    pitchRangeStart: state.pitchRangeStart,
    pitchRangeEnd: state.pitchRangeEnd,
    snapTicks: state.snapTicks,
    highlightedNotes: List<String>.from(state.highlightedNotes),
  );
}
```

- [ ] **Step 4: Add the isolated note editor host**

```dart
// lib/features/song/song_note_pattern_editor.dart
class SongNotePatternEditor extends ConsumerStatefulWidget {
  final String clipId;
  final String patternId;

  const SongNotePatternEditor({
    super.key,
    required this.clipId,
    required this.patternId,
  });

  @override
  ConsumerState<SongNotePatternEditor> createState() =>
      _SongNotePatternEditorState();
}

class _SongNotePatternEditorState extends ConsumerState<SongNotePatternEditor> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    final song = ref.read(songProjectProvider);
    final pattern = song.notePatterns.firstWhere((p) => p.id == widget.patternId);
    final seedState = bridge_rules.pianoRollStateFromNotePattern(
      pattern,
      tempo: song.config.tempo,
      timeSignature: song.config.timeSignature,
    );

    _container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(() => SeededPianoRollNotifier(seedState)),
      ],
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: _SongNotePatternEditorScaffold(
        title: 'Edit Pattern',
        onSave: _handleSave,
      ),
    );
  }
}

class SeededPianoRollNotifier extends PianoRollNotifier {
  SeededPianoRollNotifier(this.seedState);

  final PianoRollState seedState;

  @override
  PianoRollState build() => seedState;
}

class _SongNotePatternEditorScaffold extends ConsumerWidget {
  final String title;
  final VoidCallback onSave;

  const _SongNotePatternEditorScaffold({
    required this.title,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: onSave,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: const [
          Expanded(child: PianoRollGrid()),
          PianoRollDetectionPanel(),
        ],
      ),
    );
  }
}
```

The save flow must:

- convert scoped `PianoRollState` back into a `NotePattern`
- call `songProjectProvider.notifier.applyNotePattern(...)`
- block save if linked clip spans would overlap after the length change
- allow `Make unique` before saving if the user wants to isolate the edit

- [ ] **Step 5: Wire note-clip taps to the editor launcher**

```dart
// lib/features/song/song_pattern_editor_launcher.dart
Future<void> openClipEditor(
  BuildContext context,
  WidgetRef ref,
  SongClipInstance clip,
) {
  if (clip.patternType == SongPatternType.note) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SongNotePatternEditor(
          clipId: clip.id,
          patternId: clip.patternId,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => DrumMachineEditor(
      clipId: clip.id,
      patternId: clip.patternId,
    ),
  );
}
```

- [ ] **Step 6: Re-run the targeted note-editor tests**

Run:

- `flutter test test/schema/rules/song_pattern_bridge_rules_test.dart`
- `flutter test test/features/song/song_note_pattern_editor_test.dart`

Expected: PASS

- [ ] **Step 7: Commit the task**

```bash
git add \
  lib/schema/rules/song_pattern_bridge_rules.dart \
  lib/features/song/song_pattern_editor_launcher.dart \
  lib/features/song/song_note_pattern_editor.dart \
  lib/features/song/song_arranger_timeline.dart \
  test/schema/rules/song_pattern_bridge_rules_test.dart \
  test/features/song/song_note_pattern_editor_test.dart
git commit -m "feat: add isolated note pattern editor for song clips"
```

---

## Task 8: Drum-Machine Editor And Clip-Edit Integration

**Owner:** `instrument-renderer`

**Required reviewers after implementation:** `code-quality`, `accessibility-ux`

**Files:**

- Create: `lib/features/song/drum_machine_editor.dart`
- Modify: `lib/store/song_project_store.dart`
- Test: `test/features/song/drum_machine_editor_test.dart`

- [ ] **Step 1: Write the failing drum-editor widget tests**

```dart
// test/features/song/drum_machine_editor_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  testWidgets('DrumMachineEditor renders default lanes and toggles steps', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songProjectProvider.notifier);
    final trackId = notifier.addTrack(SongTrackType.drum);
    final clipId = notifier.createEmptyDrumPatternClip(trackId: trackId, startTick: 0);
    final patternId = container.read(songProjectProvider).clips
        .firstWhere((clip) => clip.id == clipId)
        .patternId;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DrumMachineEditor(clipId: clipId, patternId: patternId),
        ),
      ),
    );

    expect(find.text('Kick'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the drum-editor tests and confirm they fail**

Run: `flutter test test/features/song/drum_machine_editor_test.dart`

Expected: FAIL with missing `DrumMachineEditor`.

- [ ] **Step 3: Build the drum-machine editor UI**

```dart
// lib/features/song/drum_machine_editor.dart
class DrumMachineEditor extends ConsumerWidget {
  final String clipId;
  final String patternId;

  const DrumMachineEditor({
    super.key,
    required this.clipId,
    required this.patternId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(songProjectProvider);
    final pattern = song.drumPatterns.firstWhere((p) => p.id == patternId);
    final usedCount = song.clips.where((clip) => clip.patternId == patternId).length;
    final stepCount = pattern.lengthTicks;

    return Scaffold(
      appBar: AppBar(
        title: Text(pattern.name),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(songProjectProvider.notifier).makeClipPatternUnique(clipId),
            child: const Text('Make unique'),
          ),
        ],
      ),
      body: Column(
        children: [
          Text('Used in $usedCount clips'),
          Expanded(
            child: ListView(
              children: [
                for (final lane in pattern.lanes)
                  _DrumLaneRow(
                    lane: lane,
                    stepCount: stepCount,
                    onToggle: (tick) {
                      ref.read(songProjectProvider.notifier).toggleDrumStep(
                        patternId: patternId,
                        laneId: lane.laneId,
                        tick: tick,
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add the store mutation for drum-step toggling**

```dart
// add to SongProjectNotifier
void toggleDrumStep({
  required String patternId,
  required DrumLaneId laneId,
  required int tick,
}) {
  state = state.copyWith(
    drumPatterns: state.drumPatterns.map((pattern) {
      if (pattern.id != patternId) return pattern;
      return pattern.copyWith(
        lanes: pattern.lanes.map((lane) {
          if (lane.laneId != laneId) return lane;
          final nextTicks = lane.activeTicks.toSet();
          if (!nextTicks.add(tick)) {
            nextTicks.remove(tick);
          }
          final ordered = nextTicks.toList()..sort();
          return lane.copyWith(activeTicks: ordered);
        }).toList(),
      );
    }).toList(),
  );
}
```

- [ ] **Step 5: Re-run the drum-editor tests**

Run: `flutter test test/features/song/drum_machine_editor_test.dart`

Expected: PASS

- [ ] **Step 6: Commit the task**

```bash
git add \
  lib/features/song/drum_machine_editor.dart \
  lib/store/song_project_store.dart \
  test/features/song/drum_machine_editor_test.dart
git commit -m "feat: add drum machine editor for song clips"
```

---

## Task 9: Docs, Review Sweep, And Full Verification

**Owner:** `state-architect`

**Required reviewers after implementation:** `code-quality`, `accessibility-ux`

**Files:**

- Modify: `docs/save_system.md`
- Modify: `docs/piano_roll.md`
- Create: `docs/song_workspace.md`

- [ ] **Step 1: Update product docs**

Update `docs/save_system.md` with:

- `SongProjectSnapshot`
- Song save/load behavior
- Song-specific preview semantics

Update `docs/piano_roll.md` with:

- standalone Roll remains separate from Song workspace
- note-pattern editor reuse inside Song
- what state belongs to standalone Roll vs. Song-scoped note editing

Add a dedicated user-facing doc:

```markdown
# Song Workspace

- Song tab purpose
- Track types
- Pattern reuse
- Make unique
- Import flows
- Save/load behavior
```

- [ ] **Step 2: Run formatter on all changed paths**

Run:

- `dart format lib/models/song_project.dart`
- `dart format lib/models/song_playback.dart`
- `dart format lib/schema/rules/song_rules.dart`
- `dart format lib/schema/rules/song_import_rules.dart`
- `dart format lib/schema/rules/song_playback_rules.dart`
- `dart format lib/schema/rules/song_pattern_bridge_rules.dart`
- `dart format lib/store/song_project_store.dart`
- `dart format lib/store/song_playback_store.dart`
- `dart format lib/features/song`
- `dart format lib/models/save_system.dart`
- `dart format lib/ui/save_browser_panel.dart`
- `dart format lib/utils/note_player.dart`
- `dart format lib/main.dart`
- `dart format test/schema/rules`
- `dart format test/store`
- `dart format test/features/song`

Expected: formatting completes with no errors.

- [ ] **Step 3: Run the targeted test matrix**

Run:

- `flutter test test/schema/rules/song_rules_test.dart`
- `flutter test test/schema/rules/song_import_rules_test.dart`
- `flutter test test/schema/rules/song_playback_rules_test.dart`
- `flutter test test/schema/rules/song_pattern_bridge_rules_test.dart`
- `flutter test test/store/song_project_store_test.dart`
- `flutter test test/store/song_playback_store_test.dart`
- `flutter test test/store/save_system_store_test.dart`
- `flutter test test/features/song/song_screen_test.dart`
- `flutter test test/features/song/song_save_panel_test.dart`
- `flutter test test/features/song/song_note_pattern_editor_test.dart`
- `flutter test test/features/song/drum_machine_editor_test.dart`

Expected: PASS

- [ ] **Step 4: Run full analyzer and web build**

Run:

- `flutter analyze`
- `flutter build web --release`

Expected: PASS

- [ ] **Step 5: Perform compact and wide viewport verification**

Use the Browser or simulator tooling available in the environment to verify:

- compact portrait layout
- wide/landscape layout
- track controls reachable without overlap
- note editor opens and closes cleanly
- drum editor grid stays tappable

Capture any residual layout risk in the final report if the environment prevents manual verification.

- [ ] **Step 6: Run the review sweep**

Checklist:

- `code-quality`
  - analyzer cleanliness
  - dead code
  - naming and repo conventions
- `accessibility-ux`
  - track header tap targets
  - clip affordances
  - modal editor escape paths
  - readable state labels for mute/solo and `Make unique`

- [ ] **Step 7: Commit the task**

```bash
git add \
  docs/save_system.md \
  docs/piano_roll.md \
  docs/song_workspace.md
git commit -m "docs: describe song workspace and pattern arrangement"
```

---

## Final Completion Checklist

- `Song` tab exists in bottom navigation.
- `SongProject` is the canonical arrangement model.
- `SongProjectSnapshot` is persisted through the shared save system.
- Note and drum tracks can be created.
- Note and drum clips can be created, moved, duplicated, deleted, and opened.
- Pattern reuse works across multiple clip instances.
- `Make unique` clones one pattern and relinks one clip only.
- Import works from `PianoRollSnapshot`, `PianoSnapshot`, and `FretboardSnapshot`.
- Song playback expands clips to absolute note and drum events.
- Drum voices play through `NotePlayer`.
- Note-pattern editing uses an isolated piano-roll session and does not mutate the standalone Roll tab.
- Same-track clip overlap is prevented.
- Pattern-length changes are validated across all linked instances.
- Targeted tests pass.
- `flutter analyze` passes.
- `flutter build web --release` passes.

---

## Suggested Orchestrator Handoff

After this plan is approved, run it with a task-by-task orchestration flow:

1. Dispatch one specialist per task.
2. Require tests to fail before implementation and pass after implementation.
3. Require review after every task before continuing.
4. Keep the design spec `docs/superpowers/specs/2026-05-27-song-workspace-pattern-daw-design.md` open as the product source of truth.
