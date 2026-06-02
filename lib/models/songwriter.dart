/// Songwriter project model — section/lane/block arrangement tree.
library;

import 'save_system.dart';

enum SongLaneKind { harmony, save }

// ignore: unused_element — used by SongLane in B1.3
SongLaneKind _laneKindFromName(String? raw) {
  for (final v in SongLaneKind.values) {
    if (v.name == raw) return v;
  }
  return SongLaneKind.save;
}

class SongBlock {
  final String id;
  final int startBar; // 0-based offset within the section
  final int spanBars; // width in bars

  // save-lane reference (live link into SaveSystemState.saves)
  final String? saveId;
  // non-null when "Made Unique" — detached snapshot copy
  final InstrumentSnapshot? embedded;

  // harmony-lane extras (null on save-lane blocks)
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;

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
  }) =>
      SongBlock(
        id: id,
        startBar: startBar ?? this.startBar,
        spanBars: spanBars ?? this.spanBars,
        saveId: saveId ?? this.saveId,
        embedded: embedded ?? this.embedded,
        chordSymbol: chordSymbol ?? this.chordSymbol,
        chordQuality: chordQuality ?? this.chordQuality,
        chordRootPc: chordRootPc ?? this.chordRootPc,
        chordNotes: chordNotes ?? this.chordNotes,
        romanNumeral: romanNumeral ?? this.romanNumeral,
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
      };

  factory SongBlock.fromJson(Map<String, dynamic> json) => SongBlock(
        id: json['id'] as String,
        startBar: json['startBar'] as int? ?? 0,
        spanBars: json['spanBars'] as int? ?? 1,
        saveId: json['saveId'] as String?,
        embedded: json['embedded'] == null
            ? null
            : InstrumentSnapshot.fromJson(
                json['embedded'] as Map<String, dynamic>),
        chordSymbol: json['chordSymbol'] as String?,
        chordQuality: json['chordQuality'] as String?,
        chordRootPc: json['chordRootPc'] as int?,
        chordNotes:
            (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
                const [],
        romanNumeral: json['romanNumeral'] as String?,
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

  SongwriterConfig copyWith({
    int? tempo,
    int? beatsPerBar,
    int? beatUnit,
    int? keyRoot,
    String? keyScaleName,
    bool clearKey = false,
  }) =>
      SongwriterConfig(
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
