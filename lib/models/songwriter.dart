/// Songwriter project model — section/lane/block arrangement tree.
library;

import 'piano_roll.dart' show ticksPerBeatForUnit;
import 'harmony_lane_instrument.dart';
import 'save_system.dart';
import 'song_project.dart';

enum SongLaneKind { harmony, save, drum, audio, melody, guitarStrum }

SongLaneKind _laneKindFromName(String? raw) {
  for (final v in SongLaneKind.values) {
    if (v.name == raw) return v;
  }
  return SongLaneKind.save;
}

enum AudioFitMode { loop, oneShot, stretch }

AudioFitMode _fitModeFromName(String? raw) {
  for (final v in AudioFitMode.values) {
    if (v.name == raw) return v;
  }
  return AudioFitMode.loop;
}

/// A silent, beat-quantized chord annotation inside an [AudioClip].
///
/// Positions are clip-local ticks (multiples of the config's ticksPerBeat).
/// Carries either a harmony pick (chord* fields) or a [saveId] reference.
class ChordSegment {
  final String id;
  final int startTick;
  final int spanTicks;
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;
  final String? saveId;

  const ChordSegment({
    required this.id,
    required this.startTick,
    required this.spanTicks,
    this.chordSymbol,
    this.chordQuality,
    this.chordRootPc,
    this.chordNotes = const [],
    this.romanNumeral,
    this.saveId,
  });

  ChordSegment copyWith({
    int? startTick,
    int? spanTicks,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String>? chordNotes,
    String? romanNumeral,
    String? saveId,
    bool clearRomanNumeral = false,
    bool clearSaveId = false,
  }) => ChordSegment(
    id: id,
    startTick: startTick ?? this.startTick,
    spanTicks: spanTicks ?? this.spanTicks,
    chordSymbol: chordSymbol ?? this.chordSymbol,
    chordQuality: chordQuality ?? this.chordQuality,
    chordRootPc: chordRootPc ?? this.chordRootPc,
    chordNotes: chordNotes ?? this.chordNotes,
    romanNumeral: clearRomanNumeral
        ? null
        : (romanNumeral ?? this.romanNumeral),
    saveId: clearSaveId ? null : (saveId ?? this.saveId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTick': startTick,
    'spanTicks': spanTicks,
    'chordSymbol': chordSymbol,
    'chordQuality': chordQuality,
    'chordRootPc': chordRootPc,
    'chordNotes': chordNotes,
    'romanNumeral': romanNumeral,
    'saveId': saveId,
  };

  factory ChordSegment.fromJson(Map<String, dynamic> json) => ChordSegment(
    id: json['id'] as String,
    startTick: json['startTick'] as int? ?? 0,
    spanTicks: json['spanTicks'] as int? ?? 0,
    chordSymbol: json['chordSymbol'] as String?,
    chordQuality: json['chordQuality'] as String?,
    chordRootPc: json['chordRootPc'] as int?,
    chordNotes:
        (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
        const [],
    romanNumeral: json['romanNumeral'] as String?,
    saveId: json['saveId'] as String?,
  );
}

/// Content for an audio-lane block: a reference to a recorded/imported
/// [AudioAsset] plus how it adapts to its bar span.
///
/// Songwriter-specific and distinct from `AudioClipPattern` in the Song session
/// model — this type carries [fitMode] and [ChordSegment] annotations.
class AudioClip {
  final String id;
  final String assetId;

  /// Used region of the source asset, in ms. `trimEndMs == 0` means "no
  /// end-trim" (play to the natural end); creators set it to the asset
  /// duration. Mirrors `AudioClipPattern`'s trim convention.
  final int trimStartMs;
  final int trimEndMs;
  final AudioFitMode fitMode;
  final String? stretchedAssetId;
  final List<ChordSegment> segments;

  const AudioClip({
    required this.id,
    required this.assetId,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.fitMode = AudioFitMode.loop,
    this.stretchedAssetId,
    this.segments = const [],
  });

  AudioClip copyWith({
    String? assetId,
    int? trimStartMs,
    int? trimEndMs,
    AudioFitMode? fitMode,
    String? stretchedAssetId,
    List<ChordSegment>? segments,
    bool clearStretchedAssetId = false,
  }) => AudioClip(
    id: id,
    assetId: assetId ?? this.assetId,
    trimStartMs: trimStartMs ?? this.trimStartMs,
    trimEndMs: trimEndMs ?? this.trimEndMs,
    fitMode: fitMode ?? this.fitMode,
    stretchedAssetId: clearStretchedAssetId
        ? null
        : (stretchedAssetId ?? this.stretchedAssetId),
    segments: segments ?? this.segments,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'assetId': assetId,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'fitMode': fitMode.name,
    'stretchedAssetId': stretchedAssetId,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
    id: json['id'] as String,
    assetId: json['assetId'] as String,
    trimStartMs: json['trimStartMs'] as int? ?? 0,
    trimEndMs: json['trimEndMs'] as int? ?? 0,
    fitMode: _fitModeFromName(json['fitMode'] as String?),
    stretchedAssetId: json['stretchedAssetId'] as String?,
    segments:
        (json['segments'] as List?)
            ?.map((s) => ChordSegment.fromJson(s as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

enum GuitarStrumDirection { down, up }

class GuitarStrumEvent {
  final int tick;
  final GuitarStrumDirection direction;

  const GuitarStrumEvent({required this.tick, required this.direction});

  GuitarStrumEvent copyWith({int? tick, GuitarStrumDirection? direction}) =>
      GuitarStrumEvent(
        tick: tick ?? this.tick,
        direction: direction ?? this.direction,
      );

  Map<String, dynamic> toJson() => {'tick': tick, 'direction': direction.name};

  factory GuitarStrumEvent.fromJson(Map<String, dynamic> json) {
    final rawDirection = json['direction'] as String?;
    return GuitarStrumEvent(
      tick: json['tick'] as int? ?? 0,
      direction: GuitarStrumDirection.values.firstWhere(
        (direction) => direction.name == rawDirection,
        orElse: () => GuitarStrumDirection.down,
      ),
    );
  }
}

class GuitarStrumPattern {
  final String id;
  final String name;
  final int lengthTicks;
  final List<GuitarStrumEvent> events;

  const GuitarStrumPattern({
    required this.id,
    required this.name,
    required this.lengthTicks,
    this.events = const [],
  });

  GuitarStrumPattern copyWith({
    String? id,
    String? name,
    int? lengthTicks,
    List<GuitarStrumEvent>? events,
  }) => GuitarStrumPattern(
    id: id ?? this.id,
    name: name ?? this.name,
    lengthTicks: lengthTicks ?? this.lengthTicks,
    events: events ?? this.events,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lengthTicks': lengthTicks,
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory GuitarStrumPattern.fromJson(Map<String, dynamic> json) =>
      GuitarStrumPattern(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Strum Pattern',
        lengthTicks: json['lengthTicks'] as int? ?? 16,
        events:
            (json['events'] as List?)
                ?.map(
                  (event) =>
                      GuitarStrumEvent.fromJson(event as Map<String, dynamic>),
                )
                .toList() ??
            const [],
      );
}

class SongBlock {
  final String id;
  final int startBar; // 0-based offset within the section
  final int spanBars; // width in bars

  // save-lane reference (live link into SaveSystemState.saves)
  final String? saveId;
  // non-null when "Made Unique" — detached snapshot copy
  final InstrumentSnapshot? embedded;

  // harmony-lane extras (null on save / silent blocks)
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;

  // drum-lane reference into SongwriterProjectSnapshot.drumPatterns
  final String? patternId;

  // audio-lane reference into SongwriterProjectSnapshot.audioClips
  final String? audioClipId;

  // lyric-bearing fields (any harmony / silent block can carry lyrics)
  final List<String> lyrics;
  final bool isSilent;

  const SongBlock({
    required this.id,
    required this.startBar,
    required this.spanBars,
    this.saveId,
    this.embedded,
    this.chordSymbol,
    this.chordQuality,
    this.chordRootPc,
    this.chordNotes = const [],
    this.romanNumeral,
    this.patternId,
    this.audioClipId,
    this.lyrics = const [],
    this.isSilent = false,
  });

  int get endBar => startBar + spanBars;

  SongBlock copyWith({
    int? startBar,
    int? spanBars,
    String? saveId,
    InstrumentSnapshot? embedded,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String>? chordNotes,
    String? romanNumeral,
    String? patternId,
    String? audioClipId,
    List<String>? lyrics,
    bool? isSilent,
    bool clearRomanNumeral = false,
    bool clearChordData = false,
    bool clearSaveId = false,
    bool clearEmbedded = false,
    bool clearPatternId = false,
    bool clearAudioClipId = false,
  }) => SongBlock(
    id: id,
    startBar: startBar ?? this.startBar,
    spanBars: spanBars ?? this.spanBars,
    saveId: clearSaveId ? null : (saveId ?? this.saveId),
    embedded: clearEmbedded ? null : (embedded ?? this.embedded),
    chordSymbol: clearChordData ? null : (chordSymbol ?? this.chordSymbol),
    chordQuality: clearChordData ? null : (chordQuality ?? this.chordQuality),
    chordRootPc: clearChordData ? null : (chordRootPc ?? this.chordRootPc),
    chordNotes: clearChordData ? const [] : (chordNotes ?? this.chordNotes),
    romanNumeral: clearRomanNumeral || clearChordData
        ? null
        : (romanNumeral ?? this.romanNumeral),
    patternId: clearPatternId ? null : (patternId ?? this.patternId),
    audioClipId: clearAudioClipId ? null : (audioClipId ?? this.audioClipId),
    lyrics: lyrics ?? this.lyrics,
    isSilent: isSilent ?? this.isSilent,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startBar': startBar,
    'spanBars': spanBars,
    'saveId': saveId,
    'embedded': embedded?.toJson(),
    'chordSymbol': chordSymbol,
    'chordQuality': chordQuality,
    'chordRootPc': chordRootPc,
    'chordNotes': chordNotes,
    'romanNumeral': romanNumeral,
    'patternId': patternId,
    'audioClipId': audioClipId,
    'lyrics': lyrics,
    'isSilent': isSilent,
  };

  factory SongBlock.fromJson(Map<String, dynamic> json) => SongBlock(
    id: json['id'] as String,
    startBar: json['startBar'] as int? ?? 0,
    spanBars: json['spanBars'] as int? ?? 1,
    saveId: json['saveId'] as String?,
    embedded: json['embedded'] == null
        ? null
        : InstrumentSnapshot.fromJson(json['embedded'] as Map<String, dynamic>),
    chordSymbol: json['chordSymbol'] as String?,
    chordQuality: json['chordQuality'] as String?,
    chordRootPc: json['chordRootPc'] as int?,
    chordNotes:
        (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
        const [],
    romanNumeral: json['romanNumeral'] as String?,
    patternId: json['patternId'] as String?,
    audioClipId: json['audioClipId'] as String?,
    lyrics:
        (json['lyrics'] as List?)?.map((e) => e as String).toList() ?? const [],
    isSilent: json['isSilent'] as bool? ?? false,
  );
}

class SongwriterConfig {
  final int tempo; // BPM
  final int beatsPerBar; // time-signature numerator
  final int beatUnit; // time-signature denominator
  final int? keyRoot; // pitch class 0-11, null = no key
  final String? keyScaleName; // e.g. 'major'

  const SongwriterConfig({
    required this.tempo,
    required this.beatsPerBar,
    required this.beatUnit,
    this.keyRoot,
    this.keyScaleName,
  });

  int get ticksPerBeat => ticksPerBeatForUnit(beatUnit);

  /// Ticks in one bar at this time signature.
  int get measureTicks => ticksPerBeat * beatsPerBar;

  SongwriterConfig copyWith({
    int? tempo,
    int? beatsPerBar,
    int? beatUnit,
    int? keyRoot,
    String? keyScaleName,
    bool clearKey = false,
  }) => SongwriterConfig(
    tempo: tempo ?? this.tempo,
    beatsPerBar: beatsPerBar ?? this.beatsPerBar,
    beatUnit: beatUnit ?? this.beatUnit,
    keyRoot: clearKey ? null : (keyRoot ?? this.keyRoot),
    keyScaleName: clearKey ? null : (keyScaleName ?? this.keyScaleName),
  );

  Map<String, dynamic> toJson() => {
    'tempo': tempo,
    'beatsPerBar': beatsPerBar,
    'beatUnit': beatUnit,
    'keyRoot': keyRoot,
    'keyScaleName': keyScaleName,
  };

  factory SongwriterConfig.fromJson(Map<String, dynamic> json) =>
      SongwriterConfig(
        tempo: json['tempo'] as int? ?? 120,
        beatsPerBar: json['beatsPerBar'] as int? ?? 4,
        beatUnit: json['beatUnit'] as int? ?? 4,
        keyRoot: json['keyRoot'] as int?,
        keyScaleName: json['keyScaleName'] as String?,
      );
}

class SongLane {
  final String id;
  final SongLaneKind kind;
  final String? label;
  final int order;
  final int repeat; // tiles this lane's block pattern N times
  final List<SongBlock> blocks;
  final double volume; // 0.0–1.0 playback gain
  final double pan; // -1.0 (left) .. 1.0 (right)
  final bool muted;

  /// Save or guitar-strum lane: harmony lane whose chord data drives this
  /// lane. Null resolves to the section's primary harmony lane.
  final String? anchorLaneId;

  /// Instrument used by a Harmony Lane; null for other lane kinds.
  final HarmonyLaneInstrument? harmonyInstrument;

  const SongLane({
    required this.id,
    required this.kind,
    required this.order,
    this.label,
    this.repeat = 1,
    this.blocks = const [],
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.anchorLaneId,
    this.harmonyInstrument,
  });

  SongLane copyWith({
    SongLaneKind? kind,
    String? label,
    int? order,
    int? repeat,
    List<SongBlock>? blocks,
    double? volume,
    double? pan,
    bool? muted,
    String? anchorLaneId,
    HarmonyLaneInstrument? harmonyInstrument,
    bool clearLabel = false,
    bool clearAnchorLaneId = false,
    bool clearHarmonyInstrument = false,
  }) => SongLane(
    id: id,
    kind: kind ?? this.kind,
    label: clearLabel ? null : (label ?? this.label),
    order: order ?? this.order,
    repeat: repeat ?? this.repeat,
    blocks: blocks ?? this.blocks,
    volume: volume ?? this.volume,
    pan: pan ?? this.pan,
    muted: muted ?? this.muted,
    anchorLaneId: clearAnchorLaneId
        ? null
        : (anchorLaneId ?? this.anchorLaneId),
    harmonyInstrument: clearHarmonyInstrument
        ? null
        : (harmonyInstrument ?? this.harmonyInstrument),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'order': order,
    'repeat': repeat,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'volume': volume,
    'pan': pan,
    'muted': muted,
    'anchorLaneId': anchorLaneId,
    'harmonyInstrument': harmonyInstrument?.name,
  };

  factory SongLane.fromJson(Map<String, dynamic> json) => SongLane(
    id: json['id'] as String,
    kind: _laneKindFromName(json['kind'] as String?),
    label: json['label'] as String?,
    order: json['order'] as int? ?? 0,
    repeat: json['repeat'] as int? ?? 1,
    blocks:
        (json['blocks'] as List?)
            ?.map((b) => SongBlock.fromJson(b as Map<String, dynamic>))
            .toList() ??
        const [],
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    muted: json['muted'] as bool? ?? false,
    anchorLaneId: json['anchorLaneId'] as String?,
    harmonyInstrument: HarmonyLaneInstrument.fromJson(
      json['harmonyInstrument'] as String?,
    ),
  );
}

/// Placement-free content for a Writer-native block.
///
/// Bar placement and subsequent lyric edits belong to the block placement.
/// [defaultLyrics] is only the initial lyric seed copied when the save is used
/// to create a new placement. Audio source bytes stay in SongAudioRepository;
/// this snapshot keeps the complete clip and asset metadata needed to restore
/// the reference.
class WriterBlockSnapshot extends InstrumentSnapshot {
  final SongLaneKind laneKind;
  final bool isSilent;
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;
  final List<String> defaultLyrics;
  final DrumPattern? drumPattern;
  final NotePattern? melodyPattern;
  final GuitarStrumPattern? guitarStrumPattern;
  final AudioClip? audioClip;
  final AudioAsset? audioAsset;
  final AudioAsset? stretchedAudioAsset;

  const WriterBlockSnapshot({
    required this.laneKind,
    this.isSilent = false,
    this.chordSymbol,
    this.chordQuality,
    this.chordRootPc,
    this.chordNotes = const [],
    this.romanNumeral,
    this.defaultLyrics = const [],
    this.drumPattern,
    this.melodyPattern,
    this.guitarStrumPattern,
    this.audioClip,
    this.audioAsset,
    this.stretchedAudioAsset,
  });

  @override
  String get instrument => 'writer_block';

  @override
  List<String> get selectedNotes => chordNotes;

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'writer_block',
    'instrument': instrument,
    'laneKind': laneKind.name,
    'isSilent': isSilent,
    'chordSymbol': chordSymbol,
    'chordQuality': chordQuality,
    'chordRootPc': chordRootPc,
    'chordNotes': chordNotes,
    'romanNumeral': romanNumeral,
    'defaultLyrics': defaultLyrics,
    'drumPattern': drumPattern?.toJson(),
    'melodyPattern': melodyPattern?.toJson(),
    'guitarStrumPattern': guitarStrumPattern?.toJson(),
    'audioClip': audioClip?.toJson(),
    'audioAsset': audioAsset?.toJson(),
    'stretchedAudioAsset': stretchedAudioAsset?.toJson(),
  };

  factory WriterBlockSnapshot.fromJson(
    Map<String, dynamic> json,
  ) => WriterBlockSnapshot(
    laneKind: _laneKindFromName(json['laneKind'] as String?),
    isSilent: json['isSilent'] as bool? ?? false,
    chordSymbol: json['chordSymbol'] as String?,
    chordQuality: json['chordQuality'] as String?,
    chordRootPc: json['chordRootPc'] as int?,
    chordNotes: (json['chordNotes'] as List?)?.cast<String>() ?? const [],
    romanNumeral: json['romanNumeral'] as String?,
    defaultLyrics: (json['defaultLyrics'] as List?)?.cast<String>() ?? const [],
    drumPattern: json['drumPattern'] == null
        ? null
        : DrumPattern.fromJson(json['drumPattern'] as Map<String, dynamic>),
    melodyPattern: json['melodyPattern'] == null
        ? null
        : NotePattern.fromJson(json['melodyPattern'] as Map<String, dynamic>),
    guitarStrumPattern: json['guitarStrumPattern'] == null
        ? null
        : GuitarStrumPattern.fromJson(
            json['guitarStrumPattern'] as Map<String, dynamic>,
          ),
    audioClip: json['audioClip'] == null
        ? null
        : AudioClip.fromJson(json['audioClip'] as Map<String, dynamic>),
    audioAsset: json['audioAsset'] == null
        ? null
        : AudioAsset.fromJson(json['audioAsset'] as Map<String, dynamic>),
    stretchedAudioAsset: json['stretchedAudioAsset'] == null
        ? null
        : AudioAsset.fromJson(
            json['stretchedAudioAsset'] as Map<String, dynamic>,
          ),
  );
}

class SongwriterProjectSnapshot extends InstrumentSnapshot {
  final String name;
  final SongwriterConfig config;
  final List<SongSection> sections;
  final List<DrumPattern> drumPatterns;
  final List<NotePattern> melodyPatterns;
  final List<GuitarStrumPattern> guitarStrumPatterns;
  final List<AudioAsset> audioAssets;
  final List<AudioClip> audioClips;

  const SongwriterProjectSnapshot({
    this.name = 'Untitled song',
    required this.config,
    this.sections = const [],
    this.drumPatterns = const [],
    this.melodyPatterns = const [],
    this.guitarStrumPatterns = const [],
    this.audioAssets = const [],
    this.audioClips = const [],
  });

  @override
  String get instrument => 'songwriter';

  @override
  List<String> get selectedNotes {
    final set = <String>{};
    for (final section in sections) {
      for (final lane in section.lanes) {
        for (final block in lane.blocks) {
          set.addAll(block.chordNotes);
        }
      }
    }
    for (final clip in audioClips) {
      for (final seg in clip.segments) {
        set.addAll(seg.chordNotes);
      }
    }
    return set.toList();
  }

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  SongwriterProjectSnapshot copyWith({
    String? name,
    SongwriterConfig? config,
    List<SongSection>? sections,
    List<DrumPattern>? drumPatterns,
    List<NotePattern>? melodyPatterns,
    List<GuitarStrumPattern>? guitarStrumPatterns,
    List<AudioAsset>? audioAssets,
    List<AudioClip>? audioClips,
  }) => SongwriterProjectSnapshot(
    name: name ?? this.name,
    config: config ?? this.config,
    sections: sections ?? this.sections,
    drumPatterns: drumPatterns ?? this.drumPatterns,
    melodyPatterns: melodyPatterns ?? this.melodyPatterns,
    guitarStrumPatterns: guitarStrumPatterns ?? this.guitarStrumPatterns,
    audioAssets: audioAssets ?? this.audioAssets,
    audioClips: audioClips ?? this.audioClips,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'songwriter',
    'instrument': 'songwriter',
    'name': name,
    'config': config.toJson(),
    'sections': sections.map((s) => s.toJson()).toList(),
    'drumPatterns': drumPatterns.map((p) => p.toJson()).toList(),
    'melodyPatterns': melodyPatterns.map((p) => p.toJson()).toList(),
    'guitarStrumPatterns': guitarStrumPatterns.map((p) => p.toJson()).toList(),
    'audioAssets': audioAssets.map((a) => a.toJson()).toList(),
    'audioClips': audioClips.map((c) => c.toJson()).toList(),
  };

  factory SongwriterProjectSnapshot.fromJson(Map<String, dynamic> json) =>
      SongwriterProjectSnapshot(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : 'Untitled song',
        config: SongwriterConfig.fromJson(
          json['config'] as Map<String, dynamic>? ?? const {},
        ),
        sections:
            (json['sections'] as List?)
                ?.map((s) => SongSection.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        drumPatterns:
            (json['drumPatterns'] as List?)
                ?.map((p) => DrumPattern.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        melodyPatterns:
            (json['melodyPatterns'] as List?)
                ?.map((p) => NotePattern.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        guitarStrumPatterns:
            (json['guitarStrumPatterns'] as List?)
                ?.map(
                  (p) => GuitarStrumPattern.fromJson(p as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        audioAssets:
            (json['audioAssets'] as List?)
                ?.map((a) => AudioAsset.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        audioClips:
            (json['audioClips'] as List?)
                ?.map((c) => AudioClip.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class SongSection {
  final String id;
  final String? label; // optional free text
  final int lengthBars;
  final int order;
  final int repeat; // loops the whole section N times
  final List<SongLane> lanes;
  // Free-text lyrics for the section, one entry per repeat instance (verse).
  // Decoupled from bars: see [SongBlock.lyrics] for the per-chord variant.
  final List<String> lyrics;

  const SongSection({
    required this.id,
    required this.lengthBars,
    required this.order,
    this.label,
    this.repeat = 1,
    this.lanes = const [],
    this.lyrics = const [],
  });

  SongSection copyWith({
    String? label,
    int? lengthBars,
    int? order,
    int? repeat,
    List<SongLane>? lanes,
    List<String>? lyrics,
    bool clearLabel = false,
  }) => SongSection(
    id: id,
    label: clearLabel ? null : (label ?? this.label),
    lengthBars: lengthBars ?? this.lengthBars,
    order: order ?? this.order,
    repeat: repeat ?? this.repeat,
    lanes: lanes ?? this.lanes,
    lyrics: lyrics ?? this.lyrics,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'lengthBars': lengthBars,
    'order': order,
    'repeat': repeat,
    'lanes': lanes.map((l) => l.toJson()).toList(),
    'lyrics': lyrics,
  };

  factory SongSection.fromJson(Map<String, dynamic> json) => SongSection(
    id: json['id'] as String,
    label: json['label'] as String?,
    lengthBars: json['lengthBars'] as int? ?? 4,
    order: json['order'] as int? ?? 0,
    repeat: json['repeat'] as int? ?? 1,
    lanes:
        (json['lanes'] as List?)
            ?.map((l) => SongLane.fromJson(l as Map<String, dynamic>))
            .toList() ??
        const [],
    lyrics:
        (json['lyrics'] as List?)?.map((e) => e as String).toList() ?? const [],
  );
}
