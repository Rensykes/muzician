# Piano Roll Latest Import Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Jump to latest` action for the most recent hum import, and guarantee that hum recording imports remain one-note-at-a-time after quantization.

**Architecture:** Keep monophonic import normalization in `lib/schema/rules/mono_pitch_rules.dart`, store the remembered latest-import target in `PianoRollState`, let `HumToMidiNotifier` own the import-to-navigation handoff, and wire the Hum to MIDI card to the existing `pianoRollScrollToTickProvider` without changing selection or playback state. Clear the remembered import target only when a later non-import note-add action occurs or the piano roll is fully cleared/reset.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, immutable state in `lib/models/`, pure Dart rules in `lib/schema/rules/`, `flutter_test`

---

## File Structure

### Modify

- `lib/models/piano_roll.dart`
  Add a small immutable `PianoRollImportedRange` value object and store it in `PianoRollState`.
- `lib/schema/rules/mono_pitch_rules.dart`
  Add a pure normalization helper that keeps quantized hum imports strictly monophonic.
- `lib/store/piano_roll_store.dart`
  Add remembered-import range helpers, clear the range on non-import note-add flows, and ensure import results report the actual created range after truncation.
- `lib/store/hum_to_midi_store.dart`
  Normalize quantized hum notes before append, remember the final imported range after successful import, and clear stale remembered range when an import creates no notes.
- `lib/features/piano_roll/piano_roll_hum_recorder.dart`
  Show `Jump to latest` in the Hum to MIDI card and emit the existing scroll-to-tick signal without changing selection.
- `docs/piano_roll.md`
  Document `Jump to latest` and the post-quantization monophonic import rule.

### Tests

- `test/schema/rules/mono_pitch_rules_test.dart`
  Regression coverage for overlap trimming and same-tick drop behavior.
- `test/store/piano_roll_store_test.dart`
  State coverage for remembered-import range ownership, clearing rules, and created-range reporting.
- `test/store/hum_to_midi_store_test.dart`
  Integration coverage for successful import, replacement, and stale-target clearing.
- `test/features/piano_roll/piano_roll_hum_recorder_test.dart`
  Widget coverage for button visibility and jump behavior.

## Task 1: Add Pure Monophonic Import Normalization

**Primary specialist:** `state-architect`

**Files:**
- Modify: `lib/schema/rules/mono_pitch_rules.dart`
- Test: `test/schema/rules/mono_pitch_rules_test.dart`

- [ ] **Step 1: Write the failing rule tests**

```dart
test('normalizes overlapping imported hum notes into a one-note sequence', () {
  const imported = <QuantizedHumNote>[
    QuantizedHumNote(midiNote: 69, startTick: 8, durationTicks: 4),
    QuantizedHumNote(midiNote: 71, startTick: 10, durationTicks: 4),
  ];

  final normalized = rules.normalizeQuantizedHumNotesMonophonically(imported);

  expect(normalized, hasLength(2));
  expect(normalized[0].midiNote, 69);
  expect(normalized[0].startTick, 8);
  expect(normalized[0].durationTicks, 2);
  expect(normalized[1].midiNote, 71);
  expect(normalized[1].startTick, 10);
  expect(normalized[1].durationTicks, 4);
});

test('drops the earlier imported hum note when two notes quantize to the same tick', () {
  const imported = <QuantizedHumNote>[
    QuantizedHumNote(midiNote: 69, startTick: 12, durationTicks: 2),
    QuantizedHumNote(midiNote: 71, startTick: 12, durationTicks: 3),
  ];

  final normalized = rules.normalizeQuantizedHumNotesMonophonically(imported);

  expect(normalized, hasLength(1));
  expect(normalized.single.midiNote, 71);
  expect(normalized.single.startTick, 12);
  expect(normalized.single.durationTicks, 3);
});
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `flutter test test/schema/rules/mono_pitch_rules_test.dart`

Expected: FAIL with `Undefined name 'normalizeQuantizedHumNotesMonophonically'` or equivalent missing-helper errors.

- [ ] **Step 3: Add the minimal normalization helper**

```dart
List<QuantizedHumNote> normalizeQuantizedHumNotesMonophonically(
  List<QuantizedHumNote> notes,
) {
  final indexed = <({int index, QuantizedHumNote note})>[
    for (var i = 0; i < notes.length; i++) (index: i, note: notes[i]),
  ]..sort((a, b) {
      final byTick = a.note.startTick.compareTo(b.note.startTick);
      return byTick != 0 ? byTick : a.index.compareTo(b.index);
    });

  final normalized = <QuantizedHumNote>[];

  for (final entry in indexed) {
    final note = entry.note;
    if (normalized.isNotEmpty) {
      final previous = normalized.last;
      final previousEnd = previous.startTick + previous.durationTicks;

      if (note.startTick < previousEnd) {
        final trimmedDuration = note.startTick - previous.startTick;

        if (trimmedDuration <= 0) {
          normalized.removeLast();
        } else {
          normalized[normalized.length - 1] = QuantizedHumNote(
            midiNote: previous.midiNote,
            startTick: previous.startTick,
            durationTicks: trimmedDuration,
          );
        }
      }
    }

    normalized.add(note);
  }

  return normalized;
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `flutter test test/schema/rules/mono_pitch_rules_test.dart`

Expected: PASS for the new overlap-trimming and same-tick-drop cases, with existing mono-pitch tests still green.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/mono_pitch_rules.dart test/schema/rules/mono_pitch_rules_test.dart
git commit -m "fix: normalize hum imports into a mono sequence"
```

## Task 2: Store And Clear The Latest Imported Range In Piano Roll State

**Primary specialist:** `state-architect`

**Files:**
- Modify: `lib/models/piano_roll.dart`
- Modify: `lib/store/piano_roll_store.dart`
- Test: `test/store/piano_roll_store_test.dart`

- [ ] **Step 1: Write the failing piano-roll store tests**

```dart
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

test('addNote clears latestImportedRange because it creates a new manual note', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(pianoRollProvider.notifier);
  notifier.rememberLatestImportedRange(24, 32);

  notifier.addNote(72, 12, 1);

  expect(container.read(pianoRollProvider).latestImportedRange, isNull);
});

test('splitNote clears latestImportedRange because it creates a new manual note', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(pianoRollProvider.notifier);
  notifier.addNote(72, 12, 4);
  final noteId = container.read(pianoRollProvider).notes.single.id;
  notifier.rememberLatestImportedRange(24, 32);

  notifier.splitNote(noteId, 14);

  expect(container.read(pianoRollProvider).latestImportedRange, isNull);
});

test('appendImportedNotes reports the actual created end tick after truncation', () {
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
});
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `flutter test test/store/piano_roll_store_test.dart`

Expected: FAIL with missing `latestImportedRange` state, missing range helpers, and incorrect `furthestEndTick` semantics.

- [ ] **Step 3: Add the immutable range model and clearing helpers**

```dart
class PianoRollImportedRange {
  final int startTick;
  final int endTickExclusive;

  const PianoRollImportedRange({
    required this.startTick,
    required this.endTickExclusive,
  });
}

class PianoRollState {
  final PianoRollImportedRange? latestImportedRange;

  const PianoRollState({
    required this.config,
    required this.notes,
    required this.pitchRangeStart,
    required this.pitchRangeEnd,
    this.selectedColumnTick,
    this.selectedNoteIds = const <String>{},
    this.activeTool = PianoRollTool.draw,
    this.snapTicks = 1,
    this.highlightedNotes = const <String>[],
    this.latestImportedRange,
  });

  PianoRollState copyWith({
    PianoRollConfig? config,
    List<PianoRollNote>? notes,
    int? pitchRangeStart,
    int? pitchRangeEnd,
    int? Function()? selectedColumnTick,
    Set<String>? selectedNoteIds,
    PianoRollTool? activeTool,
    int? snapTicks,
    List<String>? highlightedNotes,
    PianoRollImportedRange? Function()? latestImportedRange,
  }) => PianoRollState(
    config: config ?? this.config,
    notes: notes ?? this.notes,
    pitchRangeStart: pitchRangeStart ?? this.pitchRangeStart,
    pitchRangeEnd: pitchRangeEnd ?? this.pitchRangeEnd,
    selectedColumnTick: selectedColumnTick != null
        ? selectedColumnTick()
        : this.selectedColumnTick,
    selectedNoteIds: selectedNoteIds ?? this.selectedNoteIds,
    activeTool: activeTool ?? this.activeTool,
    snapTicks: snapTicks ?? this.snapTicks,
    highlightedNotes: highlightedNotes ?? this.highlightedNotes,
    latestImportedRange: latestImportedRange != null
        ? latestImportedRange()
        : this.latestImportedRange,
  );
}
```

```dart
void rememberLatestImportedRange(int startTick, int endTickExclusive) {
  state = state.copyWith(
    latestImportedRange: () => PianoRollImportedRange(
      startTick: startTick,
      endTickExclusive: endTickExclusive,
    ),
  );
}

void clearLatestImportedRange() {
  state = state.copyWith(latestImportedRange: () => null);
}

void _clearLatestImportedRangeForNewNote() {
  if (state.latestImportedRange == null) return;
  clearLatestImportedRange();
}
```

- [ ] **Step 4: Clear the remembered range only on non-import note creation and report created bounds**

```dart
void addNote(int midiNote, int startTick, int durationTicks) {
  final maxTick = rules.totalTicks(
    state.config.timeSignature,
    state.config.totalMeasures,
  );
  if (startTick < 0 || startTick >= maxTick) return;
  final safeDuration = durationTicks.clamp(1, maxTick - startTick);
  final note = PianoRollNote(
    id: _makeId(),
    midiNote: midiNote,
    pitchClass: rules.midiToPitchClass(midiNote),
    noteWithOctave: rules.midiToNoteWithOctave(midiNote),
    startTick: startTick,
    durationTicks: safeDuration,
  );
  _clearLatestImportedRangeForNewNote();
  state = state.copyWith(
    notes: [...state.notes, note],
    selectedNoteIds: {note.id},
  );
}

void addNoteStack(List<int> midiNotes, int startTick, int durationTicks) {
  final maxTick = rules.totalTicks(
    state.config.timeSignature,
    state.config.totalMeasures,
  );
  if (startTick < 0 || startTick >= maxTick) return;
  final safe = durationTicks.clamp(1, maxTick - startTick);
  final unique = midiNotes.toSet().where(
    (m) => m >= state.pitchRangeStart && m <= state.pitchRangeEnd,
  );
  if (unique.isEmpty) return;
  final created = unique.map(
    (midi) => PianoRollNote(
      id: _makeId(),
      midiNote: midi,
      pitchClass: rules.midiToPitchClass(midi),
      noteWithOctave: rules.midiToNoteWithOctave(midi),
      startTick: startTick,
      durationTicks: safe,
    ),
  );
  _clearLatestImportedRangeForNewNote();
  state = state.copyWith(notes: [...state.notes, ...created]);
}

void splitNote(String noteId, int splitTick) {
  final target = state.notes.where((n) => n.id == noteId).firstOrNull;
  if (target == null) return;
  if (splitTick <= target.startTick ||
      splitTick >= target.startTick + target.durationTicks) {
    return;
  }
  final dur1 = splitTick - target.startTick;
  final dur2 = (target.startTick + target.durationTicks) - splitTick;
  final left = target.copyWith(durationTicks: dur1);
  final right = PianoRollNote(
    id: _makeId(),
    midiNote: target.midiNote,
    pitchClass: target.pitchClass,
    noteWithOctave: target.noteWithOctave,
    startTick: splitTick,
    durationTicks: dur2,
  );
  _clearLatestImportedRangeForNewNote();
  state = state.copyWith(
    notes: [...state.notes.where((n) => n.id != noteId), left, right],
    selectedNoteIds: {right.id},
  );
}

void clearNotes() => state = state.copyWith(
  notes: [],
  selectedNoteIds: const <String>{},
  selectedColumnTick: () => null,
  latestImportedRange: () => null,
);
```

```dart
final created = clamped.map((note) {
  final boundedStart = note.startTick.clamp(0, maxTick - 1);
  final boundedDuration = min(note.durationTicks, maxTick - boundedStart);
  if (boundedStart != note.startTick ||
      boundedDuration != note.durationTicks) {
    truncated = true;
  }
  return PianoRollNote(
    id: _makeId(),
    midiNote: note.midiNote,
    pitchClass: rules.midiToPitchClass(note.midiNote),
    noteWithOctave: rules.midiToNoteWithOctave(note.midiNote),
    startTick: boundedStart,
    durationTicks: max(1, boundedDuration),
  );
}).toList();

final createdFirstStartTick = created.map((note) => note.startTick).reduce(min);
final createdFurthestEndTick = created
    .map((note) => note.startTick + note.durationTicks)
    .reduce(max);

state = state.copyWith(
  notes: [...state.notes, ...created],
  selectedNoteIds: created.map((note) => note.id).toSet(),
);

return (
  createdCount: created.length,
  truncated: truncated,
  firstStartTick: createdFirstStartTick,
  furthestEndTick: createdFurthestEndTick,
);
```

- [ ] **Step 5: Run the focused test to verify it passes**

Run: `flutter test test/store/piano_roll_store_test.dart`

Expected: PASS for remembered-range ownership, non-import clearing, and actual created-end reporting.

- [ ] **Step 6: Commit**

```bash
git add lib/models/piano_roll.dart lib/store/piano_roll_store.dart test/store/piano_roll_store_test.dart
git commit -m "feat: remember latest hum import range"
```

## Task 3: Wire Hum Import To The Remembered Range And Clear Stale Targets

**Primary specialist:** `state-architect`

**Files:**
- Modify: `lib/store/hum_to_midi_store.dart`
- Test: `test/store/hum_to_midi_store_test.dart`

- [ ] **Step 1: Write the failing hum-store tests**

```dart
test('stopRecording stores latestImportedRange after a successful hum import', () async {
  final fake = _FakeMicPitchSession();
  final container = ProviderContainer(
    overrides: [micPitchSessionProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);

  await container.read(humToMidiProvider.notifier).startRecording();
  fake.emit(const PitchFrame(
    timestampMs: 0,
    frequencyHz: 440,
    midiNote: 69,
    centsOffset: 0,
    amplitude: 0.9,
    confidence: 0.97,
    isSilence: false,
  ));
  fake.emit(const PitchFrame(
    timestampMs: 180,
    frequencyHz: 440,
    midiNote: 69,
    centsOffset: 0,
    amplitude: 0.9,
    confidence: 0.97,
    isSilence: false,
  ));
  await Future<void>.delayed(Duration.zero);

  await container.read(humToMidiProvider.notifier).stopRecording();

  final range = container.read(pianoRollProvider).latestImportedRange;
  expect(range, isNotNull);
  expect(range!.startTick, 0);
  expect(range.endTickExclusive, greaterThan(0));
});

test('stopRecording replaces the previous latestImportedRange on a later successful import', () async {
  final fake = _FakeMicPitchSession();
  final container = ProviderContainer(
    overrides: [micPitchSessionProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);

  container.read(pianoRollProvider.notifier).rememberLatestImportedRange(4, 8);

  await container.read(humToMidiProvider.notifier).startRecording();
  fake.emit(const PitchFrame(
    timestampMs: 0,
    frequencyHz: 494,
    midiNote: 71,
    centsOffset: 0,
    amplitude: 0.9,
    confidence: 0.97,
    isSilence: false,
  ));
  fake.emit(const PitchFrame(
    timestampMs: 180,
    frequencyHz: 494,
    midiNote: 71,
    centsOffset: 0,
    amplitude: 0.9,
    confidence: 0.97,
    isSilence: false,
  ));
  await Future<void>.delayed(Duration.zero);

  await container.read(humToMidiProvider.notifier).stopRecording();

  final range = container.read(pianoRollProvider).latestImportedRange;
  expect(range?.startTick, isNot(4));
});

test('stopRecording clears the previous latestImportedRange when no stable note is imported', () async {
  final fake = _FakeMicPitchSession();
  final container = ProviderContainer(
    overrides: [micPitchSessionProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);

  container.read(pianoRollProvider.notifier).rememberLatestImportedRange(24, 32);

  await container.read(humToMidiProvider.notifier).startRecording();
  fake.emit(const PitchFrame(
    timestampMs: 0,
    frequencyHz: 440,
    midiNote: 69,
    centsOffset: 0,
    amplitude: 0.9,
    confidence: 0.97,
    isSilence: false,
  ));
  await Future<void>.delayed(Duration.zero);

  await container.read(humToMidiProvider.notifier).stopRecording();

  expect(container.read(pianoRollProvider).latestImportedRange, isNull);
  expect(
    container.read(humToMidiProvider).feedbackMessage,
    'No stable note detected',
  );
});
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `flutter test test/store/hum_to_midi_store_test.dart`

Expected: FAIL because `stopRecording()` does not yet normalize imports, remember the final import range, or clear stale latest-import state on empty import.

- [ ] **Step 3: Normalize imports and remember the final created range**

```dart
final segmented = rules.segmentStableNotes(state.frames);
final pianoRoll = ref.read(pianoRollProvider);
final anchorTick = ref
    .read(pianoRollProvider.notifier)
    .suggestedImportAnchorTick();
final quantized = rules.quantizeNotesToTicks(
  notes: segmented,
  anchorTick: anchorTick,
  tempo: pianoRoll.config.tempo,
  timeSignature: pianoRoll.config.timeSignature,
  snapTicks: pianoRoll.snapTicks,
);
final imported = rules.normalizeQuantizedHumNotesMonophonically(quantized);

final pianoRollNotifier = ref.read(pianoRollProvider.notifier);
final preImportColumn = ref.read(pianoRollProvider).selectedColumnTick;
final importResult = pianoRollNotifier.appendImportedNotes(imported);

if (importResult.createdCount > 0 &&
    importResult.firstStartTick != null &&
    importResult.furthestEndTick != null) {
  pianoRollNotifier.rememberLatestImportedRange(
    importResult.firstStartTick!,
    importResult.furthestEndTick!,
  );

  if (preImportColumn == null) {
    pianoRollNotifier.selectColumn(importResult.firstStartTick);
  }

  ref.read(pianoRollScrollToTickProvider.notifier).state =
      importResult.firstStartTick;
} else {
  pianoRollNotifier.clearLatestImportedRange();
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `flutter test test/store/hum_to_midi_store_test.dart`

Expected: PASS for latest-import range creation, replacement, and stale-target clearing while preserving the existing import assertions.

- [ ] **Step 5: Commit**

```bash
git add lib/store/hum_to_midi_store.dart test/store/hum_to_midi_store_test.dart
git commit -m "fix: track latest hum import navigation target"
```

## Task 4: Add The Hum-Card `Jump to latest` Action

**Primary specialist:** `instrument-renderer`

**Files:**
- Modify: `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- Test: `test/features/piano_roll/piano_roll_hum_recorder_test.dart`

- [ ] **Step 1: Write the failing widget tests**

```dart
class FakeHumNotifier extends HumToMidiNotifier {
  FakeHumNotifier(this._initial);

  final HumToMidiState _initial;

  @override
  HumToMidiState build() => _initial;
}

class FakePianoRollNotifier extends PianoRollNotifier {
  FakePianoRollNotifier(this._initial);

  final PianoRollState _initial;

  @override
  PianoRollState build() => _initial;
}

const _defaultPRState = PianoRollState(
  config: PianoRollConfig(
    tempo: 120,
    timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    totalMeasures: 4,
  ),
  notes: [],
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
);

testWidgets('shows jump to latest and scrolls without changing selection', (tester) async {
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(
        () => FakePianoRollNotifier(
          _defaultPRState.copyWith(
            selectedColumnTick: () => 12,
            latestImportedRange: () => const PianoRollImportedRange(
              startTick: 32,
              endTickExclusive: 40,
            ),
          ),
        ),
      ),
      humToMidiProvider.overrideWith(
        () => FakeHumNotifier(
          const HumToMidiState(
            status: HumToMidiStatus.completed,
            feedbackMessage: 'Imported',
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: PianoRollHumRecorderPanel()),
      ),
    ),
  );
  await tester.pump();

  expect(find.text('Jump to latest'), findsOneWidget);

  await tester.tap(find.text('Jump to latest'));
  await tester.pump();

  expect(container.read(pianoRollScrollToTickProvider), 32);
  expect(container.read(pianoRollProvider).selectedColumnTick, 12);
});

testWidgets('hides jump to latest after a later manual note add clears the remembered range', (tester) async {
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(
        () => FakePianoRollNotifier(
          _defaultPRState.copyWith(
            latestImportedRange: () => const PianoRollImportedRange(
              startTick: 32,
              endTickExclusive: 40,
            ),
          ),
        ),
      ),
      humToMidiProvider.overrideWith(
        () => FakeHumNotifier(
          const HumToMidiState(status: HumToMidiStatus.completed),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: PianoRollHumRecorderPanel()),
      ),
    ),
  );
  await tester.pump();
  expect(find.text('Jump to latest'), findsOneWidget);

  container.read(pianoRollProvider.notifier).addNote(72, 20, 1);
  await tester.pump();

  expect(find.text('Jump to latest'), findsNothing);
});
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart`

Expected: FAIL because the panel does not yet read `latestImportedRange` or render a jump action.

- [ ] **Step 3: Add the jump action to the provider-backed panel and card**

```dart
class _PianoRollHumRecorderPanelState
    extends ConsumerState<PianoRollHumRecorderPanel> {
  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final state = ref.watch(humToMidiProvider);
    final latestImportedRange = ref.watch(
      pianoRollProvider.select((state) => state.latestImportedRange),
    );

    return PianoRollHumRecorderCard(
      status: state.status,
      liveNoteLabel: state.liveMidiNote == null
          ? 'No pitch'
          : rules.midiToNoteLabel(state.liveMidiNote!),
      statusLabel: switch (state.status) {
        HumToMidiStatus.recording =>
          state.liveMidiNote == null ? 'No pitch' : 'Stable',
        HumToMidiStatus.processing => 'Processing',
        HumToMidiStatus.error => state.errorMessage ?? 'Error',
        HumToMidiStatus.completed => state.feedbackMessage ?? 'Imported',
        _ => 'Ready',
      },
      elapsedLabel: state.status == HumToMidiStatus.recording
          ? elapsedLabel
          : 'Idle',
      onStart:
          state.status == HumToMidiStatus.idle ||
              state.status == HumToMidiStatus.completed ||
              state.status == HumToMidiStatus.error
          ? () => ref.read(humToMidiProvider.notifier).startRecording()
          : null,
      onStop: state.status == HumToMidiStatus.recording
          ? () => ref.read(humToMidiProvider.notifier).stopRecording()
          : null,
      onJumpToLatest: latestImportedRange == null
          ? null
          : () {
              ref.read(pianoRollScrollToTickProvider.notifier).state =
                  latestImportedRange.startTick;
            },
    );
  }
}
```

```dart
class PianoRollHumRecorderCard extends StatelessWidget {
  final VoidCallback? onJumpToLatest;

  const PianoRollHumRecorderCard({
    super.key,
    required this.status,
    required this.liveNoteLabel,
    required this.statusLabel,
    required this.elapsedLabel,
    required this.onStart,
    required this.onStop,
    this.onJumpToLatest,
  });

  @override
  Widget build(BuildContext context) {
    final isRecording = status == HumToMidiStatus.recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hum to MIDI',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    liveNoteLabel,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: const TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              elapsedLabel,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: isRecording ? onStop : onStart,
              child: Text(isRecording ? 'Stop' : 'Record'),
            ),
          ],
        ),
        if (onJumpToLatest != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onJumpToLatest,
            child: const Text('Jump to latest'),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart`

Expected: PASS for button visibility, scroll signal emission, and post-manual-add hiding.

- [ ] **Step 5: Commit**

```bash
git add lib/features/piano_roll/piano_roll_hum_recorder.dart test/features/piano_roll/piano_roll_hum_recorder_test.dart
git commit -m "feat: add jump to latest hum import action"
```

## Task 5: Update Docs And Run Final Verification

**Primary specialist:** `code-quality`

**Files:**
- Modify: `docs/piano_roll.md`
- Verify: `lib/models/piano_roll.dart`
- Verify: `lib/schema/rules/mono_pitch_rules.dart`
- Verify: `lib/store/piano_roll_store.dart`
- Verify: `lib/store/hum_to_midi_store.dart`
- Verify: `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- Verify: `test/schema/rules/mono_pitch_rules_test.dart`
- Verify: `test/store/piano_roll_store_test.dart`
- Verify: `test/store/hum_to_midi_store_test.dart`
- Verify: `test/features/piano_roll/piano_roll_hum_recorder_test.dart`

- [ ] **Step 1: Update the piano roll docs**

```md
### Jump to latest

- After a successful hum import, the `Hum to MIDI` card can show `Jump to latest`.
- The action scrolls back to the latest imported hum region without changing selection or playback state.
- The action stays available until a later non-import note-add action occurs or the piano roll is cleared/reset.

### Monophonic import guarantee

- Hum recording remains one-note-at-a-time after quantization.
- If two imported notes would overlap, the earlier note is trimmed to the later note's start.
- If trimming would make the earlier note zero-length, that earlier note is dropped.
```

- [ ] **Step 2: Run the targeted regression suite**

Run:

```bash
flutter test \
  test/schema/rules/mono_pitch_rules_test.dart \
  test/store/piano_roll_store_test.dart \
  test/store/hum_to_midi_store_test.dart \
  test/features/piano_roll/piano_roll_hum_recorder_test.dart
```

Expected: PASS for all four focused suites.

- [ ] **Step 3: Run analyzer on the touched code paths**

Run:

```bash
flutter analyze \
  lib/models/piano_roll.dart \
  lib/schema/rules/mono_pitch_rules.dart \
  lib/store/piano_roll_store.dart \
  lib/store/hum_to_midi_store.dart \
  lib/features/piano_roll/piano_roll_hum_recorder.dart \
  test/schema/rules/mono_pitch_rules_test.dart \
  test/store/piano_roll_store_test.dart \
  test/store/hum_to_midi_store_test.dart \
  test/features/piano_roll/piano_roll_hum_recorder_test.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add docs/piano_roll.md
git commit -m "docs: document latest hum import navigation"
```

## Self-Review Checklist

- Spec coverage:
  - `Jump to latest` in Hum card is covered by Task 4.
  - Remembered latest-import target ownership and clearing rules are covered by Tasks 2 and 3.
  - Monophonic post-quantization import behavior is covered by Task 1.
  - Docs and verification are covered by Task 5.
- Placeholder scan:
  - No `TODO`, `TBD`, or deferred “handle later” steps remain in the plan.
- Type consistency:
  - Use `PianoRollImportedRange` consistently in state, store, and tests.
  - Use `normalizeQuantizedHumNotesMonophonically(...)` consistently between the rule layer and `HumToMidiNotifier.stopRecording()`.
