/// CAGED voicing suggestion rules for the Songwriter Phase C v1 slice.
///
/// Given a chord (root pitch-class + quality), [suggestVoicings] returns
/// up to 5 CAGED shape voicings transposed onto the standard-tuned fretboard,
/// sorted by lowest fret ascending. Shapes whose highest fret exceeds 12
/// after transposition are skipped. Only major ('') and minor ('m') triads
/// are supported in v1.
library;

import '../../models/fretboard.dart';
import '../../models/save_system.dart';
import '../../utils/note_utils.dart';

enum CagedShape { c, a, g, e, d }

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
  });
  final CagedShape shape;
  final int rootPc;
  final String quality;
  final List<FretCoordinate> cells;
  final int lowestFret;
  final String label;
}

/// Fret value past which a CAGED shape will not fit on a 12-fret display.
const _kMaxFret = 12;

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
        FretCoordinate(
          stringIndex: i,
          fret: f,
          noteName: chromaticNotes[pc],
        ),
      );
    }

    out.add(
      VoicingSuggestion(
        shape: t.shape,
        rootPc: chordRootPc,
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

/// Wraps a voicing's cells into a `FretboardSnapshot` (standard tuning,
/// 12 frets, capo 0, exact view).
FretboardSnapshot voicingToSnapshot(VoicingSuggestion v) {
  final pcs = <String>{};
  for (final c in v.cells) {
    pcs.add(c.noteName);
  }
  return FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: _kMaxFret,
    capo: 0,
    selectedCells: v.cells,
    selectedNotes: pcs.toList(),
    viewMode: FretboardViewMode.exact,
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
