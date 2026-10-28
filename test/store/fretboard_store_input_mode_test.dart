import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/schema/rules/fretboard_rules.dart';

void main() {
  test('default board reaches fret 24 with physical capo pitches', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(fretboardProvider.notifier);
    expect(container.read(fretboardProvider).numFrets, 24);
    notifier.setCapo(2);
    final strings = notifier.getFretCells();
    expect(strings, hasLength(6));
    expect(strings.every((cells) => cells.length == 25), isTrue);
    expect(strings.first.last.fret, 24);
    expect(strings.first.last.midiNote, 88);
    expect(strings.last.last.midiNote, 64);
    notifier.toggleCell(0, 24, 'E');
    expect(getFretboardStrumMidiNotes(container.read(fretboardProvider)), [88]);
    expect(positionMarkerFrets, containsAll([15, 17, 19, 21, 24]));
  });

  test('older Save opens on 24 frets without rewriting its stored content', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final snapshot = FretboardSnapshot(
      tuning: TuningName.dropD,
      numFrets: 12,
      capo: 2,
      selectedCells: [FretCoordinate(stringIndex: 0, fret: 2, noteName: 'F#')],
      selectedNotes: ['F#'],
      viewMode: FretboardViewMode.exactFocus,
      inputMode: FretboardInputMode.chord,
    );
    container.read(fretboardProvider.notifier).loadSnapshot(snapshot);
    final loaded = container.read(fretboardProvider);
    expect(loaded.numFrets, 24);
    expect(loaded.selectedCells, snapshot.selectedCells);
    expect(loaded.currentTuning, snapshot.tuning);
    expect(loaded.capo, snapshot.capo);
    expect(loaded.viewMode, snapshot.viewMode);
    expect(loaded.inputMode, snapshot.inputMode);
    expect(snapshot.numFrets, 12);
  });

  test('loadSnapshot restores Chord versus Free input behaviour', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fretboard = container.read(fretboardProvider.notifier);
    final base = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [
        FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
      ],
      selectedNotes: const ['E'],
      viewMode: FretboardViewMode.exact,
    );

    fretboard.loadSnapshot(
      FretboardSnapshot(
        tuning: base.tuning,
        numFrets: base.numFrets,
        capo: base.capo,
        selectedCells: base.selectedCells,
        selectedNotes: base.selectedNotes,
        viewMode: base.viewMode,
        inputMode: FretboardInputMode.chord,
      ),
    );
    fretboard.toggleCell(0, 2, 'F#');
    expect(
      container.read(fretboardProvider).inputMode,
      FretboardInputMode.chord,
    );
    final chordCells = container.read(fretboardProvider).selectedCells;
    expect(chordCells, hasLength(1));
    expect(chordCells.single.stringIndex, 0);
    expect(chordCells.single.fret, 2);

    // A legacy snapshot defaults to Free and keeps both positions.
    fretboard.loadSnapshot(base);
    fretboard.toggleCell(0, 2, 'F#');
    expect(
      container.read(fretboardProvider).inputMode,
      FretboardInputMode.free,
    );
    expect(container.read(fretboardProvider).selectedCells, hasLength(2));
  });
}
