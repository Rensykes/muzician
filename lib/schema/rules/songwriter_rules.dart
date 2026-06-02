/// Songwriter pure rules: Roman-numeral derivation, overlap validation,
/// factories, and timeline flattening.
library;

import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';
import 'save_system_rules.dart' show generateId;

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

SongSection makeSection(
        {String? label, required int lengthBars, required int order}) =>
    SongSection(
        id: generateId(), label: label, lengthBars: lengthBars, order: order);

SongLane makeLane(
        {required SongLaneKind kind, String? label, required int order}) =>
    SongLane(id: generateId(), kind: kind, label: label, order: order);

SongBlock makeSaveBlock({
  required String saveId,
  required int startBar,
  required int spanBars,
}) =>
    SongBlock(
        id: generateId(),
        saveId: saveId,
        startBar: startBar,
        spanBars: spanBars);

SongBlock makeHarmonyBlock({
  required int startBar,
  required int spanBars,
  required String chordSymbol,
  required String chordQuality,
  required int chordRootPc,
  required List<String> chordNotes,
  String? romanNumeral,
}) =>
    SongBlock(
      id: generateId(),
      startBar: startBar,
      spanBars: spanBars,
      chordSymbol: chordSymbol,
      chordQuality: chordQuality,
      chordRootPc: chordRootPc,
      chordNotes: chordNotes,
      romanNumeral: romanNumeral,
    );

// ─── Timeline Flattening ──────────────────────────────────────────────────────

/// Total bar length of the whole project after expanding section repeats.
int flattenedBarCount(List<SongSection> sections) {
  var total = 0;
  for (final s in sections) {
    total += s.lengthBars * s.repeat;
  }
  return total;
}

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
List<SongBlock> tileLaneBlocks(SongLane lane, {required int sectionLengthBars}) {
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
