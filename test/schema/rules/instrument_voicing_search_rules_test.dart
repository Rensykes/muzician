import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/instrument_voicing_search_rules.dart';
import 'package:muzician/utils/note_utils.dart';

void main() {
  test('note search exposes different completions before alternate shapes', () {
    final results = searchFretboardVoicingsFromNotes(
      requiredPitchClasses: ['C', 'E'],
      stringMidis: [64, 59, 55, 50, 45, 40],
      capo: 0,
      numFrets: 12,
    );
    expect(results.first.chord.id, 'C:');
    expect(results[1].chord.id, isNot(results.first.chord.id));
    expect(results.map((r) => r.id).toSet().length, results.length);
    expect(results.map((r) => r.chord.id), containsAll(['C:maj7', 'F:maj7']));
  });

  group('chordCandidatesContainingPitchClasses', () {
    test(
      'returns every chord containing all requested notes plus extra tones',
      () {
        final candidates = chordCandidatesContainingPitchClasses(['C', 'E']);
        final ids = candidates.map((chord) => chord.id).toSet();

        expect(
          ids,
          containsAll(['C:', 'C:maj7', 'A:m', 'F:maj7', 'C:aug', 'C:7']),
        );
        expect(ids, isNot(contains('G:7')));
        for (final chord in candidates) {
          expect(
            getChordNotes(chord.root, chord.quality).toSet(),
            containsAll(['C', 'E']),
            reason:
                '${chord.root}${chord.quality} must retain every query tone',
          );
        }
      },
    );

    test('keeps every chord tone inside the active major scale', () {
      final candidates = chordCandidatesContainingPitchClasses(
        ['C', 'E'],
        scaleRoot: 'C',
        scaleName: 'major',
      );
      final ids = candidates.map((chord) => chord.id).toSet();

      expect(ids, containsAll(['C:', 'C:maj7', 'A:m', 'F:maj7']));
      expect(ids, isNot(contains('C:aug')));
      expect(ids, isNot(contains('C:7')));
      expect(ids, isNot(contains('E:aug')));
      expect(candidates.first.id, 'C:');
      expect(candidates[1].id, 'A:m');
      final scaleNotes = getScaleNotes('C', 'major');
      for (final chord in candidates) {
        final tones = getChordNotes(chord.root, chord.quality);
        expect(tones, containsAll(['C', 'E']));
        expect(tones, everyElement(isIn(scaleNotes)));
      }
    });

    test('an in-scale chord root does not permit chromatic chord tones', () {
      final unrestricted = chordCandidatesContainingPitchClasses(['E']);
      final inScale = chordCandidatesContainingPitchClasses(
        ['E'],
        scaleRoot: 'C',
        scaleName: 'major',
      );

      expect(unrestricted.map((chord) => chord.id), contains('E:'));
      expect(inScale.map((chord) => chord.id), isNot(contains('E:')));
      expect(inScale.map((chord) => chord.id), contains('E:m'));
    });

    test('uses the full active pentatonic scale rather than a major key', () {
      final candidates = chordCandidatesContainingPitchClasses(
        ['C', 'E'],
        scaleRoot: 'C',
        scaleName: 'major pentatonic',
      );
      final ids = candidates.map((chord) => chord.id).toSet();

      expect(ids, containsAll(['C:', 'A:m', 'C:6', 'C:add9']));
      expect(ids, isNot(contains('C:maj7')));
      expect(ids, isNot(contains('F:maj7')));
      final scaleNotes = getScaleNotes('C', 'major pentatonic');
      for (final chord in candidates) {
        expect(
          getChordNotes(chord.root, chord.quality),
          everyElement(isIn(scaleNotes)),
        );
      }
    });

    test('does not relax a captured note outside the active scale', () {
      expect(
        chordCandidatesContainingPitchClasses(
          ['C', 'D#'],
          scaleRoot: 'C',
          scaleName: 'major',
        ),
        isEmpty,
      );
      expect(chordCandidatesContainingPitchClasses(['C', 'D#']), isNotEmpty);
    });

    test('normalizes flats and leaves empty note queries explicit', () {
      final candidates = chordCandidatesContainingPitchClasses(['Db', 'F']);
      expect(candidates, isNotEmpty);
      expect(candidates.every((chord) => chord.root != 'Db'), isTrue);
      expect(chordCandidatesContainingPitchClasses(const []), isEmpty);
    });
  });

  group('generateFretboardChordVoicings', () {
    final standardStringMidis = [64, 59, 55, 50, 45, 40];

    test('searches the complete configured fret range deterministically', () {
      final first = generateFretboardChordVoicings(
        root: 'C',
        quality: '',
        stringMidis: standardStringMidis,
        capo: 0,
        numFrets: 24,
      );
      final second = generateFretboardChordVoicings(
        root: 'C',
        quality: '',
        stringMidis: standardStringMidis,
        capo: 0,
        numFrets: 24,
      );

      expect(first, isNotEmpty);
      expect(
        first.map((voicing) => voicing.positions.join(',')),
        second.map((voicing) => voicing.positions.join(',')),
      );
      expect(
        first.any(
          (voicing) =>
              voicing.positions.any((fret) => fret != null && fret > 14),
        ),
        isTrue,
        reason: 'the search must reach frets above the former hardcoded limit',
      );
      for (final voicing in first) {
        final played = <String>{};
        for (var index = 0; index < voicing.positions.length; index++) {
          final fret = voicing.positions[index];
          if (fret != null) {
            played.add(
              chromaticNotes[(standardStringMidis[index] + fret) % 12],
            );
          }
        }
        expect(played, containsAll(['C', 'E', 'G']));
      }
    });

    test('respects capo and the configured fretboard boundary', () {
      final voicings = generateFretboardChordVoicings(
        root: 'D',
        quality: 'm',
        stringMidis: standardStringMidis,
        capo: 7,
        numFrets: 12,
      );

      expect(voicings, isNotEmpty);
      for (final fret in voicings.expand((voicing) => voicing.positions)) {
        if (fret != null) expect(fret, inInclusiveRange(7, 12));
      }
    });

    test('From-notes results contain every captured pitch class', () {
      final results = searchFretboardVoicingsFromNotes(
        requiredPitchClasses: const ['C', 'E'],
        stringMidis: standardStringMidis,
        capo: 0,
        numFrets: 12,
      );

      expect(results, isNotEmpty);
      expect(
        results.map((result) => result.chord.id),
        containsAll(['C:', 'C:maj7', 'A:m', 'F:maj7']),
      );
      for (final result in results) {
        final played = <String>{};
        for (var index = 0; index < result.voicing.positions.length; index++) {
          final fret = result.voicing.positions[index];
          if (fret != null) {
            played.add(
              chromaticNotes[(standardStringMidis[index] + fret) % 12],
            );
          }
        }
        expect(played, containsAll(['C', 'E']));
      }
    });

    test('From-notes shapes contain only active-scale pitches', () {
      final results = searchFretboardVoicingsFromNotes(
        requiredPitchClasses: const ['C', 'E'],
        stringMidis: standardStringMidis,
        capo: 0,
        numFrets: 12,
        scaleRoot: 'C',
        scaleName: 'major',
      );

      expect(results, isNotEmpty);
      expect(
        results.map((result) => result.chord.id),
        containsAll(['C:', 'C:maj7', 'A:m', 'F:maj7']),
      );
      final scaleNotes = getScaleNotes('C', 'major');
      for (final result in results) {
        final played = <String>{};
        for (var index = 0; index < result.voicing.positions.length; index++) {
          final fret = result.voicing.positions[index];
          if (fret != null) {
            played.add(
              chromaticNotes[(standardStringMidis[index] + fret) % 12],
            );
          }
        }
        expect(played, containsAll(['C', 'E']));
        expect(played, everyElement(isIn(scaleNotes)));
      }
      expect(
        searchFretboardVoicingsFromNotes(
          requiredPitchClasses: const ['C', 'D#'],
          stringMidis: standardStringMidis,
          capo: 0,
          numFrets: 12,
          scaleRoot: 'C',
          scaleName: 'major',
        ),
        isEmpty,
      );
    });
  });

  group('generatePianoChordVoicings', () {
    test(
      'returns complete inversions and octave placements across the range',
      () {
        final results = generatePianoChordVoicings(
          root: 'C',
          quality: 'maj7',
          rangeStartMidi: 36,
          rangeEndMidi: 84,
        );

        expect(results, isNotEmpty);
        expect(results.map((result) => result.inversion).toSet(), {0, 1, 2, 3});
        expect(
          results.map((result) => result.midis.first ~/ 12).toSet().length,
          greaterThan(1),
        );
        expect(
          results.any((result) => result.midis.first < 48) &&
              results.any((result) => result.midis.last > 72),
          isTrue,
        );
        for (final result in results) {
          expect(result.midis, everyElement(inInclusiveRange(36, 84)));
          expect(result.midis.toSet().length, 4);
          expect(result.midis.map((midi) => midi % 12).toSet(), {0, 4, 7, 11});
          expect(result.midis.last - result.midis.first, lessThanOrEqualTo(23));
        }
      },
    );

    test(
      'never returns a partial chord when the active range clips a tone',
      () {
        final results = generatePianoChordVoicings(
          root: 'C',
          quality: '',
          rangeStartMidi: 60,
          rangeEndMidi: 62,
        );

        expect(results, isEmpty);
      },
    );

    test(
      'From-notes results keep captured tones without requiring exact match',
      () {
        final results = searchPianoVoicingsFromNotes(
          requiredPitchClasses: const ['C', 'E'],
          rangeStartMidi: 36,
          rangeEndMidi: 84,
        );

        expect(results, isNotEmpty);
        expect(
          results.map((result) => result.chord.id),
          containsAll(['C:', 'C:maj7', 'A:m', 'F:maj7']),
        );
        for (final result in results) {
          expect(
            result.midis.map((midi) => chromaticNotes[midi % 12]).toSet(),
            containsAll(['C', 'E']),
          );
        }
      },
    );

    test('From-notes keys contain only active-scale pitches', () {
      final results = searchPianoVoicingsFromNotes(
        requiredPitchClasses: const ['C', 'E'],
        rangeStartMidi: 36,
        rangeEndMidi: 84,
        scaleRoot: 'C',
        scaleName: 'major',
      );

      expect(results, isNotEmpty);
      expect(
        results.map((result) => result.chord.id),
        containsAll(['C:', 'C:maj7', 'A:m', 'F:maj7']),
      );
      final scaleNotes = getScaleNotes('C', 'major');
      for (final result in results) {
        final played = result.midis
            .map((midi) => chromaticNotes[midi % 12])
            .toSet();
        expect(played, containsAll(['C', 'E']));
        expect(played, everyElement(isIn(scaleNotes)));
      }
      expect(
        searchPianoVoicingsFromNotes(
          requiredPitchClasses: const ['C', 'D#'],
          rangeStartMidi: 36,
          rangeEndMidi: 84,
          scaleRoot: 'C',
          scaleName: 'major',
        ),
        isEmpty,
      );
    });
  });
}
