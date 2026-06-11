/// Song Project Domain Models
/// Immutable data types for song-level arrangement: config, tracks, clips,
/// note patterns, and drum patterns.
library;

import 'piano_roll.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum SongTrackType { note, drum, audio }

enum SongPatternType { note, drum, audio }

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
  final String? scaleRoot;
  final String? scaleName;

  const SongProjectConfig({
    required this.tempo,
    required this.timeSignature,
    required this.totalMeasures,
    this.scaleRoot,
    this.scaleName,
  });

  SongProjectConfig copyWith({
    int? tempo,
    TimeSignature? timeSignature,
    int? totalMeasures,
    String? Function()? scaleRoot,
    String? Function()? scaleName,
  }) => SongProjectConfig(
    tempo: tempo ?? this.tempo,
    timeSignature: timeSignature ?? this.timeSignature,
    totalMeasures: totalMeasures ?? this.totalMeasures,
    scaleRoot: scaleRoot != null ? scaleRoot() : this.scaleRoot,
    scaleName: scaleName != null ? scaleName() : this.scaleName,
  );

  Map<String, dynamic> toJson() => {
    'tempo': tempo,
    'timeSignature': timeSignature.toJson(),
    'totalMeasures': totalMeasures,
    if (scaleRoot != null) 'scaleRoot': scaleRoot,
    if (scaleName != null) 'scaleName': scaleName,
  };

  factory SongProjectConfig.fromJson(Map<String, dynamic> json) =>
      SongProjectConfig(
        tempo: json['tempo'] as int,
        timeSignature: TimeSignature.fromJson(
          json['timeSignature'] as Map<String, dynamic>,
        ),
        totalMeasures: json['totalMeasures'] as int,
        scaleRoot: json['scaleRoot'] as String?,
        scaleName: json['scaleName'] as String?,
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
  final double volume; // 0.0–1.0 playback gain

  const SongTrack({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
    this.isMuted = false,
    this.isSolo = false,
    this.volume = 1.0,
  });

  SongTrack copyWith({
    String? id,
    String? name,
    SongTrackType? type,
    int? order,
    bool? isMuted,
    bool? isSolo,
    double? volume,
  }) => SongTrack(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    order: order ?? this.order,
    isMuted: isMuted ?? this.isMuted,
    isSolo: isSolo ?? this.isSolo,
    volume: volume ?? this.volume,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'order': order,
    'isMuted': isMuted,
    'isSolo': isSolo,
    'volume': volume,
  };

  factory SongTrack.fromJson(Map<String, dynamic> json) => SongTrack(
    id: json['id'] as String,
    name: json['name'] as String,
    type: SongTrackType.values.firstWhere((e) => e.name == json['type']),
    order: json['order'] as int,
    isMuted: json['isMuted'] as bool? ?? false,
    isSolo: json['isSolo'] as bool? ?? false,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
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

// ── AudioClipPattern ──────────────────────────────────────────────────────────

class AudioClipPattern {
  final String id;
  final String name;
  final String assetId;

  const AudioClipPattern({
    required this.id,
    required this.name,
    required this.assetId,
  });

  AudioClipPattern copyWith({String? id, String? name, String? assetId}) =>
      AudioClipPattern(
        id: id ?? this.id,
        name: name ?? this.name,
        assetId: assetId ?? this.assetId,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'assetId': assetId};

  factory AudioClipPattern.fromJson(Map<String, dynamic> json) =>
      AudioClipPattern(
        id: json['id'] as String,
        name: json['name'] as String,
        assetId: json['assetId'] as String,
      );
}

// ── SongProject ───────────────────────────────────────────────────────────────

class SongProject {
  final SongProjectConfig config;
  final List<SongTrack> tracks;
  final List<SongClipInstance> clips;
  final List<NotePattern> notePatterns;
  final List<DrumPattern> drumPatterns;
  final List<AudioAsset> audioAssets;
  final List<AudioClipPattern> audioPatterns;

  const SongProject({
    required this.config,
    required this.tracks,
    required this.clips,
    required this.notePatterns,
    required this.drumPatterns,
    this.audioAssets = const [],
    this.audioPatterns = const [],
  });

  SongProject copyWith({
    SongProjectConfig? config,
    List<SongTrack>? tracks,
    List<SongClipInstance>? clips,
    List<NotePattern>? notePatterns,
    List<DrumPattern>? drumPatterns,
    List<AudioAsset>? audioAssets,
    List<AudioClipPattern>? audioPatterns,
  }) => SongProject(
    config: config ?? this.config,
    tracks: tracks ?? this.tracks,
    clips: clips ?? this.clips,
    notePatterns: notePatterns ?? this.notePatterns,
    drumPatterns: drumPatterns ?? this.drumPatterns,
    audioAssets: audioAssets ?? this.audioAssets,
    audioPatterns: audioPatterns ?? this.audioPatterns,
  );

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'clips': clips.map((c) => c.toJson()).toList(),
    'notePatterns': notePatterns.map((p) => p.toJson()).toList(),
    'drumPatterns': drumPatterns.map((p) => p.toJson()).toList(),
    'audioAssets': audioAssets.map((a) => a.toJson()).toList(),
    'audioPatterns': audioPatterns.map((p) => p.toJson()).toList(),
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
    audioAssets: (json['audioAssets'] as List<dynamic>? ?? const [])
        .map((a) => AudioAsset.fromJson(a as Map<String, dynamic>))
        .toList(),
    audioPatterns: (json['audioPatterns'] as List<dynamic>? ?? const [])
        .map((p) => AudioClipPattern.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}
