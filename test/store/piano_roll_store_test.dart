import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/piano_roll_store.dart';

void main() {
  test('suggestedImportAnchorTick prefers the selected column', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.selectColumn(6);

    expect(notifier.suggestedImportAnchorTick(), 6);
  });

  test('setKey(null) clears an existing key', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setKey('C');
    expect(container.read(pianoRollProvider).config.key, 'C');

    notifier.setKey(null);

    expect(container.read(pianoRollProvider).config.key, isNull);
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

  test(
    'setTotalMeasures keeps selected tick and suggested import anchor in range',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      // 4/4, 4 measures -> 64 ticks.
      notifier.selectColumn(60);
      expect(container.read(pianoRollProvider).selectedColumnTick, 60);

      // Shrink to 1 measure -> 16 ticks (max valid index = 15).
      notifier.setTotalMeasures(1);

      final state = container.read(pianoRollProvider);
      expect(state.selectedColumnTick, 15);
      expect(notifier.suggestedImportAnchorTick(), 15);
    },
  );

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

  group('loadSnapshot', () {
    test('restores config, notes, pitch window, snap, and selected column', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      final snap = PianoRollSnapshot(
        tempo: 90,
        key: 'A',
        numerator: 6,
        denominator: 8,
        totalMeasures: 12,
        notes: [
          {'midiNote': 69, 'startTick': 0, 'durationTicks': 4}, // A4
          {'midiNote': 73, 'startTick': 8, 'durationTicks': 4}, // C#5
          {'midiNote': 76, 'startTick': 16, 'durationTicks': 8}, // E5
        ],
        pitchRangeStart: 40,
        pitchRangeEnd: 88,
        selectedColumnTick: 8,
        snapTicks: 4,
        highlightedNotes: ['A', 'C#', 'E'],
      );

      notifier.loadSnapshot(snap);

      final state = container.read(pianoRollProvider);

      // Config
      expect(state.config.tempo, 90);
      expect(state.config.key, 'A');
      expect(state.config.timeSignature.beatsPerMeasure, 6);
      expect(state.config.timeSignature.beatUnit, 8);
      expect(state.config.totalMeasures, 12);

      // Notes
      expect(state.notes, hasLength(3));
      expect(state.notes[0].midiNote, 69);
      expect(state.notes[0].startTick, 0);
      expect(state.notes[0].durationTicks, 4);
      expect(state.notes[1].midiNote, 73);
      expect(state.notes[1].startTick, 8);
      expect(state.notes[2].midiNote, 76);
      expect(state.notes[2].startTick, 16);

      // Pitch range
      expect(state.pitchRangeStart, 40);
      expect(state.pitchRangeEnd, 88);

      // Selected column
      expect(state.selectedColumnTick, 8);

      // Snap
      expect(state.snapTicks, 4);

      // Highlighted notes
      expect(state.highlightedNotes, ['A', 'C#', 'E']);

      // Transient fields are reset
      expect(state.selectedNoteIds, isEmpty);
      expect(state.latestImportedRange, isNull);
    });

    test('loadSnapshot handles empty notes and null selected column', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      final snap = PianoRollSnapshot(
        tempo: 120,
        key: null,
        numerator: 4,
        denominator: 4,
        totalMeasures: 4,
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: null,
        snapTicks: 1,
        highlightedNotes: [],
      );

      notifier.loadSnapshot(snap);

      final state = container.read(pianoRollProvider);
      expect(state.notes, isEmpty);
      expect(state.selectedColumnTick, isNull);
      expect(state.highlightedNotes, isEmpty);
    });
  });
}
