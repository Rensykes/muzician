import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll_composer.dart';
import 'package:muzician/store/piano_roll_composer_store.dart';
import 'package:muzician/store/piano_roll_store.dart';

void main() {
  // ── Defaults & mutations ─────────────────────────────────────────────────

  test('composer defaults to C major, quarter note duration', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(pianoRollComposerProvider);
    expect(state.root, 'C');
    expect(state.quality, '');
    expect(state.durationTicks, 4);
  });

  test('setRoot updates the root', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollComposerProvider.notifier);
    notifier.setRoot('G');
    expect(container.read(pianoRollComposerProvider).root, 'G');
  });

  test('setQuality updates the quality symbol', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollComposerProvider.notifier);
    notifier.setQuality('m');
    expect(container.read(pianoRollComposerProvider).quality, 'm');
  });

  test('setDuration updates the duration in ticks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollComposerProvider.notifier);
    notifier.setDuration(8);
    expect(container.read(pianoRollComposerProvider).durationTicks, 8);
  });

  // ── addStack with selected column ────────────────────────────────────────

  test('addStack places notes at selectedColumnTick when present', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final composerNotifier = container.read(pianoRollComposerProvider.notifier);
    composerNotifier.setRoot('C');
    composerNotifier.setQuality(''); // major triad: C, E, G
    composerNotifier.setDuration(4);

    // Set up piano roll with a selected column at tick 8
    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(48, 84); // C3-C5, so C major fits
    prNotifier.selectColumn(8);

    composerNotifier.addStack();

    final prState = container.read(pianoRollProvider);
    expect(prState.notes, isNotEmpty);
    // All notes should start at tick 8
    for (final note in prState.notes) {
      expect(note.startTick, 8);
    }
    // Selected column should remain at 8
    expect(prState.selectedColumnTick, 8);
  });

  // ── addStack fallback when no column selected ────────────────────────────

  test('addStack falls back to tick 0 when no column is selected', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final composerNotifier = container.read(pianoRollComposerProvider.notifier);
    composerNotifier.setRoot('D');
    composerNotifier.setQuality('m'); // D minor: D, F, A
    composerNotifier.setDuration(2);

    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(48, 84);
    // No selected column — falls back to 0

    composerNotifier.addStack();

    final prState = container.read(pianoRollProvider);
    expect(prState.notes, isNotEmpty);
    for (final note in prState.notes) {
      expect(note.startTick, 0);
    }
    // selectedColumnTick should now be set to 0
    expect(prState.selectedColumnTick, 0);
  });

  // ── addStack edge cases ──────────────────────────────────────────────────

  test(
    'addStack produces no notes when chord stack is empty (bad root/quality)',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final composerNotifier = container.read(
        pianoRollComposerProvider.notifier,
      );
      composerNotifier.setRoot('invalid');
      composerNotifier.setQuality('');

      final prNotifier = container.read(pianoRollProvider.notifier);
      prNotifier.setPitchRange(48, 84);

      final prevNoteCount = container.read(pianoRollProvider).notes.length;
      composerNotifier.addStack();

      // No notes should be added
      expect(container.read(pianoRollProvider).notes.length, prevNoteCount);
    },
  );

  test(
    'addStack produces no notes when pitch range cannot accommodate the chord',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final composerNotifier = container.read(
        pianoRollComposerProvider.notifier,
      );
      composerNotifier.setRoot('C');
      composerNotifier.setQuality('');

      // Set a pitch range that contains no chord tones
      final prNotifier = container.read(pianoRollProvider.notifier);
      prNotifier.setPitchRange(61, 62); // C#4-D4 — no C, E, or G fit

      final prevNoteCount = container.read(pianoRollProvider).notes.length;
      composerNotifier.addStack();

      expect(container.read(pianoRollProvider).notes.length, prevNoteCount);
    },
  );

  // ── Composer state reusability across widgets ────────────────────────────

  test('composer state is shared across multiple reads (reusable)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Simulate V1 reading
    final notifier = container.read(pianoRollComposerProvider.notifier);
    notifier.setRoot('A');
    notifier.setQuality('7');
    notifier.setDuration(16);

    // Simulate V2 reading
    final stateFromV2 = container.read(pianoRollComposerProvider);

    expect(stateFromV2.root, 'A');
    expect(stateFromV2.quality, '7');
    expect(stateFromV2.durationTicks, 16);
  });

  test('mutations from one consumer are visible to another', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Consumer A sets root
    container.read(pianoRollComposerProvider.notifier).setRoot('F#');

    // Consumer B sees the change
    expect(container.read(pianoRollComposerProvider).root, 'F#');

    // Consumer B sets quality
    container.read(pianoRollComposerProvider.notifier).setQuality('dim');

    // Consumer A sees the change
    expect(container.read(pianoRollComposerProvider).quality, 'dim');
  });

  // ── Quality label mapping ────────────────────────────────────────────────

  test('qualityLabelBySymbol maps major (empty string) to "maj"', () {
    expect(qualityLabelBySymbol[''], 'maj');
  });

  test('qualitySymbolByLabel maps "maj" to empty string', () {
    expect(qualitySymbolByLabel['maj'], '');
  });

  test('qualityLabelBySymbol and qualitySymbolByLabel are inverses', () {
    for (final entry in qualityLabelBySymbol.entries) {
      expect(qualitySymbolByLabel[entry.value], entry.key);
    }
  });

  // ── Duration label mapping ───────────────────────────────────────────────

  test('labelToDurationTicks maps "1/4" to 4 ticks', () {
    expect(labelToDurationTicks['1/4'], 4);
  });

  test('durationTicksToLabel maps 4 ticks to "1/4"', () {
    expect(durationTicksToLabel[4], '1/4');
  });

  test('durationTicksToLabel and labelToDurationTicks are inverses', () {
    for (final entry in labelToDurationTicks.entries) {
      expect(durationTicksToLabel[entry.value], entry.key);
    }
  });

  // ── addStack with note count verification ────────────────────────────────

  test('addStack produces correct note count for a major triad', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final composerNotifier = container.read(pianoRollComposerProvider.notifier);
    composerNotifier.setRoot('C');
    composerNotifier.setQuality(''); // major: C, E, G → 3 notes
    composerNotifier.setDuration(4);

    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(36, 96); // wide enough

    composerNotifier.addStack();

    expect(container.read(pianoRollProvider).notes.length, 3);
  });

  test('addStack selects the destination column after placing notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final composerNotifier = container.read(pianoRollComposerProvider.notifier);
    composerNotifier.setRoot('C');
    composerNotifier.setQuality('');

    final prNotifier = container.read(pianoRollProvider.notifier);
    prNotifier.setPitchRange(36, 96);
    prNotifier.selectColumn(12);

    composerNotifier.addStack();

    final prState = container.read(pianoRollProvider);
    // addNoteStack does not set selectedNoteIds; addStack selects the column.
    expect(prState.selectedColumnTick, 12);
    expect(prState.notes, isNotEmpty);
  });
}
