import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmonic_analysis.dart';
import 'package:muzician/utils/note_utils.dart';

void main() {
  group('exact-note chord detection', () {
    test('reports slash chord when bass differs from root', () {
      final results = detectChordResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 52, pitchClass: 'E'),
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 67, pitchClass: 'G'),
      ]);

      expect(results.first.root, 'C');
      expect(results.first.quality, '');
      expect(results.first.bass, 'E');
      expect(formatChordSymbol(results.first), 'C/E');
    });
  });

  group('scale parity', () {
    test('covers the full picker catalog through shared scale intervals', () {
      final results = detectScaleResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 62, pitchClass: 'D'),
        const ExactSelectionNote(midiNote: 64, pitchClass: 'E'),
        const ExactSelectionNote(midiNote: 66, pitchClass: 'F#'),
        const ExactSelectionNote(midiNote: 67, pitchClass: 'G'),
        const ExactSelectionNote(midiNote: 69, pitchClass: 'A'),
        const ExactSelectionNote(midiNote: 71, pitchClass: 'B'),
      ]);

      expect(results.any((result) => result.scaleName == 'lydian'), isTrue);
    });
  });

  group('contextual spelling', () {
    test('formats common flat harmonic labels musically', () {
      const chord = ChordDetectionResult(
        root: 'A#',
        quality: 'maj7',
        bass: 'D',
      );
      const scale = ScaleDetectionResult(root: 'D#', scaleName: 'dorian');

      expect(formatChordSymbol(chord), 'Bbmaj7/D');
      expect(formatScaleLabel(scale), 'Eb dorian');
      expect(formatRootChoiceLabel('C#'), 'Db');
    });
  });

  group('compatibility', () {
    test('compatibility wrapper still returns canonical root and quality', () {
      final detected = detectFirstChord(['C', 'E', 'G']);
      expect(detected, isNotNull);
      expect(detected!.root, 'C');
      expect(detected.quality, '');
    });
  });
}
