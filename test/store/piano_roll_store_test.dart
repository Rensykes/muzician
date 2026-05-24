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

  test(
    'appendImportedNotes expands when furthestEndTick crosses current end',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      // 4/4, 1 measure = 16 ticks
      notifier.setTotalMeasures(1);

      final result = notifier.appendImportedNotes(const [
        QuantizedHumNote(midiNote: 60, startTick: 13, durationTicks: 4),
      ]);

      // furthestEndTick = 13 + 4 = 17 > 16
      expect(result.createdCount, 1);
      expect(result.truncated, isFalse);
      expect(result.firstStartTick, 13);
      expect(result.furthestEndTick, 17);
      // 2 measures = 32 ticks
      expect(container.read(pianoRollProvider).config.totalMeasures, 2);
    },
  );

  test(
    'appendImportedNotes does NOT expand when furthestEndTick equals current total ticks',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      // 4/4, 1 measure = 16 ticks
      notifier.setTotalMeasures(1);

      final result = notifier.appendImportedNotes(const [
        QuantizedHumNote(midiNote: 60, startTick: 12, durationTicks: 4),
      ]);

      // furthestEndTick = 12 + 4 = 16, equals 1 measure's totalTicks
      expect(result.createdCount, 1);
      expect(result.truncated, isFalse);
      expect(result.firstStartTick, 12);
      expect(result.furthestEndTick, 16);
      // Still 1 measure — no expansion
      expect(container.read(pianoRollProvider).config.totalMeasures, 1);
    },
  );

  test('appendImportedNotes leaves selectedColumnTick untouched', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.selectColumn(8);
    expect(container.read(pianoRollProvider).selectedColumnTick, 8);

    notifier.appendImportedNotes(const [
      QuantizedHumNote(midiNote: 60, startTick: 4, durationTicks: 2),
    ]);

    expect(container.read(pianoRollProvider).selectedColumnTick, 8);
  });

  test('appendImportedNotes leaves latestImportedRange untouched', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.rememberLatestImportedRange(24, 32);

    notifier.appendImportedNotes(const [
      QuantizedHumNote(midiNote: 69, startTick: 8, durationTicks: 2),
    ]);

    final range = container.read(pianoRollProvider).latestImportedRange;
    expect(range?.startTick, 24);
    expect(range?.endTickExclusive, 32);
  });

  test(
    'addNote clears latestImportedRange because it creates a new manual note',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      notifier.rememberLatestImportedRange(24, 32);

      notifier.addNote(72, 12, 1);

      expect(container.read(pianoRollProvider).latestImportedRange, isNull);
    },
  );

  test(
    'splitNote clears latestImportedRange because it creates a new manual note',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      notifier.addNote(72, 12, 4);
      final noteId = container.read(pianoRollProvider).notes.single.id;
      notifier.rememberLatestImportedRange(24, 32);

      notifier.splitNote(noteId, 14);

      expect(container.read(pianoRollProvider).latestImportedRange, isNull);
    },
  );

  test(
    'appendImportedNotes reports the actual created end tick after truncation',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      notifier.setTotalMeasures(32);

      final result = notifier.appendImportedNotes(const [
        QuantizedHumNote(midiNote: 72, startTick: 510, durationTicks: 16),
      ]);

      expect(result.truncated, isTrue);
      expect(result.firstStartTick, 510);
      expect(result.furthestEndTick, 512);
    },
  );
}
