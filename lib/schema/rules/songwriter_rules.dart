/// Songwriter pure rules: Roman-numeral derivation, overlap validation,
/// factories, and timeline flattening.
library;

import '../../utils/note_utils.dart';

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
