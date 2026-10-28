/// Deterministic, bounded chord and instrument voicing search rules.
library;

import 'dart:math' as math;

import '../../models/fretboard.dart';
import '../../utils/note_utils.dart';

class ChordSearchIdentity {
  final String root;
  final String quality;

  const ChordSearchIdentity({required this.root, required this.quality});

  String get id => '$root:$quality';
}

class FretboardVoicingCandidate {
  final ChordSearchIdentity chord;
  final ChordVoicing voicing;

  const FretboardVoicingCandidate({required this.chord, required this.voicing});

  String get id => '${chord.id}:${voicing.positions.join(',')}';
}

class PianoVoicingCandidate {
  final ChordSearchIdentity chord;
  final int inversion;
  final List<int> midis;

  const PianoVoicingCandidate({
    required this.chord,
    required this.inversion,
    required this.midis,
  });

  String get id => '${chord.id}:${midis.join(',')}';
}

/// Returns every supported root/quality whose pitch-class set contains all
/// [requiredPitchClasses], with fewer added chord tones first, then chromatic root and quality order.
/// Extra chord tones are allowed when they fit [scaleRoot]/[scaleName], if set.
List<ChordSearchIdentity> chordCandidatesContainingPitchClasses(
  Iterable<String> requiredPitchClasses, {
  String? scaleRoot,
  String? scaleName,
}) {
  final required = <int>{
    for (final note in requiredPitchClasses) ?noteToPC[toSharp(note)],
  };
  if (required.isEmpty) return const [];

  final candidates = <ChordSearchIdentity>[];
  for (final root in chromaticNotes) {
    for (final quality in chordIntervals.keys) {
      final chordNotes = getChordNotes(root, quality);
      if (chordPitchClassesOutOfKey(
        chordNotes,
        scaleRoot: scaleRoot,
        scaleName: scaleName,
      ).isNotEmpty) {
        continue;
      }
      final chordPcs = chordNotes.map((note) => noteToPC[note]!).toSet();
      if (chordPcs.containsAll(required)) {
        candidates.add(ChordSearchIdentity(root: root, quality: quality));
      }
    }
  }
  // Prefer simpler completions; retain catalogue order for equal tone counts.
  final order = {
    for (var i = 0; i < candidates.length; i++) candidates[i].id: i,
  };
  candidates.sort((a, b) {
    final bySize = getChordNotes(
      a.root,
      a.quality,
    ).length.compareTo(getChordNotes(b.root, b.quality).length);
    return bySize != 0 ? bySize : order[a.id]!.compareTo(order[b.id]!);
  });
  return candidates;
}

/// Generates complete guitar shapes inside the current
/// physical fretboard span. Hand shapes cover at most four adjacent frets,
/// with all capo-touching strings treated as open strings. Results are not
/// count-limited and are ordered by fuller shapes, lower position, then frets.
List<ChordVoicing> generateFretboardChordVoicings({
  required String root,
  required String quality,
  required List<int> stringMidis,
  required int capo,
  required int numFrets,
}) {
  final chordNotes = getChordNotes(root, quality);
  final chordPcs = chordNotes.map((note) => noteToPC[note]!).toSet();
  if (chordPcs.isEmpty || stringMidis.isEmpty || capo > numFrets) {
    return const [];
  }

  final stringOptions = stringMidis.map((openMidi) {
    final options = <int>[];
    for (var fret = capo; fret <= numFrets; fret++) {
      final midi = openMidi + fret;
      if (chordPcs.contains(midi % 12)) options.add(fret);
    }
    return options;
  }).toList();

  final byPosition = <String, ChordVoicing>{};
  final firstWindow = capo == 0 ? 1 : capo;
  for (var base = firstWindow; base <= numFrets; base++) {
    final end = base + 3;
    final choices = stringOptions.map((options) {
      final result = <int?>[null];
      if (capo == 0 && options.contains(0)) result.add(0);
      if (capo > 0 && options.contains(capo)) result.add(capo);
      result.addAll(
        options.where((fret) => fret > capo && fret >= base && fret <= end),
      );
      return result;
    }).toList();

    void visit(int stringIndex, List<int?> positions) {
      if (stringIndex == stringMidis.length) {
        final played = positions.whereType<int>().toList();
        if (played.length < chordPcs.length) return;

        final playedPcs = <int>{};
        for (var index = 0; index < positions.length; index++) {
          final fret = positions[index];
          if (fret != null) playedPcs.add((stringMidis[index] + fret) % 12);
        }
        if (!playedPcs.containsAll(chordPcs)) return;

        final fretted = played.where((fret) => fret > capo).toList();
        if (fretted.isNotEmpty &&
            fretted.reduce((a, b) => a > b ? a : b) -
                    fretted.reduce((a, b) => a < b ? a : b) >
                3) {
          return;
        }

        final key = positions.join(',');
        if (byPosition.containsKey(key)) return;
        final usedFrets = played.where((fret) => fret > capo).toList();
        final baseFret = usedFrets.isEmpty
            ? 0
            : usedFrets.reduce((a, b) => a < b ? a : b);
        byPosition[key] = ChordVoicing(
          positions: List<int?>.unmodifiable(positions),
          baseFret: baseFret,
        );
        return;
      }

      for (final fret in choices[stringIndex]) {
        positions.add(fret);
        visit(stringIndex + 1, positions);
        positions.removeLast();
      }
    }

    visit(0, []);
  }

  final results = byPosition.values.toList();
  results.sort((left, right) {
    final leftPlayed = left.positions.whereType<int>().length;
    final rightPlayed = right.positions.whereType<int>().length;
    final byFullness = rightPlayed.compareTo(leftPlayed);
    if (byFullness != 0) return byFullness;
    final byPosition = left.baseFret.compareTo(right.baseFret);
    if (byPosition != 0) return byPosition;
    return _compareNullableInts(left.positions, right.positions);
  });
  return results;
}

/// Enumerates ordered inversions, register choices, and open spacings that
/// include every chord tone,
/// fit within [rangeStartMidi]…[rangeEndMidi], and span no more than 23
/// semitones. The two-octave span keeps each complete result visible in the
/// existing two-octave card diagram. Every octave placement and inversion
/// within those bounds is returned; no tone is clipped at the keyboard edge.
List<PianoVoicingCandidate> generatePianoChordVoicings({
  required String root,
  required String quality,
  required int rangeStartMidi,
  required int rangeEndMidi,
}) {
  final tones = getChordNotes(
    root,
    quality,
  ).map((note) => noteToPC[note]!).toList(growable: false);
  if (tones.isEmpty || rangeEndMidi < rangeStartMidi) return const [];

  const maxSpanSemitones = 23;
  final unique = <String, PianoVoicingCandidate>{};
  for (var inversion = 0; inversion < tones.length; inversion++) {
    final orderedTones = [...tones.skip(inversion), ...tones.take(inversion)];
    final firstTone = orderedTones.first;

    for (
      var firstMidi = rangeStartMidi;
      firstMidi <= rangeEndMidi;
      firstMidi++
    ) {
      if (firstMidi % 12 != firstTone) continue;

      void visit(int toneIndex, List<int> midis) {
        if (toneIndex == orderedTones.length) {
          final candidate = PianoVoicingCandidate(
            chord: ChordSearchIdentity(root: root, quality: quality),
            inversion: inversion,
            midis: List<int>.unmodifiable(midis),
          );
          unique.putIfAbsent(candidate.id, () => candidate);
          return;
        }

        final previousMidi = midis.last;
        final highestMidi = math
            .min(rangeEndMidi, firstMidi + maxSpanSemitones)
            .toInt();
        for (var midi = previousMidi + 1; midi <= highestMidi; midi++) {
          if (midi % 12 != orderedTones[toneIndex]) continue;
          midis.add(midi);
          visit(toneIndex + 1, midis);
          midis.removeLast();
        }
      }

      visit(1, [firstMidi]);
    }
  }

  final results = unique.values.toList();
  results.sort((left, right) {
    final byInversion = left.inversion.compareTo(right.inversion);
    if (byInversion != 0) return byInversion;
    final byBass = left.midis.first.compareTo(right.midis.first);
    if (byBass != 0) return byBass;
    final leftSpan = left.midis.last - left.midis.first;
    final rightSpan = right.midis.last - right.midis.first;
    final bySpan = leftSpan.compareTo(rightSpan);
    if (bySpan != 0) return bySpan;
    return _compareInts(left.midis, right.midis);
  });
  return results;
}

/// Interleave chord identities so one chord's many shapes do not bury the
/// other completions. By-chord browsing still exposes its entire ordered list.
List<FretboardVoicingCandidate> searchFretboardVoicingsFromNotes({
  required Iterable<String> requiredPitchClasses,
  required List<int> stringMidis,
  required int capo,
  required int numFrets,
  String? scaleRoot,
  String? scaleName,
}) => _interleave([
  for (final chord in chordCandidatesContainingPitchClasses(
    requiredPitchClasses,
    scaleRoot: scaleRoot,
    scaleName: scaleName,
  ))
    [
      for (final voicing in generateFretboardChordVoicings(
        root: chord.root,
        quality: chord.quality,
        stringMidis: stringMidis,
        capo: capo,
        numFrets: numFrets,
      ))
        FretboardVoicingCandidate(chord: chord, voicing: voicing),
    ],
]);

List<PianoVoicingCandidate> searchPianoVoicingsFromNotes({
  required Iterable<String> requiredPitchClasses,
  required int rangeStartMidi,
  required int rangeEndMidi,
  String? scaleRoot,
  String? scaleName,
}) => _interleave([
  for (final chord in chordCandidatesContainingPitchClasses(
    requiredPitchClasses,
    scaleRoot: scaleRoot,
    scaleName: scaleName,
  ))
    generatePianoChordVoicings(
      root: chord.root,
      quality: chord.quality,
      rangeStartMidi: rangeStartMidi,
      rangeEndMidi: rangeEndMidi,
    ),
]);

List<T> _interleave<T>(List<List<T>> groups) {
  final results = <T>[];
  final longest = groups.fold(
    0,
    (length, group) => math.max(length, group.length),
  );
  for (var index = 0; index < longest; index++) {
    for (final group in groups) {
      if (index < group.length) results.add(group[index]);
    }
  }
  return results;
}

int _compareNullableInts(List<int?> left, List<int?> right) {
  for (var index = 0; index < left.length && index < right.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a == b) continue;
    if (a == null) return 1;
    if (b == null) return -1;
    final comparison = a.compareTo(b);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}

int _compareInts(List<int> left, List<int> right) {
  for (var index = 0; index < left.length && index < right.length; index++) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}
