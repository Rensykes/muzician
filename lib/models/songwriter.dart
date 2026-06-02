/// Songwriter project model — section/lane/block arrangement tree.
library;

enum SongLaneKind { harmony, save }

// ignore: unused_element — used by SongLane in B1.3
SongLaneKind _laneKindFromName(String? raw) {
  for (final v in SongLaneKind.values) {
    if (v.name == raw) return v;
  }
  return SongLaneKind.save;
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
