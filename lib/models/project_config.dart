library;

import 'harmony_lane_instrument.dart';

/// Global config carried by a top-level project folder (kind == project).
/// Saves under the project inherit and stay locked to these fields.
class ProjectConfig {
  final int? keyRootPc; // 0..11; null = no key set
  final String? keyScaleName; // e.g. 'major', 'minor', 'dorian'
  final int tempo; // BPM
  final int beatsPerBar; // numerator
  final int beatUnit; // denominator: 2, 4, 8, 16
  final HarmonyLaneInstrument defaultHarmonyInstrument;

  const ProjectConfig({
    this.keyRootPc,
    this.keyScaleName,
    this.tempo = 120,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.defaultHarmonyInstrument = HarmonyLaneInstrument.fretboard,
  });

  ProjectConfig copyWith({
    int? keyRootPc,
    String? keyScaleName,
    int? tempo,
    int? beatsPerBar,
    int? beatUnit,
    HarmonyLaneInstrument? defaultHarmonyInstrument,
    bool clearKey = false,
  }) => ProjectConfig(
    keyRootPc: clearKey ? null : (keyRootPc ?? this.keyRootPc),
    keyScaleName: clearKey ? null : (keyScaleName ?? this.keyScaleName),
    tempo: tempo ?? this.tempo,
    beatsPerBar: beatsPerBar ?? this.beatsPerBar,
    beatUnit: beatUnit ?? this.beatUnit,
    defaultHarmonyInstrument:
        defaultHarmonyInstrument ?? this.defaultHarmonyInstrument,
  );

  Map<String, dynamic> toJson() => {
    'keyRootPc': keyRootPc,
    'keyScaleName': keyScaleName,
    'tempo': tempo,
    'beatsPerBar': beatsPerBar,
    'beatUnit': beatUnit,
    'defaultHarmonyInstrument': defaultHarmonyInstrument.name,
  };

  factory ProjectConfig.fromJson(Map<String, dynamic> json) => ProjectConfig(
    keyRootPc: json['keyRootPc'] as int?,
    keyScaleName: json['keyScaleName'] as String?,
    tempo: json['tempo'] as int? ?? 120,
    beatsPerBar: json['beatsPerBar'] as int? ?? 4,
    beatUnit: json['beatUnit'] as int? ?? 4,
    defaultHarmonyInstrument:
        HarmonyLaneInstrument.fromJson(
          json['defaultHarmonyInstrument'] as String?,
        ) ??
        HarmonyLaneInstrument.fretboard,
  );
}
