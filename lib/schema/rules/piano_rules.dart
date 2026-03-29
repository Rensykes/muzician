/// Piano Schema Rules
/// Keyboard presets, note helpers, and validation.
library;

import '../../models/piano.dart';
import '../../utils/note_utils.dart';

export '../../utils/note_utils.dart' show chromaticNotes, isNaturalNote;

const pianoRanges = <PianoRangeName, PianoRange>{
  PianoRangeName.key88: PianoRange(
    name: PianoRangeName.key88,
    displayName: '88 Keys (A0-C8)',
    startMidi: 21,
    endMidi: 108,
  ),
  PianoRangeName.key61: PianoRange(
    name: PianoRangeName.key61,
    displayName: '61 Keys (C2-C7)',
    startMidi: 36,
    endMidi: 96,
  ),
  PianoRangeName.key49: PianoRange(
    name: PianoRangeName.key49,
    displayName: '49 Keys (C2-C6)',
    startMidi: 36,
    endMidi: 84,
  ),
};

String midiToPitchClass(int midi) {
  final pc = ((midi % 12) + 12) % 12;
  return chromaticNotes[pc];
}

String midiToNoteWithOctave(int midi) {
  final octave = (midi ~/ 12) - 1;
  return '${midiToPitchClass(midi)}$octave';
}

bool isBlackMidiKey(int midi) {
  final pc = ((midi % 12) + 12) % 12;
  return [1, 3, 6, 8, 10].contains(pc);
}

List<PianoKeyCell> getKeysForRange(PianoRangeName rangeName) {
  final range = pianoRanges[rangeName]!;
  final keys = <PianoKeyCell>[];
  for (var midi = range.startMidi; midi <= range.endMidi; midi++) {
    final noteName = midiToPitchClass(midi);
    keys.add(
      PianoKeyCell(
        keyIndex: keys.length,
        midiNote: midi,
        noteName: noteName,
        noteWithOctave: midiToNoteWithOctave(midi),
        octave: (midi ~/ 12) - 1,
        isNatural: isNaturalNote(noteName),
        isBlack: isBlackMidiKey(midi),
      ),
    );
  }
  return keys;
}

PianoState getDefaultPianoState() => const PianoState(
  currentRange: PianoRangeName.key61,
  highlightedNotes: [],
  selectedNotes: [],
  selectedKeys: [],
  viewMode: PianoViewMode.exact,
);
