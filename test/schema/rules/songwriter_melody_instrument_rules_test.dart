import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_melody_instrument_rules.dart';

void main() {
  const standardGuitar = FretboardState(
    currentTuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    highlightedNotes: [],
    selectedNotes: [],
    selectedCells: [],
    viewMode: FretboardViewMode.exact,
    inputMode: FretboardInputMode.free,
  );

  const capoedGuitar = FretboardState(
    currentTuning: TuningName.standard,
    numFrets: 12,
    capo: 2,
    highlightedNotes: [],
    selectedNotes: [],
    selectedCells: [],
    viewMode: FretboardViewMode.exact,
    inputMode: FretboardInputMode.free,
  );

  NotePattern pattern(List<int> midis) => NotePattern(
    id: 'melody',
    name: 'Lead',
    lengthTicks: 16,
    notes: [
      for (var i = 0; i < midis.length; i++)
        NotePatternNote(
          id: 'n$i',
          midiNote: midis[i],
          startTick: i * 2,
          durationTicks: 2,
        ),
    ],
    pitchRangeStart: 48,
    pitchRangeEnd: 84,
    snapTicks: 1,
    highlightedNotes: const [],
  );

  test('enumerates only physical positions matching MIDI under capo', () {
    final positions = fretboardPositionsForMidi(
      midiNote: 64,
      state: capoedGuitar,
    );
    expect(
      positions.map((position) => (position.stringIndex, position.fret)),
      containsAll([(1, 5), (2, 9)]),
    );
    expect(
      positions.any((position) => position.fret < capoedGuitar.capo),
      isFalse,
    );
    expect(
      isValidFretboardNotePosition(
        midiNote: 64,
        position: const FretboardNotePosition(stringIndex: 0, fret: 0),
        state: capoedGuitar,
      ),
      isFalse,
    );
  });

  test('gates Piano and Fretboard views using current instrument limits', () {
    expect(
      canOpenOnInstrument(
        pattern: pattern([60, 64, 84]),
        instrument: HarmonyLaneInstrument.piano,
        pianoRange: PianoRangeName.key49,
        fretboard: standardGuitar,
      ),
      isTrue,
    );
    expect(
      canOpenOnInstrument(
        pattern: pattern([60, 85]),
        instrument: HarmonyLaneInstrument.piano,
        pianoRange: PianoRangeName.key49,
        fretboard: standardGuitar,
      ),
      isFalse,
    );
    expect(
      canOpenOnInstrument(
        pattern: pattern([64]),
        instrument: HarmonyLaneInstrument.fretboard,
        pianoRange: PianoRangeName.key88,
        fretboard: capoedGuitar.copyWith(numFrets: 4),
      ),
      isFalse,
    );
  });

  test('reconciles positions by note id, pitch, and current fretboard', () {
    const saved = {
      'n0': FretboardNotePosition(stringIndex: 0, fret: 5),
      'deleted': FretboardNotePosition(stringIndex: 0, fret: 0),
      'n1': FretboardNotePosition(stringIndex: 0, fret: 0),
    };
    final reconciled = reconcileFretboardPositions(
      pattern: pattern([69]),
      positions: saved,
      state: standardGuitar,
    );
    expect(reconciled.keys, ['n0']);
    expect((reconciled['n0']!.stringIndex, reconciled['n0']!.fret), (0, 5));
  });
}
