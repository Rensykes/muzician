import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/fretboard_store.dart';

void main() {
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
