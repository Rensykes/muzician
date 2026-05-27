/// Song Project Domain Models
/// Immutable data types for song-level arrangement: config, tracks, clips,
/// note patterns, and drum patterns.
library;

import 'piano_roll.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

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

// ── SongProjectConfig ─────────────────────────────────────────────────────────

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

// ── SongTrack ─────────────────────────────────────────────────────────────────

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
    String? id,
    String? name,
    SongTrackType? type,
    int? order,
    bool? isMuted,
    bool? isSolo,
  }) => SongTrack(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
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
    type: SongTrackType.values.firstWhere((e) => e.name == json['type']),
    order: json['order'] as int,
    isMuted: json['isMuted'] as bool? ?? false,
    isSolo: json['isSolo'] as bool? ?? false,
  );
}

// ── SongClipInstance ──────────────────────────────────────────────────────────

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
    String? id,
    String? trackId,
    String? patternId,
    SongPatternType? patternType,
    int? startTick,
  }) => SongClipInstance(
    id: id ?? this.id,
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
          (e) => e.name == json['patternType'],
        ),
        startTick: json['startTick'] as int,
      );
}

// ── NotePatternNote ───────────────────────────────────────────────────────────

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

  NotePatternNote copyWith({
    String? id,
    int? midiNote,
    int? startTick,
    int? durationTicks,
  }) => NotePatternNote(
    id: id ?? this.id,
    midiNote: midiNote ?? this.midiNote,
    startTick: startTick ?? this.startTick,
    durationTicks: durationTicks ?? this.durationTicks,
  );

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

// ── NotePattern ───────────────────────────────────────────────────────────────

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
    String? id,
    String? name,
    int? lengthTicks,
    List<NotePatternNote>? notes,
    int? pitchRangeStart,
    int? pitchRangeEnd,
    int? snapTicks,
    List<String>? highlightedNotes,
  }) => NotePattern(
    id: id ?? this.id,
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
    'notes': notes.map((n) => n.toJson()).toList(),
    'pitchRangeStart': pitchRangeStart,
    'pitchRangeEnd': pitchRangeEnd,
    'snapTicks': snapTicks,
    'highlightedNotes': highlightedNotes,
  };

  factory NotePattern.fromJson(Map<String, dynamic> json) => NotePattern(
    id: json['id'] as String,
    name: json['name'] as String,
    lengthTicks: json['lengthTicks'] as int,
    notes: (json['notes'] as List<dynamic>)
        .map((n) => NotePatternNote.fromJson(n as Map<String, dynamic>))
        .toList(),
    pitchRangeStart: json['pitchRangeStart'] as int,
    pitchRangeEnd: json['pitchRangeEnd'] as int,
    snapTicks: json['snapTicks'] as int,
    highlightedNotes: List<String>.from(json['highlightedNotes'] as List),
  );
}

// ── DrumLaneSequence ──────────────────────────────────────────────────────────

class DrumLaneSequence {
  final DrumLaneId laneId;
  final List<int> activeTicks;

  const DrumLaneSequence({required this.laneId, required this.activeTicks});

  DrumLaneSequence copyWith({DrumLaneId? laneId, List<int>? activeTicks}) =>
      DrumLaneSequence(
        laneId: laneId ?? this.laneId,
        activeTicks: activeTicks ?? this.activeTicks,
      );

  Map<String, dynamic> toJson() => {
    'laneId': laneId.name,
    'activeTicks': activeTicks,
  };

  factory DrumLaneSequence.fromJson(Map<String, dynamic> json) =>
      DrumLaneSequence(
        laneId: DrumLaneId.values.firstWhere((e) => e.name == json['laneId']),
        activeTicks: List<int>.from(json['activeTicks'] as List),
      );
}

// ── DrumPattern ───────────────────────────────────────────────────────────────

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
    String? id,
    String? name,
    int? lengthTicks,
    List<DrumLaneSequence>? lanes,
  }) => DrumPattern(
    id: id ?? this.id,
    name: name ?? this.name,
    lengthTicks: lengthTicks ?? this.lengthTicks,
    lanes: lanes ?? this.lanes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lengthTicks': lengthTicks,
    'lanes': lanes.map((l) => l.toJson()).toList(),
  };

  factory DrumPattern.fromJson(Map<String, dynamic> json) => DrumPattern(
    id: json['id'] as String,
    name: json['name'] as String,
    lengthTicks: json['lengthTicks'] as int,
    lanes: (json['lanes'] as List<dynamic>)
        .map((l) => DrumLaneSequence.fromJson(l as Map<String, dynamic>))
        .toList(),
  );
}

// ── SongProject ───────────────────────────────────────────────────────────────

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
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'clips': clips.map((c) => c.toJson()).toList(),
    'notePatterns': notePatterns.map((p) => p.toJson()).toList(),
    'drumPatterns': drumPatterns.map((p) => p.toJson()).toList(),
  };

  factory SongProject.fromJson(Map<String, dynamic> json) => SongProject(
    config: SongProjectConfig.fromJson(json['config'] as Map<String, dynamic>),
    tracks: (json['tracks'] as List<dynamic>)
        .map((t) => SongTrack.fromJson(t as Map<String, dynamic>))
        .toList(),
    clips: (json['clips'] as List<dynamic>)
        .map((c) => SongClipInstance.fromJson(c as Map<String, dynamic>))
        .toList(),
    notePatterns: (json['notePatterns'] as List<dynamic>)
        .map((p) => NotePattern.fromJson(p as Map<String, dynamic>))
        .toList(),
    drumPatterns: (json['drumPatterns'] as List<dynamic>)
        .map((p) => DrumPattern.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}
