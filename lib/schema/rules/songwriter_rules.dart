/// Songwriter pure rules: Roman-numeral derivation, overlap validation,
/// factories, and timeline flattening.
library;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';
import 'save_system_rules.dart' show generateId, getProjectIdForFolder;

const _romanByDegree = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];

/// Classifies a chord quality string into how its Roman numeral is cased.
String _caseNumeral(String degreeUpper, String quality) {
  final q = quality.toLowerCase();
  if (q.contains('dim')) return '${degreeUpper.toLowerCase()}°';
  if (q.contains('aug')) return '$degreeUpper+';
  // minor-ish: starts with 'm' but not 'maj'
  final isMinor =
      (q.startsWith('m') && !q.startsWith('maj')) || q.contains('min');
  return isMinor ? degreeUpper.toLowerCase() : degreeUpper;
}

/// Returns the diatonic Roman numeral for a chord whose root is [chordRootPc]
/// (pitch class 0-11) in the key [keyRootPc]/[keyScaleName], or null when no
/// key is set or the chord root is not a scale degree of that key.
String? romanNumeralFor(
  int chordRootPc,
  String quality,
  int? keyRootPc,
  String? keyScaleName,
) {
  if (keyRootPc == null || keyScaleName == null) return null;
  final intervals = scaleIntervals[keyScaleName];
  if (intervals == null) return null;
  final offset = ((chordRootPc - keyRootPc) % 12 + 12) % 12;
  final degree = intervals.indexOf(offset);
  if (degree < 0 || degree >= _romanByDegree.length) return null;
  return _caseNumeral(_romanByDegree[degree], quality);
}

// ─── Diatonic Triad Derivation ───────────────────────────────────────────────

class DiatonicTriad {
  const DiatonicTriad({
    required this.degree,
    required this.rootPc,
    required this.quality,
    required this.symbol,
    required this.romanNumeral,
    required this.notes,
  });
  final int degree;
  final int rootPc;
  final String quality;
  final String symbol;
  final String romanNumeral;
  final List<String> notes;
}

/// Returns the 7 diatonic triads for [keyRootPc] / [scaleName].
///
/// Each triad's quality is derived by stacking thirds from the scale's
/// interval set: the intervals root→3rd and root→5th classify the triad
/// as major (''), minor ('m'), diminished ('dim'), or augmented ('aug').
/// Returns an empty list when [scaleName] is unknown or has fewer than 7
/// degrees.
List<DiatonicTriad> diatonicTriads(int keyRootPc, String scaleName) {
  final intervals = scaleIntervals[scaleName];
  if (intervals == null || intervals.length < 7) return [];
  final out = <DiatonicTriad>[];
  for (var d = 0; d < 7; d++) {
    final rootSemitone = intervals[d];
    final thirdSemitone = intervals[(d + 2) % 7];
    final fifthSemitone = intervals[(d + 4) % 7];
    final i3 = ((thirdSemitone - rootSemitone) % 12 + 12) % 12;
    final i5 = ((fifthSemitone - rootSemitone) % 12 + 12) % 12;

    String quality;
    if (i3 == 4 && i5 == 7) {
      quality = '';
    } else if (i3 == 3 && i5 == 7) {
      quality = 'm';
    } else if (i3 == 3 && i5 == 6) {
      quality = 'dim';
    } else if (i3 == 4 && i5 == 8) {
      quality = 'aug';
    } else {
      // Non-tertian triad (e.g. whole-tone, diminished scales). Fall back to
      // major for symbol display; chord notes still use scale-derived pcs.
      quality = '';
    }

    final rootPc = (keyRootPc + rootSemitone) % 12;
    final rootName = chromaticNotes[rootPc];
    final symbol = '$rootName$quality';
    final numeral = _caseNumeral(_romanByDegree[d], quality);
    final notes = getChordNotes(rootName, quality);

    out.add(
      DiatonicTriad(
        degree: d,
        rootPc: rootPc,
        quality: quality,
        symbol: symbol,
        romanNumeral: numeral,
        notes: notes,
      ),
    );
  }
  return out;
}

// ─── Overlap Validation ───────────────────────────────────────────────────────

/// True if [candidate] overlaps any block in [existing] (same lane).
/// Gaps are allowed; touching edges (one ends where the next starts) is not
/// an overlap. A block never overlaps itself (matched by id).
bool blocksOverlap(List<SongBlock> existing, SongBlock candidate) {
  for (final b in existing) {
    if (b.id == candidate.id) continue;
    final overlaps =
        candidate.startBar < b.endBar && b.startBar < candidate.endBar;
    if (overlaps) return true;
  }
  return false;
}

// ─── Factory Helpers ─────────────────────────────────────────────────────────

SongSection makeSection({
  String? label,
  required int lengthBars,
  required int order,
}) => SongSection(
  id: generateId(),
  label: label,
  lengthBars: lengthBars,
  order: order,
);

SongLane makeLane({
  required SongLaneKind kind,
  String? label,
  required int order,
}) => SongLane(id: generateId(), kind: kind, label: label, order: order);

SongBlock makeSaveBlock({
  required String saveId,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  saveId: saveId,
  startBar: startBar,
  spanBars: spanBars,
);

SongBlock makeEmbeddedSaveBlock({
  required InstrumentSnapshot snapshot,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  embedded: snapshot,
);

SongBlock makeHarmonyBlock({
  required int startBar,
  required int spanBars,
  required String chordSymbol,
  required String chordQuality,
  required int chordRootPc,
  required List<String> chordNotes,
  String? romanNumeral,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  chordSymbol: chordSymbol,
  chordQuality: chordQuality,
  chordRootPc: chordRootPc,
  chordNotes: chordNotes,
  romanNumeral: romanNumeral,
);

SongBlock makeSilentBlock({
  required int startBar,
  required int spanBars,
  int verseCount = 1,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  isSilent: true,
  lyrics: List<String>.filled(verseCount.clamp(1, 16), ''),
);

DrumPattern makeDrumPattern({String name = 'Pattern'}) => DrumPattern(
  id: generateId(),
  name: name,
  lengthTicks: 16,
  lanes: [
    for (final id in DrumLaneId.values)
      DrumLaneSequence(laneId: id, activeTicks: const []),
  ],
);

NotePattern makeMelodyPattern({
  String name = 'Melody',
  required int lengthTicks,
}) => NotePattern(
  id: generateId(),
  name: name,
  lengthTicks: lengthTicks < 1 ? 1 : lengthTicks,
  notes: const [],
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
  snapTicks: 1,
  highlightedNotes: const [],
);

GuitarStrumPattern makeGuitarStrumPattern({
  String name = 'Strum',
  required int lengthTicks,
  required int beatTicks,
}) {
  final safeLength = lengthTicks < 1 ? 1 : lengthTicks;
  final safeBeatTicks = beatTicks < 1 ? 1 : beatTicks;
  return GuitarStrumPattern(
    id: generateId(),
    name: name,
    lengthTicks: safeLength,
    events: [
      for (var tick = 0; tick < safeLength; tick += safeBeatTicks)
        GuitarStrumEvent(
          tick: tick,
          direction: (tick ~/ safeBeatTicks).isEven
              ? GuitarStrumDirection.down
              : GuitarStrumDirection.up,
        ),
    ],
  );
}

SongBlock makeDrumBlock({
  required String patternId,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  patternId: patternId,
);

SongBlock makePatternBlock({
  required String patternId,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  patternId: patternId,
);

AudioClip makeAudioClip({
  required String assetId,
  required int durationMs,
  AudioFitMode fitMode = AudioFitMode.loop,
}) => AudioClip(
  id: generateId(),
  assetId: assetId,
  trimStartMs: 0,
  trimEndMs: durationMs,
  fitMode: fitMode,
);

/// Whole bars a freshly recorded clip should occupy: enough bars to contain a
/// [durationMs] take at [msPerBar] (rounded up), clamped to `[1, maxBars]`. A
/// 5s take at 120 BPM 4/4 (1 bar = 2000 ms) spans 3 bars, not the whole section.
int recordedClipSpanBars({
  required int durationMs,
  required double msPerBar,
  required int maxBars,
}) {
  final cap = maxBars < 1 ? 1 : maxBars;
  if (msPerBar <= 0) return cap;
  final bars = (durationMs / msPerBar).ceil();
  if (bars < 1) return 1;
  return bars > cap ? cap : bars;
}

/// Default bar span for a new audio block placed at [startBar] in a section of
/// [sectionLengthBars]: fills all the way to the section end (floor of 1).
int audioBlockDefaultSpan({
  required int sectionLengthBars,
  required int startBar,
}) {
  if (sectionLengthBars <= 1) return 1;
  final remaining = sectionLengthBars - startBar;
  return remaining < 1 ? 1 : remaining;
}

SongBlock makeAudioBlock({
  required String audioClipId,
  required int startBar,
  required int spanBars,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  audioClipId: audioClipId,
);

/// Captures the placement-free Writer content owned by [block]. Save-lane
/// instrument content remains in its canonical instrument snapshot (or in the
/// legacy embedded fallback), so this helper returns null for those blocks.
/// Missing pattern, clip, or source-asset references are left unresolved rather
/// than replaced with fabricated content.
WriterBlockSnapshot? writerBlockSnapshotFor(
  SongwriterProjectSnapshot project,
  SongLane lane,
  SongBlock block,
) {
  if (lane.kind == SongLaneKind.save) {
    final fallback = block.embedded;
    return fallback is WriterBlockSnapshot ? fallback : null;
  }

  final fallback = block.embedded;
  final defaultLyrics =
      fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
      ? fallback.defaultLyrics
      : block.lyrics;

  if (lane.kind == SongLaneKind.harmony) {
    if (fallback is WriterBlockSnapshot &&
        fallback.laneKind == lane.kind &&
        block.chordSymbol == null &&
        block.chordQuality == null &&
        block.chordRootPc == null &&
        block.chordNotes.isEmpty &&
        (fallback.isSilent || fallback.chordSymbol != null)) {
      return fallback;
    }
    return WriterBlockSnapshot(
      laneKind: lane.kind,
      isSilent: block.isSilent,
      chordSymbol: block.chordSymbol,
      chordQuality: block.chordQuality,
      chordRootPc: block.chordRootPc,
      chordNotes: block.chordNotes,
      romanNumeral: block.romanNumeral,
      defaultLyrics: defaultLyrics,
    );
  }

  if (lane.kind == SongLaneKind.drum) {
    final patternId = block.patternId;
    if (patternId == null) {
      return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
          ? fallback
          : null;
    }
    final pattern = project.drumPatterns
        .where((candidate) => candidate.id == patternId)
        .firstOrNull;
    if (pattern == null) {
      return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
          ? fallback
          : null;
    }
    return WriterBlockSnapshot(
      laneKind: lane.kind,
      drumPattern: pattern,
      defaultLyrics: defaultLyrics,
    );
  }

  if (lane.kind == SongLaneKind.melody) {
    final patternId = block.patternId;
    if (patternId == null) {
      return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
          ? fallback
          : null;
    }
    final pattern = project.melodyPatterns
        .where((candidate) => candidate.id == patternId)
        .firstOrNull;
    if (pattern == null) {
      return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
          ? fallback
          : null;
    }
    return WriterBlockSnapshot(
      laneKind: lane.kind,
      melodyPattern: pattern,
      defaultLyrics: defaultLyrics,
    );
  }

  if (lane.kind == SongLaneKind.guitarStrum) {
    final patternId = block.patternId;
    if (patternId == null) {
      return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
          ? fallback
          : null;
    }
    final pattern = project.guitarStrumPatterns
        .where((candidate) => candidate.id == patternId)
        .firstOrNull;
    if (pattern == null) {
      return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
          ? fallback
          : null;
    }
    return WriterBlockSnapshot(
      laneKind: lane.kind,
      guitarStrumPattern: pattern,
      defaultLyrics: defaultLyrics,
    );
  }

  final clipId = block.audioClipId;
  if (clipId == null) {
    return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
        ? fallback
        : null;
  }
  final clip = project.audioClips
      .where((candidate) => candidate.id == clipId)
      .firstOrNull;
  if (clip == null) {
    return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
        ? fallback
        : null;
  }
  final asset = project.audioAssets
      .where((candidate) => candidate.id == clip.assetId)
      .firstOrNull;
  if (asset == null) {
    return fallback is WriterBlockSnapshot && fallback.laneKind == lane.kind
        ? fallback
        : null;
  }
  final stretchedAssetId = clip.stretchedAssetId;
  final stretchedAsset = stretchedAssetId == null
      ? null
      : project.audioAssets
            .where((candidate) => candidate.id == stretchedAssetId)
            .firstOrNull;
  return WriterBlockSnapshot(
    laneKind: lane.kind,
    audioClip: clip,
    audioAsset: asset,
    stretchedAudioAsset: stretchedAsset,
    defaultLyrics: defaultLyrics,
  );
}

// ─── Expanded-Section Mapping ────────────────────────────────────────────────

class ExpandedSection {
  const ExpandedSection({
    required this.sectionId,
    required this.repeatIndex,
    required this.globalStartBar,
    required this.lengthBars,
  });
  final String sectionId;
  final int repeatIndex;
  final int globalStartBar;
  final int lengthBars;
  int get globalEndBar => globalStartBar + lengthBars;
}

class SectionHit {
  const SectionHit({required this.section, required this.localBar});
  final ExpandedSection section;
  final int localBar;
}

List<ExpandedSection> expandSections(List<SongSection> sections) {
  final out = <ExpandedSection>[];
  var bar = 0;
  for (final s in sections) {
    final reps = s.repeat < 1 ? 1 : s.repeat;
    for (var r = 0; r < reps; r++) {
      out.add(
        ExpandedSection(
          sectionId: s.id,
          repeatIndex: r,
          globalStartBar: bar,
          lengthBars: s.lengthBars,
        ),
      );
      bar += s.lengthBars;
    }
  }
  return out;
}

SectionHit? sectionAtGlobalBar(List<ExpandedSection> expanded, int globalBar) {
  for (final e in expanded) {
    if (globalBar >= e.globalStartBar && globalBar < e.globalEndBar) {
      return SectionHit(section: e, localBar: globalBar - e.globalStartBar);
    }
  }
  return null;
}

// ─── Timeline Flattening ──────────────────────────────────────────────────────

/// Total bar length of the whole project after expanding section repeats.
int flattenedBarCount(List<SongSection> sections) {
  var total = 0;
  for (final s in sections) {
    total += s.lengthBars * s.repeat;
  }
  return total;
}

/// The section's first harmony lane (the "primary" lane: it carries the
/// lyrics, the inline save badges, and governs save-lane mixing), or null.
SongLane? primaryHarmonyLane(SongSection section) {
  for (final l in section.lanes) {
    if (l.kind == SongLaneKind.harmony) return l;
  }
  return null;
}

/// The harmony lane a save [lane]'s voicings belong to: its
/// [SongLane.anchorLaneId] when that still names a harmony lane in
/// [section], otherwise the primary harmony lane (legacy save lanes have no
/// anchor). Null when the section has no harmony lane at all.
SongLane? saveAnchorLane(SongSection section, SongLane lane) {
  for (final l in section.lanes) {
    if (l.id == lane.anchorLaneId && l.kind == SongLaneKind.harmony) return l;
  }
  return primaryHarmonyLane(section);
}

/// The lane whose mix settings (volume / pan / muted) govern [lane] during
/// playback and export. Save lanes follow their anchor harmony lane (see
/// [saveAnchorLane]) — their blocks render as badges on that lane and sound
/// as part of it — so they have no mix of their own. Every other lane
/// governs itself, as does a save lane in a section with no harmony lane.
SongLane mixGoverningLane(SongSection section, SongLane lane) {
  if (lane.kind != SongLaneKind.save) return lane;
  return saveAnchorLane(section, lane) ?? lane;
}

/// Display fallback for the [index]-th harmony lane of a section when it has
/// no user label: "Harmony", then "Harmony 2", "Harmony 3", … Shared by the
/// lane headers, the add-lane action, and the Song export.
String harmonyLaneFallbackLabel(int index) =>
    index == 0 ? 'Harmony' : 'Harmony ${index + 1}';

/// Display fallback for an unlabeled lane by kind.
String laneKindFallbackLabel(SongLaneKind kind) => switch (kind) {
  SongLaneKind.harmony => 'Harmony',
  SongLaneKind.save => 'Save',
  SongLaneKind.drum => 'Beat',
  SongLaneKind.audio => 'Sample',
  SongLaneKind.melody => 'Melody',
  SongLaneKind.guitarStrum => 'Guitar strum',
};

/// Natural pattern length of a lane = the max block end bar (0 if empty).
int laneNaturalLength(SongLane lane) {
  var max = 0;
  for (final b in lane.blocks) {
    if (b.endBar > max) max = b.endBar;
  }
  return max;
}

/// Expands a lane's blocks into concrete placements, tiling the block pattern
/// [lane.repeat] times from bar 0, clipped to [sectionLengthBars]. A placement
/// offsets each block's startBar by the tile origin. A tile whose origin is at
/// or beyond the section length is not emitted; within a tile, a block whose
/// (offset) startBar is at or beyond the section length is skipped. Blocks that
/// start inside the section but span past its end are kept.
List<SongBlock> tileLaneBlocks(
  SongLane lane, {
  required int sectionLengthBars,
}) {
  final pattern = laneNaturalLength(lane);
  if (pattern <= 0) return const [];
  final out = <SongBlock>[];
  for (var tile = 0; tile < lane.repeat; tile++) {
    final origin = tile * pattern;
    if (origin >= sectionLengthBars) break;
    for (final b in lane.blocks) {
      final start = origin + b.startBar;
      if (start >= sectionLengthBars) continue;
      out.add(b.copyWith(startBar: start));
    }
  }
  return out;
}

// ─── Snapshot Resolution ─────────────────────────────────────────────────────

/// Resolves a block's content. A canonical save is used only when its folder is
/// inside [projectId]; a missing or foreign save falls back to retained content.
InstrumentSnapshot? resolveBlockSnapshot(
  SongBlock block,
  List<SaveEntry> saves, {
  required String? projectId,
  required List<SaveFolder> folders,
}) {
  final id = block.saveId;
  if (id != null && projectId != null) {
    final entry = saves.where((save) => save.id == id).firstOrNull;
    if (entry != null &&
        getProjectIdForFolder(folders, entry.folderId) == projectId) {
      return entry.snapshot;
    }
  }
  return block.embedded;
}

/// The chord a save block resolves to, for Roman-numeral display.
class ResolvedChord {
  const ResolvedChord({
    required this.rootPc,
    required this.quality,
    required this.symbol,
  });

  /// Pitch class (0-11) of the chord root.
  final int rootPc;

  /// Chord quality string (e.g. `''`, `'m'`, `'maj7'`).
  final String quality;

  /// Display symbol (e.g. `'Cmaj7'`).
  final String symbol;
}

/// Resolves the chord of a save block's [snapshot] for display.
///
/// Prefers an explicit [InstrumentSnapshot.pendingChord] (set when the user
/// committed a chord on the source instrument). When absent, detects the first
/// matching chord from the snapshot's [InstrumentSnapshot.selectedNotes] so
/// that voicings saved by free note placement still surface a chord — and thus
/// a scale degree. Returns null when no chord can be determined.
ResolvedChord? resolveSnapshotChord(InstrumentSnapshot? snapshot) {
  if (snapshot == null) return null;

  // noteToPC is keyed by sharp spellings only, so normalize any flat-spelled
  // root (e.g. a legacy/imported save or a future flats display mode) to its
  // sharp equivalent before lookup; otherwise the chord would be silently
  // dropped and no degree shown.
  final pending = snapshot.pendingChord;
  if (pending != null) {
    final pc = noteToPC[toSharp(pending.root)];
    if (pc != null) {
      return ResolvedChord(
        rootPc: pc,
        quality: pending.quality,
        symbol: pending.symbol,
      );
    }
  }

  final detected = detectFirstChord(
    snapshot.selectedNotes.map(toSharp).toList(),
  );
  if (detected != null) {
    final pc = noteToPC[detected.root];
    if (pc != null) {
      return ResolvedChord(
        rootPc: pc,
        quality: detected.quality,
        symbol: '${detected.root}${detected.quality}',
      );
    }
  }

  return null;
}

/// The Roman numeral a save block's resolved chord maps to in the given key,
/// or null when no chord can be resolved or it is non-diatonic. Convenience
/// wrapper combining [resolveSnapshotChord] and [romanNumeralFor].
String? saveBlockRomanNumeral(
  InstrumentSnapshot? snapshot,
  int? keyRootPc,
  String? keyScaleName,
) {
  final chord = resolveSnapshotChord(snapshot);
  if (chord == null) return null;
  return romanNumeralFor(chord.rootPc, chord.quality, keyRootPc, keyScaleName);
}
