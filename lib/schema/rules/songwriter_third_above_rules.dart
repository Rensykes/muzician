/// 3rd-above harmony suggestion rule for the Songwriter Phase C v2-a slice.
///
/// Given a harmony block's chord and the project key, returns a single
/// [ThirdAboveSuggestion] that shifts each source pitch class up by a
/// diatonic 3rd in the key. Source pcs not in the key's scale are dropped.
/// Returns null when no key is set, when the scale is unknown, or when the
/// chord is fully non-diatonic.
library;

import '../../models/piano.dart';
import '../../models/save_system.dart';
import '../../utils/note_utils.dart';

/// MIDI value of C4 — the bottom of the C4..B4 octave used for anchoring
/// 3rd-above harmony notes.
const int _c4Midi = 60;

/// Starting MIDI value of [PianoRangeName.key49] (C2). `keyIndex` in the
/// `key49` range is computed as `midi - _key49StartMidi`.
const int _key49StartMidi = 36;

class ThirdAboveSuggestion {
  const ThirdAboveSuggestion({
    required this.rootPc,
    required this.quality,
    required this.sourcePcs,
    required this.targetPcs,
    required this.midiKeys,
    required this.label,
  });
  final int rootPc;
  final String quality;
  final List<int> sourcePcs;
  final List<int> targetPcs;
  final List<int> midiKeys;
  final String label;
}

/// Returns a single 3rd-above suggestion or null when the chord/key combo
/// has no diatonic targets.
ThirdAboveSuggestion? suggestThirdAbove({
  required int chordRootPc,
  required String chordQuality,
  required List<int> chordTonePcs,
  required int? keyRootPc,
  required String? keyScaleName,
}) {
  if (keyRootPc == null || keyScaleName == null) return null;
  final intervals = scaleIntervals[keyScaleName];
  if (intervals == null || intervals.length < 7) return null;

  final targetPcs = <int>[];
  for (final sourcePc in chordTonePcs) {
    final offset = ((sourcePc - keyRootPc) % 12 + 12) % 12;
    final degree = intervals.indexOf(offset);
    if (degree < 0) continue;
    final targetDegree = (degree + 2) % 7;
    final targetPc = (keyRootPc + intervals[targetDegree]) % 12;
    if (!targetPcs.contains(targetPc)) targetPcs.add(targetPc);
  }
  if (targetPcs.isEmpty) return null;

  // Octave anchoring: midi 60..71 (C4..B4).
  final midiKeys = [for (final pc in targetPcs) _c4Midi + pc];

  final names = targetPcs.map((pc) => chromaticNotes[pc]).join(', ');
  return ThirdAboveSuggestion(
    rootPc: chordRootPc,
    quality: chordQuality,
    sourcePcs: List.unmodifiable(chordTonePcs),
    targetPcs: List.unmodifiable(targetPcs),
    midiKeys: List.unmodifiable(midiKeys),
    label: '3rd above ($names)',
  );
}

/// Wraps a suggestion as a PianoSnapshot anchored in key49's middle octave.
PianoSnapshot thirdAboveToSnapshot(ThirdAboveSuggestion s) {
  return PianoSnapshot(
    currentRange: PianoRangeName.key49,
    selectedKeys: [
      for (final m in s.midiKeys)
        PianoCoordinate(
          keyIndex: m - _key49StartMidi,
          midiNote: m,
          noteName: chromaticNotes[m % 12],
        ),
    ],
    selectedNotes: [for (final pc in s.targetPcs) chromaticNotes[pc]],
    viewMode: PianoViewMode.exact,
  );
}
