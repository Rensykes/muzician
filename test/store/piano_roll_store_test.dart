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

  test('clearSelection empties selectedNoteIds without clearing column', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.addNote(60, 4, 2);
    notifier.selectColumn(4);
    final selectedId = container.read(pianoRollProvider).notes.single.id;
    notifier.setSelection({selectedId});

    notifier.clearSelection();

    final state = container.read(pianoRollProvider);
    expect(state.selectedNoteIds, isEmpty);
    expect(state.selectedColumnTick, 4);
  });

  test('deleteSelectedNotes removes only selected notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.addNote(60, 1, 2);
    final firstId = container.read(pianoRollProvider).notes.single.id;
    notifier.addNote(64, 5, 2);
    final notes = container.read(pianoRollProvider).notes;
    final secondId = notes.firstWhere((note) => note.id != firstId).id;
    notifier.setSelection({firstId});

    notifier.deleteSelectedNotes();

    final state = container.read(pianoRollProvider);
    expect(state.notes.map((note) => note.id), {secondId});
    expect(state.selectedNoteIds, isEmpty);
  });

  test('selectNotesAtTick selects every active note at the tick', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.addNote(60, 2, 4); // Active at tick 3.
    final firstId = container.read(pianoRollProvider).notes.single.id;
    notifier.addNote(64, 3, 2); // Active at tick 3.
    final notes = container.read(pianoRollProvider).notes;
    final secondId = notes.firstWhere((note) => note.id != firstId).id;
    notifier.addNote(67, 7, 1); // Not active at tick 3.

    notifier.selectNotesAtTick(3);

    final state = container.read(pianoRollProvider);
    expect(state.selectedNoteIds, {firstId, secondId});
    expect(state.selectedColumnTick, 3);
  });

  test(
    'active scale blocks adding notes outside highlighted pitch classes',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      notifier.setHighlightedNotes(['C', 'E', 'G']);

      notifier.addNote(61, 0, 1);

      expect(container.read(pianoRollProvider).notes, isEmpty);

      notifier.addNote(60, 0, 1);

      final state = container.read(pianoRollProvider);
      expect(state.notes, hasLength(1));
      expect(state.notes.single.pitchClass, 'C');
    },
  );

  test('active scale blocks moving a note to an out-of-scale pitch', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.addNote(60, 2, 2);
    final original = container.read(pianoRollProvider).notes.single;
    notifier.setHighlightedNotes(['C', 'E', 'G']);

    notifier.moveNote(original.id, 6, 61);

    final moved = container.read(pianoRollProvider).notes.single;
    expect(moved.midiNote, 60);
    expect(moved.startTick, 2);
  });

  test(
    'active scale rejects a multi-note move unless the whole batch fits',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      notifier.addNote(60, 2, 2); // C
      final firstId = container.read(pianoRollProvider).notes.single.id;
      notifier.addNote(64, 2, 2); // E
      final secondId = container
          .read(pianoRollProvider)
          .notes
          .firstWhere((note) => note.id != firstId)
          .id;
      notifier.setHighlightedNotes(['C', 'D', 'E', 'F', 'G', 'A', 'B']);

      notifier.moveNotesBatch([
        (id: firstId, startTick: 6, midiNote: 61), // C# -> out of scale
        (id: secondId, startTick: 6, midiNote: 65), // F -> in scale
      ]);

      final state = container.read(pianoRollProvider);
      final first = state.notes.firstWhere((note) => note.id == firstId);
      final second = state.notes.firstWhere((note) => note.id == secondId);
      expect(first.midiNote, 60);
      expect(first.startTick, 2);
      expect(second.midiNote, 64);
      expect(second.startTick, 2);
    },
  );

  test('active scale rejects stacks containing out-of-scale notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setHighlightedNotes(['C', 'E', 'G']);

    notifier.addNoteStack([60, 64, 70], 4, 2);

    expect(container.read(pianoRollProvider).notes, isEmpty);

    notifier.addNoteStack([60, 64, 67], 4, 2);

    final state = container.read(pianoRollProvider);
    expect(state.notes, hasLength(3));
    expect(state.notes.map((note) => note.pitchClass).toSet(), {'C', 'E', 'G'});
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

  test('resizeNotesBatch updates multiple notes and clamps independently', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setTotalMeasures(1); // 16 ticks
    notifier.addNote(60, 2, 2);
    final firstId = container.read(pianoRollProvider).notes.single.id;
    notifier.addNote(64, 14, 1);
    final secondId = container
        .read(pianoRollProvider)
        .notes
        .firstWhere((note) => note.id != firstId)
        .id;
    notifier.addNote(67, 4, 3);
    final thirdId = container
        .read(pianoRollProvider)
        .notes
        .firstWhere((note) => note.id != firstId && note.id != secondId)
        .id;
    notifier.setSelection({firstId, secondId});
    notifier.selectColumn(9);

    notifier.resizeNotesBatch([
      (id: firstId, durationTicks: 0),
      (id: secondId, durationTicks: 8),
    ]);

    final state = container.read(pianoRollProvider);
    final first = state.notes.firstWhere((note) => note.id == firstId);
    final second = state.notes.firstWhere((note) => note.id == secondId);
    final third = state.notes.firstWhere((note) => note.id == thirdId);
    expect(first.durationTicks, 1);
    expect(second.durationTicks, 2);
    expect(third.durationTicks, 3);
    expect(state.selectedNoteIds, {firstId, secondId});
    expect(state.selectedColumnTick, 9);
  });

  test('splitSelectedNotesAtTick splits all eligible selected notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.addNote(60, 2, 6); // spans 2..8
    final firstId = container.read(pianoRollProvider).notes.single.id;
    notifier.addNote(64, 4, 5); // spans 4..9
    final secondId = container
        .read(pianoRollProvider)
        .notes
        .firstWhere((note) => note.id != firstId)
        .id;
    notifier.setSelection({firstId, secondId});
    notifier.selectColumn(11);
    notifier.rememberLatestImportedRange(24, 32);

    notifier.splitSelectedNotesAtTick(6);

    final state = container.read(pianoRollProvider);
    final firstLeft = state.notes.firstWhere((note) => note.id == firstId);
    final secondLeft = state.notes.firstWhere((note) => note.id == secondId);
    final rightHalves = state.notes
        .where(
          (note) =>
              note.startTick == 6 &&
              (note.midiNote == 60 || note.midiNote == 64),
        )
        .toList();

    expect(firstLeft.durationTicks, 4);
    expect(secondLeft.durationTicks, 2);
    expect(rightHalves, hasLength(2));
    expect(rightHalves.map((note) => note.durationTicks).toSet(), {2, 3});
    expect(state.selectedNoteIds, rightHalves.map((note) => note.id).toSet());
    expect(state.latestImportedRange, isNull);
    expect(state.selectedColumnTick, 11);
  });

  test('splitSelectedNotesAtTick keeps untouched selected notes selected', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.addNote(60, 2, 6); // splittable at 6
    final splittableId = container.read(pianoRollProvider).notes.single.id;
    notifier.addNote(67, 10, 2); // not splittable at 6
    final untouchedId = container
        .read(pianoRollProvider)
        .notes
        .firstWhere((note) => note.id != splittableId)
        .id;
    notifier.setSelection({splittableId, untouchedId});

    notifier.splitSelectedNotesAtTick(6);

    final state = container.read(pianoRollProvider);
    final rightHalf = state.notes
        .where((note) => note.midiNote == 60 && note.startTick == 6)
        .single;
    expect(state.selectedNoteIds, {rightHalf.id, untouchedId});
  });

  test(
    'splitSelectedNotesAtTick is a no-op when nothing selected can split',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pianoRollProvider.notifier);
      notifier.addNote(60, 2, 2); // spans 2..4
      final selectedId = container.read(pianoRollProvider).notes.single.id;
      notifier.setSelection({selectedId});
      notifier.selectColumn(5);
      notifier.rememberLatestImportedRange(24, 32);
      final before = container.read(pianoRollProvider);

      notifier.splitSelectedNotesAtTick(8);

      final after = container.read(pianoRollProvider);
      expect(after.notes, before.notes);
      expect(after.selectedNoteIds, before.selectedNoteIds);
      expect(after.latestImportedRange, before.latestImportedRange);
      expect(after.selectedColumnTick, before.selectedColumnTick);
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
