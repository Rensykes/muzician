/// Fretboard Riverpod Store
/// Equivalent of the Zustand fretboard-store.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/fretboard.dart';
import '../schema/rules/fretboard_rules.dart';

class FretboardNotifier extends Notifier<FretboardState> {
  @override
  FretboardState build() => getDefaultFretboardState();

  Tuning getCurrentTuning() => tunings[state.currentTuning]!;

  List<List<FretCell>> getFretCells() {
    final tuning = getCurrentTuning();
    return tuning.strings.asMap().entries.map((entry) {
      final stringIndex = entry.key;
      final stringTuning = entry.value;
      final cells = <FretCell>[];
      for (var fret = 0; fret <= state.numFrets; fret++) {
        final effectiveMidi = stringTuning.midiNote + state.capo;
        final noteName = getPitchClassAtFret(effectiveMidi, fret);
        final noteWithOctave = getNoteWithOctaveAtFret(effectiveMidi, fret);
        cells.add(FretCell(
          stringIndex: stringIndex,
          fret: fret,
          noteName: noteName,
          noteWithOctave: noteWithOctave,
          isNatural: isNaturalNote(noteName),
          midiNote: effectiveMidi + fret,
        ));
      }
      return cells;
    }).toList();
  }

  void setTuning(TuningName tuning) =>
      state = state.copyWith(currentTuning: tuning);

  void setNumFrets(int numFrets) {
    if (numFrets < 1 || numFrets > 24) return;
    state = state.copyWith(numFrets: numFrets);
  }

  void setCapo(int capo) {
    if (capo < 0 || capo > 11) return;
    state = state.copyWith(capo: capo);
  }

  void setHighlightedNotes(List<String> notes) =>
      state = state.copyWith(highlightedNotes: notes);

  void toggleCell(int stringIndex, int fret, String noteName) {
    final cells = state.selectedCells;
    List<FretCoordinate> newCells;
    if (state.viewMode == FretboardViewMode.exact ||
        state.viewMode == FretboardViewMode.exactFocus) {
      final idx = cells.indexWhere(
          (c) => c.stringIndex == stringIndex && c.fret == fret);
      if (idx >= 0) {
        newCells = List.of(cells)..removeAt(idx);
      } else {
        newCells = [
          ...cells,
          FretCoordinate(
              stringIndex: stringIndex, fret: fret, noteName: noteName)
        ];
      }
    } else {
      final hasPitchClass = cells.any((c) => c.noteName == noteName);
      newCells = hasPitchClass
          ? cells.where((c) => c.noteName != noteName).toList()
          : [
              ...cells,
              FretCoordinate(
                  stringIndex: stringIndex, fret: fret, noteName: noteName)
            ];
    }
    final newNotes = newCells.map((c) => c.noteName).toSet().toList();
    state = state.copyWith(selectedCells: newCells, selectedNotes: newNotes);
  }

  void clearSelectedNotes() => state = state.copyWith(
        selectedNotes: [],
        selectedCells: [],
        viewMode: FretboardViewMode.pitchClass,
      );

  void setViewMode(FretboardViewMode mode) =>
      state = state.copyWith(viewMode: mode);

  void loadVoicing(ChordVoicing voicing) {
    final tuning = tunings[state.currentTuning]!;
    final cells = <FretCoordinate>[];
    for (var i = 0; i < voicing.positions.length; i++) {
      final fret = voicing.positions[i];
      if (fret == null) continue;
      final effectiveMidi = tuning.strings[i].midiNote + state.capo;
      final noteName = getPitchClassAtFret(effectiveMidi, fret);
      cells.add(FretCoordinate(stringIndex: i, fret: fret, noteName: noteName));
    }
    final notes = cells.map((c) => c.noteName).toSet().toList();
    state = state.copyWith(
        selectedCells: cells,
        selectedNotes: notes,
        viewMode: FretboardViewMode.exact);
  }

  void reset() => state = getDefaultFretboardState();
}

final fretboardProvider =
    NotifierProvider<FretboardNotifier, FretboardState>(FretboardNotifier.new);

/// Pending chord (set by detection panel, consumed by pickers).
final pendingChordProvider =
    StateProvider<({String root, String quality})?>((_) => null);

/// Pending scale (set by detection panel, consumed by pickers).
final pendingScaleProvider =
    StateProvider<({String root, String scaleName})?>((_) => null);
