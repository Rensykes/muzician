import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('Piano Harmony chord snapshot round-trips both representations', () {
    final original = HarmonyChordSnapshot(
      harmonyInstrument: HarmonyLaneInstrument.piano,
      writerBlock: const WriterBlockSnapshot(
        laneKind: SongLaneKind.harmony,
        chordSymbol: 'Cmaj7',
        chordQuality: 'major7',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G', 'B'],
        defaultLyrics: ['stay'],
      ),
      instrumentState: PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const ['C', 'E', 'G', 'B'],
        viewMode: PianoViewMode.exact,
      ),
    );

    final json = original.toJson();
    expect(json['type'], 'harmony_chord');
    expect(json['instrument'], 'piano');

    final restored = InstrumentSnapshot.fromJson(json);
    expect(restored, isA<HarmonyChordSnapshot>());
    final harmony = restored as HarmonyChordSnapshot;
    expect(harmony.instrument, 'piano');
    expect(harmony.harmonyInstrument, HarmonyLaneInstrument.piano);
    expect(harmony.instrumentState, isA<PianoSnapshot>());
    expect(harmony.writerBlock.chordSymbol, 'Cmaj7');
    expect(harmony.writerBlock.chordNotes, ['C', 'E', 'G', 'B']);
    expect(harmony.writerBlock.defaultLyrics, ['stay']);
    expect(harmony.selectedNotes, ['C', 'E', 'G', 'B']);
  });

  test('Fretboard Harmony chord snapshot preserves the concrete state', () {
    final original = HarmonyChordSnapshot(
      harmonyInstrument: HarmonyLaneInstrument.fretboard,
      writerBlock: const WriterBlockSnapshot(
        laneKind: SongLaneKind.harmony,
        chordSymbol: 'Am',
        chordQuality: 'minor',
        chordRootPc: 9,
        chordNotes: ['A', 'C', 'E'],
      ),
      instrumentState: FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['A', 'C', 'E'],
        viewMode: FretboardViewMode.exact,
      ),
    );

    final restored = InstrumentSnapshot.fromJson(original.toJson());
    expect(restored, isA<HarmonyChordSnapshot>());
    final harmony = restored as HarmonyChordSnapshot;
    expect(harmony.harmonyInstrument, HarmonyLaneInstrument.fretboard);
    expect(harmony.instrumentState, isA<FretboardSnapshot>());
    expect(harmony.writerBlock.chordSymbol, 'Am');
  });

  test('rejects a native snapshot that does not match its lane instrument', () {
    final pianoState = PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [],
      selectedNotes: const ['C', 'E', 'G'],
      viewMode: PianoViewMode.exact,
    );
    const writerBlock = WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      chordSymbol: 'C',
      chordNotes: ['C', 'E', 'G'],
    );

    expect(
      () => HarmonyChordSnapshot(
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
        writerBlock: writerBlock,
        instrumentState: pianoState,
      ),
      throwsArgumentError,
    );

    final mismatchedJson = {
      'type': 'harmony_chord',
      'harmonyInstrument': 'fretboard',
      'writerBlock': writerBlock.toJson(),
      'instrumentState': pianoState.toJson(),
    };
    expect(
      () => InstrumentSnapshot.fromJson(mismatchedJson),
      throwsArgumentError,
    );

    expect(
      () => InstrumentSnapshot.fromJson({
        ...mismatchedJson,
        'instrument': 'piano',
      }),
      throwsFormatException,
    );
  });

  test('rejects non-Harmony Writer content in a Harmony chord snapshot', () {
    final pianoState = PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [],
      selectedNotes: const ['C'],
      viewMode: PianoViewMode.exact,
    );

    expect(
      () => HarmonyChordSnapshot(
        harmonyInstrument: HarmonyLaneInstrument.piano,
        writerBlock: const WriterBlockSnapshot(laneKind: SongLaneKind.save),
        instrumentState: pianoState,
      ),
      throwsArgumentError,
    );
  });
}
