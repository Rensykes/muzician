/// Shared arrangement content: note patterns, drum patterns and audio assets.
library;

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

// ── NotePatternNote ───────────────────────────────────────────────────────────

class NotePatternNote {
  final String id;
  final int midiNote;
  final int startTick;
  final int durationTicks;
  final int onsetOffsetMs;
  final int durationOffsetMs;

  const NotePatternNote({
    required this.id,
    required this.midiNote,
    required this.startTick,
    required this.durationTicks,
    this.onsetOffsetMs = 0,
    this.durationOffsetMs = 0,
  });

  NotePatternNote copyWith({
    String? id,
    int? midiNote,
    int? startTick,
    int? durationTicks,
    int? onsetOffsetMs,
    int? durationOffsetMs,
  }) => NotePatternNote(
    id: id ?? this.id,
    midiNote: midiNote ?? this.midiNote,
    startTick: startTick ?? this.startTick,
    durationTicks: durationTicks ?? this.durationTicks,
    onsetOffsetMs: onsetOffsetMs ?? this.onsetOffsetMs,
    durationOffsetMs: durationOffsetMs ?? this.durationOffsetMs,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'midiNote': midiNote,
    'startTick': startTick,
    'durationTicks': durationTicks,
    if (onsetOffsetMs != 0) 'onsetOffsetMs': onsetOffsetMs,
    if (durationOffsetMs != 0) 'durationOffsetMs': durationOffsetMs,
  };

  factory NotePatternNote.fromJson(Map<String, dynamic> json) =>
      NotePatternNote(
        id: json['id'] as String,
        midiNote: json['midiNote'] as int,
        startTick: json['startTick'] as int,
        durationTicks: json['durationTicks'] as int,
        onsetOffsetMs: json['onsetOffsetMs'] as int? ?? 0,
        durationOffsetMs: json['durationOffsetMs'] as int? ?? 0,
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

// ── AudioAsset ────────────────────────────────────────────────────────────────

class AudioAsset {
  final String id;
  final int durationMs;
  final int sampleRate;
  final int channels;
  final String format; // 'wav' | 'mp3' | 'm4a'
  final List<int> peaks;
  final String sourceLabel;

  const AudioAsset({
    required this.id,
    required this.durationMs,
    required this.sampleRate,
    required this.channels,
    required this.format,
    required this.peaks,
    required this.sourceLabel,
  });

  AudioAsset copyWith({
    String? id,
    int? durationMs,
    int? sampleRate,
    int? channels,
    String? format,
    List<int>? peaks,
    String? sourceLabel,
  }) => AudioAsset(
    id: id ?? this.id,
    durationMs: durationMs ?? this.durationMs,
    sampleRate: sampleRate ?? this.sampleRate,
    channels: channels ?? this.channels,
    format: format ?? this.format,
    peaks: peaks ?? this.peaks,
    sourceLabel: sourceLabel ?? this.sourceLabel,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'durationMs': durationMs,
    'sampleRate': sampleRate,
    'channels': channels,
    'format': format,
    'peaks': peaks,
    'sourceLabel': sourceLabel,
  };

  factory AudioAsset.fromJson(Map<String, dynamic> json) => AudioAsset(
    id: json['id'] as String,
    durationMs: json['durationMs'] as int,
    sampleRate: json['sampleRate'] as int,
    channels: json['channels'] as int,
    format: json['format'] as String,
    peaks: List<int>.from(json['peaks'] as List),
    sourceLabel: json['sourceLabel'] as String,
  );
}
