/// Fretboard voicing suggestion rules for Songwriter harmony blocks.
///
/// [suggestVoicings] preserves the original CAGED major/minor API. The more
/// general [suggestPlayableVoicings] searches playable positions for every
/// quality in [chordIntervals] and can target a tuning, capo, and fret range.
library;

import '../../models/fretboard.dart';
import '../../models/save_system.dart';
import 'fretboard_rules.dart' show tunings;
import '../../utils/note_utils.dart';

enum CagedShape { c, a, g, e, d, generated }

/// A CAGED shape template defined in its open-position fingering.
///
/// [openShape] is indexed 0..5, matching `FretCoordinate.stringIndex` (0-based)
/// and `tunings[TuningName.standard].strings`: 0 = high e (string 1),
/// 5 = low E (string 6). `null` = muted/unplayed.
class VoicingTemplate {
  const VoicingTemplate({
    required this.shape,
    required this.quality,
    required this.anchorPc,
    required this.openShape,
  });
  final CagedShape shape;
  final String quality;
  final int anchorPc;

  /// 0-based, indexed 0..5: 0 = high e (string 1), 5 = low E (string 6).
  final List<int?> openShape;
}

class VoicingSuggestion {
  const VoicingSuggestion({
    required this.shape,
    required this.rootPc,
    required this.quality,
    required this.cells,
    required this.lowestFret,
    required this.label,
    this.tuning = TuningName.standard,
    this.capo = 0,
    this.numFrets = 12,
  });
  final CagedShape shape;
  final int rootPc;
  final String quality;
  final List<FretCoordinate> cells;
  final int lowestFret;
  final String label;
  final TuningName tuning;
  final int capo;
  final int numFrets;
}

/// Fret value past which a CAGED shape will not fit on a 12-fret display.
const _kMaxFret = 12;
const _kMaxFretSpan = 4;

// ─── Templates ───────────────────────────────────────────────────────────────
//
// The spec table lists openShape in strings 6→1 order (low E first). We store
// in 0-based stringIndex order (high e first) for direct alignment with
// `FretCoordinate.stringIndex` and `Tuning.strings`. Each row below is the
// spec's `[s6, s5, s4, s3, s2, s1]` REVERSED, so:
//   spec  C major: [null, 3, 2, 0, 1, 0]   (s6→s1)
//   here  C major: [0, 1, 0, 2, 3, null]   (stringIndex 0..5, s1→s6)

const _templates = <VoicingTemplate>[
  // ── Major ──────────────────────────────────────────────────────────────────
  VoicingTemplate(
    shape: CagedShape.c,
    quality: '',
    anchorPc: 0,
    openShape: [0, 1, 0, 2, 3, null],
  ),
  VoicingTemplate(
    shape: CagedShape.a,
    quality: '',
    anchorPc: 9,
    openShape: [0, 2, 2, 2, 0, null],
  ),
  VoicingTemplate(
    shape: CagedShape.g,
    quality: '',
    anchorPc: 7,
    openShape: [3, 0, 0, 0, 2, 3],
  ),
  VoicingTemplate(
    shape: CagedShape.e,
    quality: '',
    anchorPc: 4,
    openShape: [0, 0, 1, 2, 2, 0],
  ),
  VoicingTemplate(
    shape: CagedShape.d,
    quality: '',
    anchorPc: 2,
    openShape: [2, 3, 2, 0, null, null],
  ),
  // ── Minor ──────────────────────────────────────────────────────────────────
  VoicingTemplate(
    shape: CagedShape.a,
    quality: 'm',
    anchorPc: 9,
    openShape: [0, 1, 2, 2, 0, null],
  ),
  VoicingTemplate(
    shape: CagedShape.e,
    quality: 'm',
    anchorPc: 4,
    openShape: [0, 0, 0, 2, 2, 0],
  ),
  VoicingTemplate(
    shape: CagedShape.d,
    quality: 'm',
    anchorPc: 2,
    openShape: [1, 3, 2, 0, null, null],
  ),
];

// ─── Public API ──────────────────────────────────────────────────────────────

/// Open-string pitch classes for standard tuning, indexed by 0-based string
/// index. Index 0 = high e (pc 4). Index 5 = low E (pc 4).
const _standardTuningOpenPc = <int>[4, 11, 7, 2, 9, 4];

List<VoicingSuggestion> suggestVoicings({
  required int chordRootPc,
  required String quality,
}) {
  if (quality != '' && quality != 'm') return const [];
  final out = <VoicingSuggestion>[];
  for (final t in _templates) {
    if (t.quality != quality) continue;
    final shift = ((chordRootPc - t.anchorPc) % 12 + 12) % 12;

    final transposedFrets = <int?>[];
    var maxFret = -1;
    var minFret = 1 << 30;
    var fits = true;
    for (final f in t.openShape) {
      if (f == null) {
        transposedFrets.add(null);
        continue;
      }
      final newFret = f + shift;
      if (newFret > _kMaxFret) {
        fits = false;
        break;
      }
      transposedFrets.add(newFret);
      if (newFret > maxFret) maxFret = newFret;
      if (newFret < minFret) minFret = newFret;
    }
    if (!fits || maxFret < 0) continue;

    final cells = <FretCoordinate>[];
    for (var i = 0; i < transposedFrets.length; i++) {
      final f = transposedFrets[i];
      if (f == null) continue;
      final openPc = _standardTuningOpenPc[i];
      final pc = (openPc + f) % 12;
      cells.add(
        FretCoordinate(stringIndex: i, fret: f, noteName: chromaticNotes[pc]),
      );
    }

    out.add(
      VoicingSuggestion(
        shape: t.shape,
        rootPc: _normalizePc(chordRootPc),
        quality: quality,
        cells: cells,
        lowestFret: minFret,
        label:
            '${t.shape.name.toUpperCase()}-shape '
            '(${minFret == 0 ? 'open' : '${_ordinal(minFret)} fret'})',
      ),
    );
  }
  out.sort((a, b) => a.lowestFret.compareTo(b.lowestFret));
  return out;
}

/// Searches for playable guitar voicings that contain every chord pitch class
/// and no pitches outside that chord.
///
/// Frets are physical fret numbers, so selected cells start at [capo] and the
/// pitch at each cell is computed from its tuning's open-string MIDI note plus
/// that fret. Each string is either muted or plays one note. Results are
/// deduplicated, ranked deterministically toward lower positions and smaller
/// stretches, and limited to [maxResults].
List<VoicingSuggestion> suggestPlayableVoicings({
  required int chordRootPc,
  required String quality,
  TuningName tuning = TuningName.standard,
  int capo = 0,
  int numFrets = 12,
  int maxResults = 8,
}) {
  final intervals = chordIntervals[quality];
  final tuningSpec = tunings[tuning];
  if (intervals == null ||
      intervals.isEmpty ||
      tuningSpec == null ||
      capo < 0 ||
      capo > 11 ||
      numFrets < 1 ||
      numFrets > 24 ||
      capo > numFrets ||
      maxResults <= 0) {
    return const [];
  }

  final rootPc = _normalizePc(chordRootPc);
  final chordPcs = <int>{
    for (final interval in intervals) (rootPc + interval) % 12,
  };
  if (chordPcs.length > tuningSpec.strings.length) return const [];

  final candidates = <String, List<int?>>{};
  final positions = List<int?>.filled(tuningSpec.strings.length, null);
  final coverageCounts = <int, int>{};

  void collectInWindow(int windowStart) {
    final windowEnd = (windowStart + _kMaxFretSpan)
        .clamp(capo, numFrets)
        .toInt();
    final fretsByString = <List<int?>>[];
    for (final string in tuningSpec.strings) {
      final frets = <int?>[null];
      for (var fret = capo; fret <= numFrets; fret++) {
        final isOpen = capo == 0 && fret == 0;
        if ((isOpen || (fret >= windowStart && fret <= windowEnd)) &&
            chordPcs.contains(_normalizePc(string.midiNote + fret))) {
          frets.add(fret);
        }
      }
      fretsByString.add(frets);
    }

    void visit(int stringIndex) {
      if (chordPcs.length - coverageCounts.length >
          fretsByString.length - stringIndex) {
        return;
      }
      if (stringIndex == fretsByString.length) {
        if (coverageCounts.length != chordPcs.length) return;
        final key = positions.map((fret) => fret ?? -1).join(',');
        candidates.putIfAbsent(key, () => List<int?>.of(positions));
        return;
      }

      for (final fret in fretsByString[stringIndex]) {
        positions[stringIndex] = fret;
        if (fret != null) {
          final pc = _normalizePc(
            tuningSpec.strings[stringIndex].midiNote + fret,
          );
          coverageCounts.update(pc, (count) => count + 1, ifAbsent: () => 1);
        }
        visit(stringIndex + 1);
        if (fret != null) {
          final pc = _normalizePc(
            tuningSpec.strings[stringIndex].midiNote + fret,
          );
          final count = coverageCounts[pc]! - 1;
          if (count == 0) {
            coverageCounts.remove(pc);
          } else {
            coverageCounts[pc] = count;
          }
        }
      }
      positions[stringIndex] = null;
    }

    visit(0);
  }

  for (var start = capo; start <= numFrets; start++) {
    collectInWindow(start);
  }

  final out = <VoicingSuggestion>[];
  for (final frets in candidates.values) {
    final cells = <FretCoordinate>[];
    var lowestFret = 1 << 30;
    for (var stringIndex = 0; stringIndex < frets.length; stringIndex++) {
      final fret = frets[stringIndex];
      if (fret == null) continue;
      final midi = tuningSpec.strings[stringIndex].midiNote + fret;
      final pc = _normalizePc(midi);
      cells.add(
        FretCoordinate(
          stringIndex: stringIndex,
          fret: fret,
          noteName: chromaticNotes[pc],
        ),
      );
      if (fret < lowestFret) lowestFret = fret;
    }
    out.add(
      VoicingSuggestion(
        shape: CagedShape.generated,
        rootPc: rootPc,
        quality: quality,
        cells: cells,
        lowestFret: lowestFret,
        label:
            'Voicing (${lowestFret == 0 ? 'open' : '${_ordinal(lowestFret)} fret'})',
        tuning: tuning,
        capo: capo,
        numFrets: numFrets,
      ),
    );
  }

  out.sort((a, b) {
    var order = a.lowestFret.compareTo(b.lowestFret);
    if (order != 0) return order;
    order = _fretSpan(a.cells, capo).compareTo(_fretSpan(b.cells, capo));
    if (order != 0) return order;
    order = _highestFret(a.cells).compareTo(_highestFret(b.cells));
    if (order != 0) return order;
    order = b.cells.length.compareTo(a.cells.length);
    if (order != 0) return order;
    for (var i = 0; i < tuningSpec.strings.length; i++) {
      order = _fretAtString(a.cells, i).compareTo(_fretAtString(b.cells, i));
      if (order != 0) return order;
    }
    return 0;
  });

  final chordLabel = chromaticNotes[rootPc];
  final limited = out.take(maxResults).toList();
  for (var i = 0; i < limited.length; i++) {
    final voicing = limited[i];
    limited[i] = VoicingSuggestion(
      shape: voicing.shape,
      rootPc: voicing.rootPc,
      quality: voicing.quality,
      cells: voicing.cells,
      lowestFret: voicing.lowestFret,
      label:
          '$chordLabel$quality voicing ${i + 1} '
          '(${voicing.lowestFret == 0 ? 'open' : '${_ordinal(voicing.lowestFret)} fret'})',
      tuning: voicing.tuning,
      capo: voicing.capo,
      numFrets: voicing.numFrets,
    );
  }
  return limited;
}

int _normalizePc(int midiOrPc) => ((midiOrPc % 12) + 12) % 12;

int _fretAtString(List<FretCoordinate> cells, int stringIndex) {
  for (final cell in cells) {
    if (cell.stringIndex == stringIndex) return cell.fret;
  }
  return -1;
}

int _highestFret(List<FretCoordinate> cells) => cells.fold<int>(
  0,
  (highest, cell) => cell.fret > highest ? cell.fret : highest,
);

int _fretSpan(List<FretCoordinate> cells, int capo) {
  final fingered = cells
      .where((cell) => cell.fret > capo)
      .map((cell) => cell.fret)
      .toList();
  if (fingered.length < 2) return 0;
  fingered.sort();
  return fingered.last - fingered.first;
}

/// Wraps a voicing's cells into an exact-view `FretboardSnapshot`.
///
/// Sets `pendingChord` from the suggestion's source chord (`rootPc` +
/// `quality`) so the saved voicing can be matched back to the same harmony
/// block via `matchLibrary`'s chord-hit predicate.
FretboardSnapshot voicingToSnapshot(VoicingSuggestion v) {
  final pcs = <String>{for (final c in v.cells) c.noteName};
  final rootName = chromaticNotes[_normalizePc(v.rootPc)];
  return FretboardSnapshot(
    tuning: v.tuning,
    numFrets: v.numFrets,
    capo: v.capo,
    selectedCells: v.cells,
    selectedNotes: pcs.toList(),
    viewMode: FretboardViewMode.exact,
    pendingChord: PendingChord(
      root: rootName,
      quality: v.quality,
      symbol: '$rootName${v.quality}',
    ),
  );
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}
