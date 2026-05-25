# Piano Roll Hum Import And Playback Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the post-hum piano roll flow so imported takes reliably expand the timeline horizontally when needed, and add a playback function that starts at the selected column and runs through the end of the piano roll timeline.

**Architecture:** Keep note import ownership in `pianoRollProvider`, tighten hum-import regression coverage around timeline growth and selection handoff, and add a dedicated playback transport store instead of mixing transport state into the editor store. Reuse the existing synthesized `NotePlayer` for note playback, but keep scheduling, timing math, and UI state testable through a separate rules layer and injected playback sink.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, `flutter_test`, existing `NotePlayer`/`audioplayers` preview synthesis, pure Dart timing helpers in `lib/schema/rules/`

---

## Brainstorm Summary

### Option 1: Extend `piano_roll_store.dart` with inline playback state

- Pros: smallest file count, fastest path to a demo
- Cons: mixes transport concerns into editing state, makes start/stop logic harder to test, and increases the risk of future regressions when humming, editing, and playback overlap

### Option 2: Add a dedicated piano roll playback transport

- Pros: clean separation between editor state and transport state, easy subagent boundaries, straightforward fake-based tests, and a better base for future loop/playhead/metronome work
- Cons: requires 2-4 extra files and a small amount of provider plumbing

### Option 3: Build a more precise audio sequencer or prerendered playback path

- Pros: best timing ceiling long-term
- Cons: too much complexity for the current bugfix-plus-v1-playback scope, and it would slow down delivery without solving a confirmed user problem

### Recommendation

Choose **Option 2**. It is the safest subagent-friendly plan: one specialist can stabilize hum import and store semantics, another can build transport timing in isolation, and the UI task can wire against a clean provider contract.

---

## Locked Product Decisions

- Hum import auto-growth means **horizontal timeline expansion only**
- The piano roll should **not** auto-expand pitch range for this follow-up
- Playback starts at the **selected column**
- Playback continues through the **end of the full piano roll timeline**
- This work is a follow-up to the existing hum-to-MIDI feature, not a redesign of the original flow

## Review Assumptions

- If playback is triggered with no `selectedColumnTick`, v1 falls back to tick `0`
- If a hum take is imported while no column was selected, the hum flow sets `selectedColumnTick` to the first imported tick so the next Play action has a meaningful start point
- v1 playback is transport-only: **play** and **stop** are in scope; **pause**, **loop**, **metronome**, **scrub**, **playhead auto-scroll**, and **MIDI export** are out of scope
- v1 playback reuses the current `NotePlayer` engine as an **onset sequencer**. Event timing and same-tick chord playback should be correct, but sustained note lengths will still use the current short synthesized preview tone instead of exact note-off timing. If duration-accurate playback is required, that should be treated as a larger follow-up scope.

---

## Detailed Implementation Contract

### Piano Roll Import Contract

Keep `appendImportedNotes()` as the only note-import entry point for hum commits.

Preferred signature:

```dart
({int createdCount, bool truncated, int? firstStartTick, int? furthestEndTick})
appendImportedNotes(List<QuantizedHumNote> imported)
```

Behavior contract:
- Filter out zero-or-negative-duration imported notes before any state changes
- Compute `furthestEndTick` from `startTick + durationTicks`
- Call `_ensureTimelineCoversEndTick(furthestEndTick)` before creating notes
- Expand measures only when `furthestEndTick > currentTotalTicks`
- Do not add an extra measure when `furthestEndTick == currentTotalTicks`
- Keep note selection behavior scoped to the newly created notes via `selectedNoteIds`
- Leave `selectedColumnTick` untouched inside `appendImportedNotes()` so the hum store can decide whether to preserve an existing user selection or set a fallback

### Hum Store Handoff Contract

`HumToMidiNotifier.stopRecording()` should follow this order:

1. Snapshot the pre-import `selectedColumnTick`
2. Finalize segmented notes into quantized notes
3. Call `appendImportedNotes(imported)`
4. If notes were created and the pre-import selection was `null`, call:

```dart
ref.read(pianoRollProvider.notifier).selectColumn(importResult.firstStartTick);
```

5. If notes were created, set:

```dart
ref.read(pianoRollScrollToTickProvider.notifier).state =
    importResult.firstStartTick;
```

6. Update hum status and feedback message

`HumToMidiNotifier.startRecording()` should stop active playback first if the transport is currently playing.

### Playback Provider Contract

Add a dedicated transport provider:

```dart
final pianoRollPlaybackProvider =
    NotifierProvider<PianoRollPlaybackNotifier, PianoRollPlaybackState>(
      PianoRollPlaybackNotifier.new,
    );
```

Add an injected playback sink instead of calling `NotePlayer.instance` directly from the store:

```dart
typedef PianoRollPlaybackSink =
    Future<void> Function(List<int> midiNotes, double volume);

final pianoRollPlaybackSinkProvider = Provider<PianoRollPlaybackSink>((ref) {
  return (midiNotes, volume) async {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: volume);
    }
  };
});
```

### Playback Model Contract

Use a minimal immutable transport state:

```dart
enum PianoRollPlaybackStatus { idle, playing, completed, error }

class PianoRollPlaybackEvent {
  final int tick;
  final List<int> midiNotes;

  const PianoRollPlaybackEvent({
    required this.tick,
    required this.midiNotes,
  });
}

class PianoRollPlaybackState {
  final PianoRollPlaybackStatus status;
  final int? startTick;
  final int? currentTick;
  final int? endTickExclusive;
  final String? message;
  final String? errorMessage;

  const PianoRollPlaybackState({
    this.status = PianoRollPlaybackStatus.idle,
    this.startTick,
    this.currentTick,
    this.endTickExclusive,
    this.message,
    this.errorMessage,
  });
}
```

### Pure Playback Rules Contract

Create these helpers in `lib/schema/rules/piano_roll_playback_rules.dart`:

```dart
int resolvePlaybackStartTick(PianoRollState state);
int resolvePlaybackEndTick(PianoRollState state);
double millisecondsPerTick(int tempo);
Duration durationForTickDelta(int tickDelta, int tempo);
List<PianoRollPlaybackEvent> groupPlaybackEvents(
  List<PianoRollNote> notes,
  int startTick,
);
```

Expected behaviors:
- `resolvePlaybackStartTick()` returns `state.selectedColumnTick ?? 0`
- `resolvePlaybackEndTick()` returns the full timeline end via `totalTicks(...)`
- `groupPlaybackEvents()` includes only notes whose `startTick >= startTick`
- Same-tick notes are grouped into one event with sorted distinct MIDI notes
- Events are returned in ascending tick order

### Transport Scheduling Contract

`PianoRollPlaybackNotifier.startPlayback()` should:

1. Return early if already playing
2. Return early or enter `completed` with a message if hum status is `recording`, `processing`, or `requestingPermission`
3. Snapshot the current `PianoRollState` and settings at the time playback starts
4. Resolve:
   - `startTick`
   - `endTickExclusive`
   - `events`
5. If `events` is empty, avoid starting transport and surface a small message such as `Nothing to play from the selected column`
6. Set transport state to `playing`
7. Iterate over events in order:

```dart
await Future<void>.delayed(durationForTickDelta(event.tick - previousTick, tempo));
await sink(event.midiNotes, volume);
state = state.copyWith(currentTick: event.tick);
```

8. After the last event, wait out the remaining silent span to `endTickExclusive`
9. Transition to `completed`

`stopPlayback()` should:
- cancel pending scheduled work using a run token or cancellation counter
- reset state to `idle`
- be safe to call repeatedly

### UI Contract

`PianoRollPlaybackConfig` should read:
- `pianoRollProvider`
- `pianoRollPlaybackProvider`
- `humToMidiProvider`

Expected visible states:
- Idle + selected column present:

```text
Start: Selected column (tick 17)
Timeline: Plays to end of roll
```

- Idle + no selected column:

```text
Start: Beginning of roll
Timeline: Plays to end of roll
```

- Playing:

```text
Status: Playing from tick 17
Current: tick 29
```

- Disabled due to hum recording:

```text
Playback unavailable while humming
```

---

## File Structure

### Create

- `lib/models/piano_roll_playback.dart`
  Immutable transport state, playback status enum, and grouped playback event model.
- `lib/schema/rules/piano_roll_playback_rules.dart`
  Pure timing helpers for tick-to-duration math, note grouping, playback start/end bounds, and timeline-derived event lists.
- `lib/store/piano_roll_playback_store.dart`
  Dedicated Riverpod transport store that schedules notes and exposes playback UI state.
- `test/schema/rules/piano_roll_playback_rules_test.dart`
  Unit tests for playback timing math and event grouping.
- `test/store/piano_roll_playback_store_test.dart`
  Fake-driven store tests for start/stop/completion behavior.
- `test/features/piano_roll/piano_roll_playback_config_test.dart`
  Widget tests for the playback panel states and disabled actions.

### Modify

- `lib/store/piano_roll_store.dart`
  Tighten imported-note result handling and any needed horizontal-growth fixes.
- `lib/store/hum_to_midi_store.dart`
  Integrate post-import selected-column behavior and playback interlocks.
- `lib/features/piano_roll/piano_roll_toolbar.dart`
  Replace the placeholder playback card with real play/stop controls and transport feedback.
- `lib/features/piano_roll/piano_roll_feature.dart`
  Export any new playback widget/API if needed by the panel split.
- `lib/main.dart`
  Only if additional provider wiring or panel composition changes are required.
- `docs/piano_roll.md`
  Document the hum follow-up behavior and playback UX.
- `lib/ui/core/app_info_panel.dart`
  Update the Piano Roll help copy for the new playback behavior if the visible instructions change.
- `test/store/piano_roll_store_test.dart`
  Add focused horizontal-growth regressions if the current test set misses real humming cases.
- `test/store/hum_to_midi_store_test.dart`
  Add end-to-end hum stop/import/selection expectations.

---

## Task 1: Lock The Hum Import Regression With Store Tests

**Primary specialist:** `state-architect`

**Files to read first:**
- `lib/store/piano_roll_store.dart`
- `lib/store/hum_to_midi_store.dart`
- `lib/models/piano_roll.dart`
- `test/store/piano_roll_store_test.dart`
- `test/store/hum_to_midi_store_test.dart`
- `docs/piano_roll.md`

**Files to modify:**
- `test/store/piano_roll_store_test.dart`
- `test/store/hum_to_midi_store_test.dart`
- `lib/store/piano_roll_store.dart`
- `lib/store/hum_to_midi_store.dart`

- [ ] **Step 1: Add failing regression coverage for horizontal growth**

Add at least these test cases:

```dart
test('appendImportedNotes expands totalMeasures when imported notes cross the current end tick', () { ... });
test('appendImportedNotes does not expand when the imported phrase ends exactly on the current timeline boundary', () { ... });
test('stopRecording selects the first imported tick when no column was selected before recording', () async { ... });
```

- [ ] **Step 2: Run the focused tests and confirm they fail for the current gap**

Run:

```bash
flutter test test/store/piano_roll_store_test.dart
flutter test test/store/hum_to_midi_store_test.dart
```

Expected:
- At least one new regression test fails before implementation

- [ ] **Step 3: Fix the store behavior without broadening scope**

Implementation rules:
- Preserve `appendImportedNotes()` as the single piano-roll import entry point
- Keep horizontal growth based on the imported notes' furthest end tick
- Do not add pitch-range auto-growth
- If needed, return enough metadata from `appendImportedNotes()` for the hum store to set `selectedColumnTick` after import
- Do not let the hum store bypass `pianoRollProvider`
- Keep the existing quantization and append semantics intact; this task is only about deterministic horizontal growth and selection handoff

Suggested result shape if extra metadata is needed:

```dart
({int createdCount, bool truncated, int? firstStartTick, int? furthestEndTick})
```

- [ ] **Step 4: Re-run the focused tests**

Run:

```bash
flutter test test/store/piano_roll_store_test.dart
flutter test test/store/hum_to_midi_store_test.dart
```

Expected:
- PASS for the new regression cases

- [ ] **Step 5: Commit**

```bash
git add test/store/piano_roll_store_test.dart test/store/hum_to_midi_store_test.dart lib/store/piano_roll_store.dart lib/store/hum_to_midi_store.dart
git commit -m "fix: lock hum import timeline growth behavior"
```

**Acceptance criteria:**
- Hum imports grow measures only when the imported phrase exceeds the current end tick
- Exact-boundary imports do not create an extra measure
- A hum import with no prior selected column leaves playback with a deterministic start point

---

## Task 2: Add Pure Playback Timing Rules And Transport Models

**Primary specialist:** `state-architect`

**Files to read first:**
- `lib/models/piano_roll.dart`
- `lib/store/piano_roll_store.dart`
- `lib/utils/note_player.dart`
- `lib/features/piano_roll/piano_roll_toolbar.dart`

**Files to modify:**
- `lib/models/piano_roll_playback.dart`
- `lib/schema/rules/piano_roll_playback_rules.dart`
- `test/schema/rules/piano_roll_playback_rules_test.dart`

- [ ] **Step 1: Write failing pure-rule tests**

Add tests for:

```dart
test('groups same-tick notes into one playback event', () { ... });
test('uses selectedColumnTick as the playback start tick', () { ... });
test('falls back to tick zero when no selected column exists', () { ... });
test('computes end-of-timeline playback bounds from totalMeasures and time signature', () { ... });
test('converts tempo and ticks-per-quarter into stable tick durations', () { ... });
```

- [ ] **Step 2: Run the new rules test and confirm failure**

Run:

```bash
flutter test test/schema/rules/piano_roll_playback_rules_test.dart
```

Expected:
- FAIL because the playback rules/models do not exist yet

- [ ] **Step 3: Add immutable transport models and pure timing helpers**

Define at minimum:

```dart
enum PianoRollPlaybackStatus { idle, playing, completed, error }

class PianoRollPlaybackEvent {
  final int tick;
  final List<int> midiNotes;
  const PianoRollPlaybackEvent({required this.tick, required this.midiNotes});
}

class PianoRollPlaybackState {
  final PianoRollPlaybackStatus status;
  final int? startTick;
  final int? currentTick;
  final int? endTickExclusive;
  final String? message;
  final String? errorMessage;
}
```

Pure helper coverage should include:
- `resolvePlaybackStartTick(PianoRollState state)`
- `resolvePlaybackEndTick(PianoRollState state)`
- `groupPlaybackEvents(List<PianoRollNote> notes, int startTick)`
- `millisecondsPerTick(int tempo)`
- `durationForTickDelta(int tickDelta, int tempo)`

Recommended formulas:

```dart
double millisecondsPerTick(int tempo) => 60000 / tempo / ticksPerQuarter;

Duration durationForTickDelta(int tickDelta, int tempo) => Duration(
  milliseconds: (millisecondsPerTick(tempo) * tickDelta).round(),
);
```

- [ ] **Step 4: Re-run the rules test**

Run:

```bash
flutter test test/schema/rules/piano_roll_playback_rules_test.dart
```

Expected:
- PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/piano_roll_playback.dart lib/schema/rules/piano_roll_playback_rules.dart test/schema/rules/piano_roll_playback_rules_test.dart
git commit -m "feat: add piano roll playback timing rules"
```

**Acceptance criteria:**
- Playback timing math is pure and testable
- Playback start semantics are explicit instead of hidden in UI code
- Event grouping supports chords on the same tick

---

## Task 3: Build A Dedicated Playback Transport Store

**Primary specialist:** `state-architect`

**Files to read first:**
- `lib/models/piano_roll_playback.dart`
- `lib/schema/rules/piano_roll_playback_rules.dart`
- `lib/store/piano_roll_store.dart`
- `lib/utils/note_player.dart`
- `lib/store/settings_store.dart`

**Files to modify:**
- `lib/store/piano_roll_playback_store.dart`
- `test/store/piano_roll_playback_store_test.dart`
- `lib/main.dart`

- [ ] **Step 1: Write failing store tests against a fake playback sink**

Use provider injection instead of calling `NotePlayer.instance` directly from the store. Cover:

```dart
test('startPlayback emits note groups from selectedColumnTick to timeline end', () async { ... });
test('stopPlayback cancels pending transport work and returns to idle', () async { ... });
test('playback completes cleanly when the timeline end is reached', () async { ... });
test('playback does nothing when there are no notes at or after the start tick', () async { ... });
test('playback is blocked while hum recording is active', () async { ... });
test('playback snapshots piano roll notes at start so mid-run edits do not affect the active transport', () async { ... });
```

- [ ] **Step 2: Run the new store tests and confirm failure**

Run:

```bash
flutter test test/store/piano_roll_playback_store_test.dart
```

Expected:
- FAIL because the transport store and sink injection do not exist yet

- [ ] **Step 3: Implement the playback store with an injected sink**

Implementation rules:
- Read note data from `pianoRollProvider`
- Read playback volume from `settingsProvider`
- Reuse `NotePlayer` through an adapter provider, not through direct singleton calls in the store
- Advance transport state on a timer/scheduler derived from `millisecondsPerTick()`
- Support only `startPlayback()` and `stopPlayback()` for v1
- If the selected column is past all notes, still run transport to the end tick only if there are audible notes remaining; otherwise fail fast to `completed` or stay `idle`
- Snapshot the piano-roll state at playback start; the active run should not re-query note data on every scheduled tick
- Sequence note onsets only; do not attempt per-note note-off scheduling in this follow-up

Recommended provider shape:

```dart
typedef PianoRollPlaybackSink = Future<void> Function(List<int> midiNotes, double volume);
final pianoRollPlaybackSinkProvider = Provider<PianoRollPlaybackSink>(...);
```

Recommended notifier surface:

```dart
class PianoRollPlaybackNotifier extends Notifier<PianoRollPlaybackState> {
  Future<void> startPlayback();
  void stopPlayback();
}
```

- [ ] **Step 4: Re-run the playback store tests**

Run:

```bash
flutter test test/store/piano_roll_playback_store_test.dart
```

Expected:
- PASS

- [ ] **Step 5: Commit**

```bash
git add lib/store/piano_roll_playback_store.dart test/store/piano_roll_playback_store_test.dart lib/main.dart
git commit -m "feat: add piano roll playback transport"
```

**Acceptance criteria:**
- Playback state is isolated from editor state
- The transport can be tested without real audio
- Playback respects the selected column and end-of-timeline rule

---

## Task 4: Wire Playback Controls Into The Piano Roll UI

**Primary specialist:** `instrument-renderer`

**Review specialist:** `accessibility-ux`

**Files to read first:**
- `lib/features/piano_roll/piano_roll_toolbar.dart`
- `lib/store/piano_roll_playback_store.dart`
- `lib/store/hum_to_midi_store.dart`
- `lib/store/piano_roll_store.dart`
- `lib/main.dart`

**Files to modify:**
- `lib/features/piano_roll/piano_roll_toolbar.dart`
- `lib/features/piano_roll/piano_roll_feature.dart`
- `test/features/piano_roll/piano_roll_playback_config_test.dart`
- `lib/ui/core/app_info_panel.dart`

- [ ] **Step 1: Add failing widget tests for the playback panel**

Cover:

```dart
testWidgets('shows Play when idle and Stop while playing', (tester) async { ... });
testWidgets('shows the selected start tick in the playback panel', (tester) async { ... });
testWidgets('disables Play while hum recording is active', (tester) async { ... });
testWidgets('shows a fallback start label when no selected column exists', (tester) async { ... });
```

- [ ] **Step 2: Run the widget tests and confirm failure**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_playback_config_test.dart
```

Expected:
- FAIL because the playback panel is still a tempo/measures config card

- [ ] **Step 3: Replace the placeholder playback UI with real transport controls**

UI requirements:
- Primary action: `Play` when idle, `Stop` when playing
- Secondary status text showing:
  - selected start point when available
  - fallback start point when no column is selected
  - current transport state
- Disable playback while hum recording or processing is active
- Keep the panel compact and visually consistent with the current piano roll card system
- Preserve the existing Playback tab location in the Piano Roll screen; do not move playback into the hum card
- Keep tick labels 1-based in the UI even though state stays 0-based internally

Suggested visible copy:

```text
Start: Selected column (tick 17)
Timeline: Plays to end of roll
```

Fallback copy if no selected column:

```text
Start: Beginning of roll
Timeline: Plays to end of roll
```

- [ ] **Step 4: Run the widget tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_playback_config_test.dart
```

Expected:
- PASS

- [ ] **Step 5: Accessibility review**

Review checklist:
- Play and Stop controls have clear text labels
- Disabled states remain readable
- Status copy explains where playback starts
- Tap targets stay comfortably sized in the current card layout

- [ ] **Step 6: Commit**

```bash
git add lib/features/piano_roll/piano_roll_toolbar.dart lib/features/piano_roll/piano_roll_feature.dart test/features/piano_roll/piano_roll_playback_config_test.dart lib/ui/core/app_info_panel.dart
git commit -m "feat: add piano roll playback controls"
```

**Acceptance criteria:**
- Playback is discoverable from the existing Playback panel
- The panel communicates the selected-column behavior clearly
- Users cannot start playback while humming is actively recording

---

## Task 5: Update Hum Integration, Docs, And Full Verification

**Primary specialist:** `state-architect`

**Final audit specialist:** `code-quality`

**Files to read first:**
- `lib/store/hum_to_midi_store.dart`
- `lib/store/piano_roll_playback_store.dart`
- `docs/piano_roll.md`
- `lib/ui/core/app_info_panel.dart`

**Files to modify:**
- `lib/store/hum_to_midi_store.dart`
- `docs/piano_roll.md`
- `lib/ui/core/app_info_panel.dart`

- [ ] **Step 1: Finalize hum/playback coordination**

Rules to enforce:
- Stopping a hum take can update `selectedColumnTick` when there was no previous selection
- Starting a hum take should stop active playback if transport is already running
- Playback should refuse to start while hum status is `recording` or `processing`
- No save-system schema changes
- Playback completion should not clear `selectedColumnTick`
- Stopping playback manually should not modify note selection or the imported-note selection state

- [ ] **Step 2: Document user-visible behavior**

Update `docs/piano_roll.md` and any visible help text to reflect:
- hum import expands measures horizontally when needed
- playback starts from the selected column
- playback runs to the end of the roll
- no pitch-range auto-growth in this follow-up

- [ ] **Step 3: Run the full focused verification set**

Run:

```bash
flutter test test/store/piano_roll_store_test.dart
flutter test test/store/hum_to_midi_store_test.dart
flutter test test/schema/rules/piano_roll_playback_rules_test.dart
flutter test test/store/piano_roll_playback_store_test.dart
flutter test test/features/piano_roll/piano_roll_playback_config_test.dart
flutter analyze
```

Expected:
- All targeted tests PASS
- `flutter analyze` reports no new issues

- [ ] **Step 4: Smoke-test the piano roll flow manually**

Manual checklist:
- Hum a phrase near the current timeline end and confirm the roll adds measures when needed
- Confirm the new notes remain editable after import
- Tap a column, press Play, and confirm playback starts there and continues until the end of the roll timeline
- Confirm Stop works during playback
- Confirm Play is disabled while recording

- [ ] **Step 5: Commit**

```bash
git add lib/store/hum_to_midi_store.dart docs/piano_roll.md lib/ui/core/app_info_panel.dart
git commit -m "docs: describe piano roll hum follow-up behavior"
```

**Acceptance criteria:**
- Hum import and playback no longer fight each other
- Docs match the shipped behavior
- The implementation is ready for orchestrator dispatch and final review

---

## Execution Notes For The Orchestrator

- Execute **Task 1 → Task 5** in order
- `Task 2` and `Task 3` are tightly coupled and should stay serial unless the orchestrator splits rules/model work from store work carefully
- `Task 4` should begin only after `Task 3` exposes a stable playback provider contract
- `Task 5` should include a brief audit of whether `main.dart` was actually needed; if not, remove any unnecessary wiring added during Task 3
- Preserve unrelated worktree changes

## Out Of Scope

- pitch-range auto-growth after hum import
- pause/resume playback
- loop mode
- metronome or count-in
- animated playhead or grid auto-scroll during playback
- multi-track playback or velocity editing
- exporting rendered audio or MIDI
