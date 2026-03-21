/// Piano Roll Schema Rules
/// Timeline helpers, validation, and defaults.

import '../../models/piano_roll.dart';

const chromaticSharp = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

const ticksPerQuarter = 4;
const minTempo = 20;
const maxTempo = 300;
const minMidi = 21;
const maxMidi = 108;

String midiToPitchClass(int midi) {
  final pc = ((midi % 12) + 12) % 12;
  return chromaticSharp[pc];
}

String midiToNoteWithOctave(int midi) {
  final octave = (midi ~/ 12) - 1;
  return '${midiToPitchClass(midi)}$octave';
}

int ticksPerMeasure(TimeSignature ts) {
  final beatTicks = ts.beatUnit == 8 ? 2 : 4;
  return ts.beatsPerMeasure * beatTicks;
}

int totalTicks(TimeSignature ts, int totalMeasures) {
  return ticksPerMeasure(ts) * totalMeasures;
}

List<PianoRollNote> getNotesAtTick(List<PianoRollNote> notes, int tick) {
  return notes
      .where((n) => n.startTick <= tick && tick < n.startTick + n.durationTicks)
      .toList();
}

({bool valid, List<String> errors}) validateTimeSignature(TimeSignature ts) {
  final errors = <String>[];
  if (ts.beatsPerMeasure < 1 || ts.beatsPerMeasure > 12) {
    errors.add('beatsPerMeasure must be between 1 and 12');
  }
  if (ts.beatUnit != 4 && ts.beatUnit != 8) {
    errors.add('beatUnit must be 4 or 8');
  }
  return (valid: errors.isEmpty, errors: errors);
}

PianoRollState getDefaultPianoRollState() => const PianoRollState(
      config: PianoRollConfig(
        tempo: 120,
        key: null,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 4,
      ),
      notes: [],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      selectedNoteId: null,
    );
