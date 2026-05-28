import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll_stack_builder.dart';
import 'package:muzician/store/piano_roll_stack_builder_store.dart';
import 'package:muzician/store/piano_roll_store.dart';

void main() {
  // ── Default state ───────────────────────────────────────────────────────

  test('default state is C major triad in canonical view', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes, [60, 64, 67]);
    expect(state.durationTicks, 4);
    expect(state.activeView, PianoRollStackBuilderView.canonical);
    expect(state.recognition.isRecognized, true);
    expect(state.recognition.recognizedRoot, 'C');
    expect(state.recognition.recognizedQuality, '');
    expect(state.errorMessage, isNull);
  });

  // ── View switching ─────────────────────────────────────────────────────

  test('switchView preserves final notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.switchView(PianoRollStackBuilderView.advanced);
    expect(
      container.read(pianoRollStackBuilderProvider).activeView,
      PianoRollStackBuilderView.advanced,
    );
    expect(container.read(pianoRollStackBuilderProvider).midiNotes, [
      60,
      64,
      67,
    ]);

    notifier.switchView(PianoRollStackBuilderView.canonical);
    expect(
      container.read(pianoRollStackBuilderProvider).activeView,
      PianoRollStackBuilderView.canonical,
    );
  });

  // ── Canonical edits ────────────────────────────────────────────────────

  test('setCanonicalRoot retargets without resetting note count', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.setCanonicalRoot('G');
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes.length, 3);
    final pcs = state.midiNotes.map((m) => m % 12).toSet();
    expect(pcs, containsAll([7, 11, 2]));
  });

  test('setCanonicalQuality retargets to new quality', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.setCanonicalQuality('m');
    final state = container.read(pianoRollStackBuilderProvider);
    final pcs = state.midiNotes.map((m) => m % 12).toSet();
    expect(pcs, containsAll([0, 3, 7]));
  });

  test('setCanonicalInversion changes inversion', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.setCanonicalInversion(1);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes[0] % 12, 4);
    expect(state.midiNotes[1] % 12, 7);
    expect(state.midiNotes[2] % 12, 0);
  });

  test('setDurationTicks updates duration', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.setDurationTicks(8);
    expect(container.read(pianoRollStackBuilderProvider).durationTicks, 8);
  });

  // ── Advanced edits ─────────────────────────────────────────────────────

  test('addAbsoluteNote adds to note list', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    final ok = notifier.addAbsoluteNote(72);
    expect(ok, true);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes, [60, 64, 67, 72]);
    expect(state.errorMessage, isNull);
  });

  test('addAbsoluteNote rejects exact duplicate with error', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    final ok = notifier.addAbsoluteNote(60);
    expect(ok, false);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes, [60, 64, 67]);
    expect(state.errorMessage, contains('C4'));
  });

  test('duplicate flat note error uses the same flat spelling as picker', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    expect(notifier.addAbsoluteNote(61), true);
    expect(notifier.addAbsoluteNote(61), false);

    expect(
      container.read(pianoRollStackBuilderProvider).errorMessage,
      contains('Db4'),
    );
  });

  test('addAbsoluteNote accepts different octave of same pitch class', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    final ok = notifier.addAbsoluteNote(72);
    expect(ok, true);
    expect(container.read(pianoRollStackBuilderProvider).midiNotes, [
      60,
      64,
      67,
      72,
    ]);
  });

  test('addAbsoluteNote enforces 10-note limit', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.replaceAllNotes(List<int>.generate(10, (i) => 60 + i));
    final ok = notifier.addAbsoluteNote(80);
    expect(ok, false);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes.length, 10);
    expect(state.errorMessage, contains('Maximum 10'));
  });

  test('replaceNoteAt replaces a note', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    final ok = notifier.replaceNoteAt(0, 65);
    expect(ok, true);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes[0], 65);
  });

  test('replaceNoteAt rejects duplicate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.addAbsoluteNote(72);
    final ok = notifier.replaceNoteAt(1, 60);
    expect(ok, false);
    expect(
      container.read(pianoRollStackBuilderProvider).errorMessage,
      isNotNull,
    );
  });

  test('duplicateNoteAt is removed — addAbsoluteNote used instead', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.replaceAllNotes([60, 64, 67, 72]);
    notifier.addAbsoluteNote(60);
    expect(
      container.read(pianoRollStackBuilderProvider).errorMessage,
      contains('C4'),
    );
  });

  test('removeNoteAt removes note at index', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.removeNoteAt(1);
    expect(container.read(pianoRollStackBuilderProvider).midiNotes, [60, 67]);
  });

  test('reorderNotes updates order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.addAbsoluteNote(72);
    notifier.reorderNotes(3, 1);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes[0], 60);
    expect(state.midiNotes[1], 72);
    expect(state.midiNotes[2], 64);
    expect(state.midiNotes[3], 67);
  });

  test('insertDegreeShortcut resolves degree relative to recognized chord', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.insertDegreeShortcut('5');
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes.length, 4);
    expect(state.midiNotes[3] % 12, 7);
    expect(state.midiNotes[3], greaterThan(67));
  });

  // ── lastAdded tracking ─────────────────────────────────────────────────

  test('addStack updates lastAddedNotes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(48, 84);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.setCanonicalRoot('G');
    notifier.setDurationTicks(8);
    notifier.addStack();

    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.lastAddedNotes, isNotEmpty);
    expect(state.lastAddedDurationTicks, 8);
  });

  // ── Add Stack ──────────────────────────────────────────────────────────

  test('addStack inserts current builder notes at selected column tick', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(48, 84);
    prNotifier.selectColumn(8);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.setCanonicalRoot('G');
    notifier.setDurationTicks(4);
    notifier.addStack();

    final prState = container.read(pianoRollProvider);
    expect(prState.notes, isNotEmpty);
    for (final note in prState.notes) {
      expect(note.startTick, 8);
      expect(note.durationTicks, 4);
    }
  });

  test('addStack fallbacks to tick 0 when no column selected', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(48, 84);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.addStack();

    final prState = container.read(pianoRollProvider);
    expect(prState.notes, isNotEmpty);
    for (final note in prState.notes) {
      expect(note.startTick, 0);
    }
  });

  // ── replaceAllNotes helper ─────────────────────────────────────────────

  test('replaceAllNotes replaces all notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollStackBuilderProvider.notifier);
    notifier.replaceAllNotes([62, 65, 69]);
    final state = container.read(pianoRollStackBuilderProvider);
    expect(state.midiNotes, [62, 65, 69]);
    expect(state.recognition.recognizedRoot, 'D');
    expect(state.recognition.recognizedQuality, 'm');
  });
}
