/// Songwriter project model — section/lane/block arrangement tree.
library;

import 'save_system.dart';

enum SongLaneKind { harmony, save }

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
    bool clearRomanNumeral = false,
    bool clearSaveId = false,
    bool clearEmbedded = false,
  }) => SongBlock(
    id: id,
    startBar: startBar ?? this.startBar,
    spanBars: spanBars ?? this.spanBars,
    saveId: clearSaveId ? null : (saveId ?? this.saveId),
    embedded: clearEmbedded ? null : (embedded ?? this.embedded),
    chordSymbol: chordSymbol ?? this.chordSymbol,
    chordQuality: chordQuality ?? this.chordQuality,
    chordRootPc: chordRootPc ?? this.chordRootPc,
    chordNotes: chordNotes ?? this.chordNotes,
    romanNumeral: clearRomanNumeral
        ? null
        : (romanNumeral ?? this.romanNumeral),
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
        : InstrumentSnapshot.fromJson(json['embedded'] as Map<String, dynamic>),
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

  const SongLane({
    required this.id,
    required this.kind,
    required this.order,
    this.label,
    this.repeat = 1,
    this.blocks = const [],
  });

  SongLane copyWith({
    SongLaneKind? kind,
    String? label,
    int? order,
    int? repeat,
    List<SongBlock>? blocks,
  }) => SongLane(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    order: order ?? this.order,
    repeat: repeat ?? this.repeat,
    blocks: blocks ?? this.blocks,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'order': order,
    'repeat': repeat,
    'blocks': blocks.map((b) => b.toJson()).toList(),
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
  );
}

class SongwriterProjectSnapshot extends InstrumentSnapshot {
  final SongwriterConfig config;
  final List<SongSection> sections;

  const SongwriterProjectSnapshot({
    required this.config,
    this.sections = const [],
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
    return set.toList();
  }

  @override
  PendingChord? get pendingChord => null;

  @override
  PendingScale? get pendingScale => null;

  SongwriterProjectSnapshot copyWith({
    SongwriterConfig? config,
    List<SongSection>? sections,
  }) => SongwriterProjectSnapshot(
    config: config ?? this.config,
    sections: sections ?? this.sections,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'songwriter',
    'instrument': 'songwriter',
    'config': config.toJson(),
    'sections': sections.map((s) => s.toJson()).toList(),
  };

  factory SongwriterProjectSnapshot.fromJson(Map<String, dynamic> json) =>
      SongwriterProjectSnapshot(
        config: SongwriterConfig.fromJson(
          json['config'] as Map<String, dynamic>? ?? const {},
        ),
        sections:
            (json['sections'] as List?)
                ?.map((s) => SongSection.fromJson(s as Map<String, dynamic>))
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

  const SongSection({
    required this.id,
    required this.lengthBars,
    required this.order,
    this.label,
    this.repeat = 1,
    this.lanes = const [],
  });

  SongSection copyWith({
    String? label,
    int? lengthBars,
    int? order,
    int? repeat,
    List<SongLane>? lanes,
    bool clearLabel = false,
  }) => SongSection(
    id: id,
    label: clearLabel ? null : (label ?? this.label),
    lengthBars: lengthBars ?? this.lengthBars,
    order: order ?? this.order,
    repeat: repeat ?? this.repeat,
    lanes: lanes ?? this.lanes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'lengthBars': lengthBars,
    'order': order,
    'repeat': repeat,
    'lanes': lanes.map((l) => l.toJson()).toList(),
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
  );
}
