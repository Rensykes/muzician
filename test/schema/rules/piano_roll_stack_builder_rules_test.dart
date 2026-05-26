import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/piano_roll_stack_builder_rules.dart';

void main() {
  group('generateCanonicalStack', () {
    test('creates C major triad root position', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 0,
        noteCount: 3,
      );
      expect(result.length, 3);
      expect(result[0] % 12, 0); // C
      expect(result[1] % 12, 4); // E
      expect(result[2] % 12, 7); // G
      expect(result[0], lessThan(result[1]));
      expect(result[1], lessThan(result[2]));
    });

    test('creates triad first inversion (E G C)', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 1,
        noteCount: 3,
      );
      expect(result[0] % 12, 4); // E
      expect(result[1] % 12, 7); // G
      expect(result[2] % 12, 0); // C
      expect(result[0], lessThan(result[1]));
      expect(result[1], lessThan(result[2]));
    });

    test('creates triad second inversion (G C E)', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 2,
        noteCount: 3,
      );
      expect(result[0] % 12, 7); // G
      expect(result[1] % 12, 0); // C
      expect(result[2] % 12, 4); // E
    });

    test('creates dom7 root position (C E G Bb)', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '7',
        inversionIndex: 0,
        noteCount: 4,
      );
      expect(result[0] % 12, 0); // C
      expect(result[1] % 12, 4); // E
      expect(result[2] % 12, 7); // G
      expect(result[3] % 12, 10); // Bb
    });

    test('creates dom7 third inversion (Bb C E G)', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '7',
        inversionIndex: 3,
        noteCount: 4,
      );
      expect(result[0] % 12, 10); // Bb
      expect(result[1] % 12, 0); // C
      expect(result[2] % 12, 4); // E
      expect(result[3] % 12, 7); // G
    });

    test('generates more notes than unique tones by wrapping octaves', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 0,
        noteCount: 5,
      );
      expect(result.length, 5);
      expect(result[0] % 12, 0); // C
      expect(result[1] % 12, 4); // E
      expect(result[2] % 12, 7); // G
      expect(result[3] % 12, 0); // C (one octave up)
      expect(result[4] % 12, 4); // E (one octave up)
      expect(result[3] - result[0], 12);
    });

    test('uses anchorMidi to position the stack', () {
      final low = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 0,
        noteCount: 3,
        anchorMidi: 48,
      );
      final high = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 0,
        noteCount: 3,
        anchorMidi: 72,
      );
      expect(low[0], lessThan(high[0]));
      expect(low[0] % 12, 0);
      expect(high[0] % 12, 0);
    });

    test('empty quality still produces major triad', () {
      final result = generateCanonicalStack(
        root: 'C',
        quality: '',
        inversionIndex: 0,
        noteCount: 3,
      );
      expect(result.length, 3);
    });
  });

  group('recognizeStack', () {
    test('C major triad root position recognized', () {
      final result = recognizeStack([60, 64, 67]);
      expect(result.isRecognized, true);
      expect(result.recognizedRoot, 'C');
      expect(result.recognizedQuality, '');
      expect(result.recognizedInversionIndex, 0);
      expect(result.isCustomVoicing, false);
    });

    test('C major second inversion custom voicing: G2 C3 E3 G3 C4', () {
      final result = recognizeStack([43, 48, 52, 55, 60]);
      expect(result.isRecognized, true);
      expect(result.recognizedRoot, 'C');
      expect(result.recognizedQuality, '');
      expect(result.recognizedInversionIndex, 2);
      expect(result.isCustomVoicing, true);
    });

    test('duplicates do not break root/quality recognition', () {
      final result = recognizeStack([60, 64, 67, 72]);
      expect(result.isRecognized, true);
      expect(result.recognizedRoot, 'C');
      expect(result.recognizedQuality, '');
      expect(result.isCustomVoicing, true);
    });

    test('unrecognized pitch class set', () {
      final result = recognizeStack([60, 61, 62]);
      expect(result.isRecognized, false);
      expect(result.recognizedRoot, isNull);
      expect(result.recognizedQuality, isNull);
      expect(result.recognizedInversionIndex, isNull);
    });

    test('D minor root position recognized', () {
      final result = recognizeStack([62, 65, 69]);
      expect(result.isRecognized, true);
      expect(result.recognizedRoot, 'D');
      expect(result.recognizedQuality, 'm');
      expect(result.recognizedInversionIndex, 0);
    });

    test('single note is not recognized', () {
      final result = recognizeStack([60]);
      expect(result.isRecognized, false);
    });
  });

  group('enforceMaxNotes', () {
    test('truncates to 10 notes', () {
      final input = List<int>.generate(15, (i) => 60 + i);
      final result = enforceMaxNotes(input);
      expect(result.length, 10);
    });

    test('passes through 10 or fewer notes unchanged', () {
      expect(enforceMaxNotes([60, 64, 67]), [60, 64, 67]);
    });

    test('returns empty for empty input', () {
      expect(enforceMaxNotes([]), isEmpty);
    });
  });

  group('retargetCanonicalStack', () {
    test('preserves note count and stays near register', () {
      final result = retargetCanonicalStack(
        currentMidiNotes: [43, 48, 52, 55, 60],
        root: 'D',
        quality: 'm',
        inversionIndex: 0,
      );
      expect(result.length, 5);
      final pcs = result.map((m) => m % 12).toSet();
      expect(pcs, containsAll([2, 5, 9])); // D, F, A
      for (var i = 1; i < result.length; i++) {
        expect(result[i], greaterThan(result[i - 1]));
      }
    });

    test('handles inversion change preserving count', () {
      final result = retargetCanonicalStack(
        currentMidiNotes: [60, 64, 67], // C major root position
        root: 'F',
        quality: '',
        inversionIndex: 1, // first inversion: A C F
      );
      expect(result.length, 3);
      expect(result[0] % 12, 9); // A (third = lowest in 1st inv)
      expect(result[1] % 12, 0); // C (fifth)
      expect(result[2] % 12, 5); // F (root)
    });
  });
}
