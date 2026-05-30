import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/schema/rules/piano_roll_rules.dart' as rules;
import 'package:muzician/store/piano_roll_store.dart';

PianoRollNote _note(int midi, int startTick) => PianoRollNote(
      id: 'n$midi-$startTick',
      midiNote: midi,
      pitchClass: rules.midiToPitchClass(midi),
      noteWithOctave: rules.midiToNoteWithOctave(midi),
      startTick: startTick,
      durationTicks: 1,
    );

class _SeededNotifier extends PianoRollNotifier {
  _SeededNotifier(this.seed);
  final PianoRollState seed;
  @override
  PianoRollState build() => seed;
}

ProviderContainer _containerWith(PianoRollState state) {
  final c = ProviderContainer(
    overrides: [pianoRollProvider.overrideWith(() => _SeededNotifier(state))],
  );
  return c;
}

void main() {
  group('PianoRollNotifier.firstEmptyColumnTick', () {
    test('returns 0 when there are no notes', () {
      final base = rules.getDefaultPianoRollState();
      final c = _containerWith(base.copyWith(notes: [], snapTicks: 1));
      addTearDown(c.dispose);
      expect(
        c.read(pianoRollProvider.notifier).firstEmptyColumnTick(),
        0,
      );
    });

    test('skips an occupied first column (snap 1)', () {
      final base = rules.getDefaultPianoRollState();
      final c = _containerWith(
        base.copyWith(notes: [_note(60, 0)], snapTicks: 1),
      );
      addTearDown(c.dispose);
      expect(
        c.read(pianoRollProvider.notifier).firstEmptyColumnTick(),
        1,
      );
    });

    test('lands on the next free snap column (snap 2)', () {
      final base = rules.getDefaultPianoRollState();
      final c = _containerWith(
        base.copyWith(notes: [_note(60, 0)], snapTicks: 2),
      );
      addTearDown(c.dispose);
      // tick 0 occupied; next grid column at snap 2 is empty.
      expect(
        c.read(pianoRollProvider.notifier).firstEmptyColumnTick(),
        2,
      );
    });

    test('returns the first gap between occupied columns', () {
      final base = rules.getDefaultPianoRollState();
      final c = _containerWith(
        base.copyWith(
          notes: [_note(60, 0), _note(62, 1), _note(64, 3)],
          snapTicks: 1,
        ),
      );
      addTearDown(c.dispose);
      expect(
        c.read(pianoRollProvider.notifier).firstEmptyColumnTick(),
        2,
      );
    });
  });
}
