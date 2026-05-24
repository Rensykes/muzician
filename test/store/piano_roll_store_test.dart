import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/store/piano_roll_store.dart';

void main() {
  test('suggestedImportAnchorTick prefers the selected column', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.selectColumn(6);

    expect(notifier.suggestedImportAnchorTick(), 6);
  });

  test('suggestedImportAnchorTick falls back to the next measure boundary', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setTimeSignature(
      const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    );
    notifier.addNote(69, 9, 2);

    expect(notifier.suggestedImportAnchorTick(), 16);
  });

  test('appendImportedNotes expands the roll and selects imported notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setTotalMeasures(1);

    final result = notifier.appendImportedNotes(const [
      QuantizedHumNote(midiNote: 69, startTick: 14, durationTicks: 4),
      QuantizedHumNote(midiNote: 71, startTick: 18, durationTicks: 3),
    ]);

    final state = container.read(pianoRollProvider);
    expect(result.createdCount, 2);
    expect(result.truncated, isFalse);
    expect(state.config.totalMeasures, 2);
    expect(state.notes.map((n) => n.midiNote), [69, 71]);
    expect(state.selectedNoteIds, hasLength(2));
  });
}
