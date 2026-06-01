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

  // ── Detection panel sourcing (Task 1) ──────────────────────────────────────

  group('detection panel chord catalog', () {
    test(
      'detectChordResultsFromExactNotes uses full chordIntervals catalog',
      () {
        // dim7 chord: C-dim7 = C Eb Gb A = [60, 63, 66, 69]
        final results = detectChordResultsFromExactNotes([
          const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
          const ExactSelectionNote(midiNote: 63, pitchClass: 'D#'),
          const ExactSelectionNote(midiNote: 66, pitchClass: 'F#'),
          const ExactSelectionNote(midiNote: 69, pitchClass: 'A'),
        ]);
        expect(results.any((r) => r.quality == 'dim7'), isTrue);
      },
    );

    test('detectChordResultsFromExactNotes detects m7b5 chord', () {
      // C-m7b5 = C Eb Gb Bb = [60, 63, 66, 70]
      final results = detectChordResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 63, pitchClass: 'D#'),
        const ExactSelectionNote(midiNote: 66, pitchClass: 'F#'),
        const ExactSelectionNote(midiNote: 70, pitchClass: 'A#'),
      ]);
      expect(results.any((r) => r.quality == 'm7b5'), isTrue);
    });

    test('detectChordResultsFromExactNotes detects 7sus4 chord', () {
      // C-7sus4 = C F G Bb = [60, 65, 67, 70]
      final results = detectChordResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 65, pitchClass: 'F'),
        const ExactSelectionNote(midiNote: 67, pitchClass: 'G'),
        const ExactSelectionNote(midiNote: 70, pitchClass: 'A#'),
      ]);
      expect(results.any((r) => r.quality == '7sus4'), isTrue);
    });

    test('formatChordSymbol handles all 17 chord qualities correctly', () {
      const qualityTests = [
        ('', 'Cmaj'),
        ('m', 'Cmin'),
        ('7', 'Cdom7'),
        ('maj7', 'Cmaj7'),
        ('m7', 'Cmin7'),
        ('dim', 'Cdim'),
        ('aug', 'Caug'),
        ('5', 'C5'),
        ('sus2', 'Csus2'),
        ('sus4', 'Csus4'),
        ('m7b5', 'Cm7b5'),
        ('add9', 'Cadd9'),
        ('maj9', 'Cmaj9'),
        ('6', 'C6'),
        ('m6', 'Cmin6'),
        ('dim7', 'Cdim7'),
        ('7sus4', 'C7sus4'),
      ];

      for (final (quality, _) in qualityTests) {
        final formatted = formatChordSymbol(
          ChordDetectionResult(root: 'C', quality: quality),
        );
        expect(
          formatted.contains(quality),
          isTrue,
          reason: 'Expected "$quality" in "$formatted"',
        );
      }
    });
  });

  group('detection panel scale catalog', () {
    test(
      'detectScaleResultsFromExactNotes uses full scaleIntervals catalog',
      () {
        // C diminished scale = C D Eb F Gb Ab A B
        final results = detectScaleResultsFromExactNotes([
          const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
          const ExactSelectionNote(midiNote: 62, pitchClass: 'D'),
          const ExactSelectionNote(midiNote: 63, pitchClass: 'D#'),
          const ExactSelectionNote(midiNote: 65, pitchClass: 'F'),
          const ExactSelectionNote(midiNote: 66, pitchClass: 'F#'),
          const ExactSelectionNote(midiNote: 68, pitchClass: 'G#'),
          const ExactSelectionNote(midiNote: 69, pitchClass: 'A'),
          const ExactSelectionNote(midiNote: 71, pitchClass: 'B'),
        ]);
        expect(results.any((r) => r.scaleName == 'diminished'), isTrue);
      },
    );

    test('detectScaleResultsFromExactNotes detects harmonic minor', () {
      // C harmonic minor = C D Eb F G Ab B
      final results = detectScaleResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 62, pitchClass: 'D'),
        const ExactSelectionNote(midiNote: 63, pitchClass: 'D#'),
        const ExactSelectionNote(midiNote: 65, pitchClass: 'F'),
        const ExactSelectionNote(midiNote: 67, pitchClass: 'G'),
        const ExactSelectionNote(midiNote: 68, pitchClass: 'G#'),
        const ExactSelectionNote(midiNote: 71, pitchClass: 'B'),
      ]);
      expect(results.any((r) => r.scaleName == 'harmonic minor'), isTrue);
    });

    test('detectScaleResultsFromExactNotes detects whole tone', () {
      // C whole tone = C D E F# G# A#
      final results = detectScaleResultsFromExactNotes([
        const ExactSelectionNote(midiNote: 60, pitchClass: 'C'),
        const ExactSelectionNote(midiNote: 62, pitchClass: 'D'),
        const ExactSelectionNote(midiNote: 64, pitchClass: 'E'),
        const ExactSelectionNote(midiNote: 66, pitchClass: 'F#'),
        const ExactSelectionNote(midiNote: 68, pitchClass: 'G#'),
        const ExactSelectionNote(midiNote: 70, pitchClass: 'A#'),
      ]);
      expect(results.any((r) => r.scaleName == 'whole tone'), isTrue);
    });

    test('formatScaleLabel handles all 14 scale types', () {
      const scales = [
        'major',
        'minor',
        'major pentatonic',
        'minor pentatonic',
        'blues',
        'dorian',
        'phrygian',
        'lydian',
        'mixolydian',
        'locrian',
        'harmonic minor',
        'melodic minor',
        'whole tone',
        'diminished',
      ];

      for (final scaleName in scales) {
        final label = formatScaleLabel(
          ScaleDetectionResult(root: 'C', scaleName: scaleName),
        );
        expect(
          label.contains(scaleName),
          isTrue,
          reason: 'Expected "$scaleName" in "$label"',
        );
      }
    });
  });
}
