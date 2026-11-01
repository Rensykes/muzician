# Piano Roll Select-Tap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a stationary tap on a note in the Piano Roll Select tool select, audition and column-anchor that note instead of clearing the selection.

**Architecture:** Extract the existing note-tap body of `_onPointerUp` into `_handleNoteTap`, then let the marquee branch call it when the pointer never moved and the release point hits a note; commit the marquee preview only after movement.

**Tech Stack:** Flutter/Dart, Riverpod, `flutter_test` widget tests.

**Spec:** `docs/superpowers/specs/2026-11-01-piano-roll-select-tap-design.md`

## Global Constraints

- No new dependencies.
- Only these files change: `lib/features/piano_roll/piano_roll_grid.dart`, `test/features/piano_roll/piano_roll_grid_test.dart`, `docs/piano_roll.md`, `AGENTS.md`.
- No modifier-key selection, no changes to Draw/Scissors/Paint/Delete/pinch/scroll/long-press, and no change to marquee commit rules after movement.
- `dart format` on changed paths, `flutter analyze` clean, then the piano roll test file.
- Conventional commit, one commit.

## Review Focus

- A tap on a note in Select must audition, select and set `selectedColumnTick` — not clear the selection.
- A tap on empty space in Select must still clear the selection.
- A drag in Select, including one starting on a note, must still commit the marquee and must not select or audition on press.
- Double-tap refinement must still work in Draw (shared `_lastTapTime` / `_preTapSelection` state is reused by the new path).
- Touch taps (no `buttons` mask) must behave identically to mouse clicks.

---

### Task 1: Select tap selects the note

**Files:**
- Modify: `lib/features/piano_roll/piano_roll_grid.dart` — `_onPointerUp` marquee branch (`:1042`) and the note-tap body of the tap branch (`:1094-1128`)
- Test: `test/features/piano_roll/piano_roll_grid_test.dart`
- Docs: `docs/piano_roll.md`, `AGENTS.md`

**Interfaces:**
- Consumes: existing `_hitTestNote(Offset, PianoRollState)`, `_localToGrid(Offset)`, `_movedBeyondSlop`, `_lastTapTime`, `_lastTapNoteId`, `_preTapSelection`.
- Produces: `void _handleNoteTap(PianoRollNote hit, PianoRollState state)` — private to `_PianoRollGridState`.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/piano_roll/piano_roll_grid_test.dart`:

```dart
testWidgets('select tool tap solo-selects a note', (tester) async {
  const note = PianoRollNote(
    id: 'select-tap-note',
    midiNote: 66,
    pitchClass: 'F#',
    noteWithOctave: 'F#4',
    startTick: 0,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    notes: const [note],
    activeTool: PianoRollTool.select,
  );
  final notifier = _TrackingNotifier(initial);
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => notifier),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapGrid(container));
  await tester.pump();

  final gridFinder = find.byKey(const ValueKey('piano-roll-grid-listener'));
  // midi 66, tick 0: row index 84 - 66 = 18, so y = 18 * 18 = 324..342.
  await tester.tapAt(tester.getRect(gridFinder).topLeft + const Offset(56, 333));
  await tester.pump();

  final state = container.read(pianoRollProvider);
  expect(
    state.selectedNoteIds,
    {'select-tap-note'},
    reason: 'A tap on a note in Select must select it',
  );
  expect(
    state.selectedColumnTick,
    0,
    reason: 'A tap on a note must anchor the selected column to it',
  );
});

testWidgets('select tool double-tap adds a note to the selection', (
  tester,
) async {
  const noteA = PianoRollNote(
    id: 'select-tap-a',
    midiNote: 66,
    pitchClass: 'F#',
    noteWithOctave: 'F#4',
    startTick: 0,
    durationTicks: 4,
  );
  const noteB = PianoRollNote(
    id: 'select-tap-b',
    midiNote: 68,
    pitchClass: 'G#',
    noteWithOctave: 'G#4',
    startTick: 2,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    notes: const [noteA, noteB],
    activeTool: PianoRollTool.select,
  );
  final notifier = _TrackingNotifier(initial);
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => notifier),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapGrid(container));
  await tester.pump();

  final gridFinder = find.byKey(const ValueKey('piano-roll-grid-listener'));
  final topLeft = tester.getRect(gridFinder).topLeft;
  final noteAPoint = topLeft + const Offset(56, 333);
  // midi 68, tick 2: row 16 -> y 289..305; x 56..168.
  final noteBPoint = topLeft + const Offset(112, 297);

  await tester.tapAt(noteAPoint);
  await tester.pump();
  await tester.tapAt(noteBPoint);
  await tester.pump(const Duration(milliseconds: 120));
  await tester.tapAt(noteBPoint);
  await tester.pump();

  expect(
    container.read(pianoRollProvider).selectedNoteIds,
    containsAll(<String>{'select-tap-a', 'select-tap-b'}),
    reason: 'Double-tap in Select must add the second note',
  );
});

testWidgets('select tool tap on empty space clears the selection', (
  tester,
) async {
  const note = PianoRollNote(
    id: 'select-empty-note',
    midiNote: 66,
    pitchClass: 'F#',
    noteWithOctave: 'F#4',
    startTick: 0,
    durationTicks: 4,
  );
  final initial = _defaultPRState.copyWith(
    notes: const [note],
    activeTool: PianoRollTool.select,
    selectedNoteIds: const {'select-empty-note'},
  );
  final notifier = _TrackingNotifier(initial);
  final container = ProviderContainer(
    overrides: [
      pianoRollProvider.overrideWith(() => notifier),
      pianoRollPlaybackProvider.overrideWith(
        () => _FakePlaybackNotifier(const PianoRollPlaybackState()),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(_wrapGrid(container));
  await tester.pump();

  final gridFinder = find.byKey(const ValueKey('piano-roll-grid-listener'));
  await tester.tapAt(tester.getRect(gridFinder).topLeft + const Offset(560, 60));
  await tester.pump();

  expect(
    container.read(pianoRollProvider).selectedNoteIds,
    isEmpty,
    reason: 'A tap on empty space must still clear the selection',
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart --plain-name 'select tool'`
Expected: the solo-select test and the double-tap test FAIL (selection empty);
the empty-space test PASSES (it pins current behaviour).

- [ ] **Step 3: Extract `_handleNoteTap`**

Move the body of the existing note-tap `else` branch in `_onPointerUp` — from
`NotePlayer.instance.previewTimbre(` through the `selectNote` / double-tap
block, excluding the Scissors split branch — into:

```dart
void _handleNoteTap(PianoRollNote hit, PianoRollState state) {
  NotePlayer.instance.previewTimbre(
    ref.read(pianoRollProvider).sound,
    hit.midiNote,
    volume: ref.read(settingsProvider).noteVolume,
  );
  final now = DateTime.now();
  final isDoubleTap =
      _lastTapNoteId == hit.id &&
      _lastTapTime != null &&
      now.difference(_lastTapTime!).inMilliseconds < 300;
  final notifier = ref.read(pianoRollProvider.notifier);
  if (isDoubleTap) {
    final toggled = _preTapSelection.contains(hit.id)
        ? _preTapSelection.difference({hit.id})
        : {..._preTapSelection, hit.id};
    notifier.setSelection(toggled.isEmpty ? {hit.id} : toggled);
    notifier.selectColumn(hit.startTick);
    HapticFeedback.mediumImpact();
    _lastTapTime = null;
    _lastTapNoteId = null;
  } else {
    _preTapSelection = state.selectedNoteIds;
    final isAlreadySolo =
        state.selectedNoteIds.length == 1 &&
        state.selectedNoteIds.contains(hit.id);
    notifier.selectNote(isAlreadySolo ? null : hit.id);
    notifier.selectColumn(hit.startTick);
    HapticFeedback.selectionClick();
    _lastTapTime = now;
    _lastTapNoteId = hit.id;
  }
}
```

The tap branch's non-scissors path becomes `_handleNoteTap(hit, state);`.

- [ ] **Step 4: Use it from the marquee branch**

At the top of `_onPointerUp`'s marquee branch, before
`setSelection(_marqueePreviewIds)`:

```dart
if (!_movedBeyondSlop) {
  final hit = _hitTestNote(_localToGrid(event.localPosition), state);
  if (hit != null) {
    _handleNoteTap(hit, state);
    setState(() {
      _marqueeStart = null;
      _marqueeCurrent = null;
      _marqueeRect = null;
      _marqueePreviewIds = const <String>{};
    });
    _dragMode = _DragMode.none;
    _movedBeyondSlop = false;
    _totalPointerDelta = Offset.zero;
    return;
  }
}
```

The existing commit path stays below it unchanged, so a drag or an empty-space
tap behaves exactly as today.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/piano_roll/piano_roll_grid_test.dart`
Expected: the whole file passes, including the new tests and the existing
marquee, pinch, paint, delete, scissors and keyboard suites.

- [ ] **Step 6: Align the docs**

`docs/piano_roll.md`:

- In the Select row of the Tool Modes matrix, replace the "Tap on note" cell
  with: `Solo-select it (audition + column anchor); double-tap to add/remove from selection.`
- In the Selection workflows list, add after the Double-tap bullet:
  `- **Tap a note (Select)**: solo-select that note, audition it and anchor the selected column; a drag still marquees.`
- In the `onPointerUp` row of the pointer table, replace the `select` clause with:
  `select: commit marquee selection via setSelection(ids); a stationary tap on a note runs the tap-select path instead`

`AGENTS.md`, appended to the Instrument UX V2 paragraph:

```markdown
Raw `Listener` canvases (Piano Roll grid, Fretboard, Writer melody timeline) gate input with `isPrimaryPointerButton` (`lib/utils/pointer_buttons.dart`) so right/middle clicks are inert, and reset gesture state on `onPointerCancel`. In Piano Roll Select, a stationary tap on a note selects it; the marquee commits only after movement.
```

- [ ] **Step 7: Verify and commit**

```bash
dart format lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart
flutter analyze
flutter test test/features/piano_roll/piano_roll_grid_test.dart
git add lib/features/piano_roll/piano_roll_grid.dart test/features/piano_roll/piano_roll_grid_test.dart docs/piano_roll.md AGENTS.md
git commit -m "fix: select a note on tap in piano roll select tool"
```

Expected: format makes no changes, analyze reports no issues, the whole test file
passes.
