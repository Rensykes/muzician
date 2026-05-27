# Piano Roll Scale State And Stack Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Piano Roll scale drawer so the selected-scale pill survives drawer close/reopen, replace the duplicated `Stack Composer` / `Stack Selector` flow with one unified `Stack Builder`, and restore a fast stack-reuse path: copy the current selected stack when something is selected, otherwise quickly repeat the latest added stack.

**Architecture:** Mirror the existing active-vs-pending scale pattern already used by Piano and Fretboard; introduce one builder model and one builder store for the final stack notes; keep chord-generation and recognition logic in `lib/schema/rules/`; add a lightweight transient quick-stack payload for copy/repeat behavior in the Piano Roll state layer; replace duplicated portrait and landscape stack-entry surfaces in `PianoRollScreenV2` with one shared builder widget.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, immutable models, `flutter_test`, existing Piano Roll store and note rules, shared in-app help panel, manual compact/wide UI verification with Simulator / `serve-sim`.

---

## Task Graph

### Sequential spine

1. Task 1 establishes the persistent Piano Roll scale state.
2. Task 2 establishes the new stack-builder data model and rule contracts.
3. Task 3 wires those contracts into Riverpod state transitions.
4. Task 4 builds the unified builder UI on top of the new store.
5. Task 5 integrates that UI into portrait and landscape, removing the duplicated flows.
6. Task 6 updates product documentation and in-app guidance.
7. Task 7 and Task 8 perform focused review and final verification.

### Safe parallelization

- Task 1 can run independently from all stack-builder work.
- Task 2 and Task 6 can overlap once the spec is frozen.
- Task 7 review subtasks can run in parallel after Tasks 1 through 6 land.

### Recommended ownership

- `state-architect`: Tasks 1 and 3
- `music-theory`: Task 2 and the recognition portion of Task 7
- `instrument-renderer`: Tasks 4 and 5
- general-purpose sub-agent: Task 6
- `accessibility-ux`: UX review task in Task 7
- `code-quality`: code review task in Task 7

---

## File Structure

### Modify

- `lib/store/piano_roll_store.dart`
- `lib/features/piano_roll/piano_roll_scale_picker.dart`
- `lib/features/piano_roll/piano_roll_screen_v2.dart`
- `lib/ui/core/app_info_panel.dart`
- `docs/piano_roll.md`

### Likely Create

- `lib/models/piano_roll_stack_builder.dart`
- `lib/schema/rules/piano_roll_stack_builder_rules.dart`
- `lib/store/piano_roll_stack_builder_store.dart`
- `lib/features/piano_roll/piano_roll_stack_builder.dart`
- `test/schema/rules/piano_roll_stack_builder_rules_test.dart`
- `test/store/piano_roll_stack_builder_store_test.dart`
- `test/features/piano_roll/piano_roll_stack_builder_test.dart`
- `test/features/piano_roll/piano_roll_scale_picker_test.dart`

### Likely Remove Or Retire

- `lib/features/piano_roll/piano_roll_stack_selector.dart`
- `lib/store/piano_roll_composer_store.dart`
- `lib/models/piano_roll_composer.dart`

Only remove legacy files after all call sites are migrated and tests are green.

---

## Task 1: Persist The Selected Scale In Piano Roll

**Owner:** `state-architect`  
**Scope:** active/pending scale state, scale-picker reconstruction, drawer reopen regression tests  
**Dependencies:** none

**Files:**

- Modify: `lib/store/piano_roll_store.dart`
- Modify: `lib/features/piano_roll/piano_roll_scale_picker.dart`
- Test: `test/features/piano_roll/piano_roll_scale_picker_test.dart`
- Possibly extend: `test/features/piano_roll/piano_roll_screen_v2_test.dart`

- [ ] **Step 1: Add failing tests for committed scale state**

Cover these behaviors:

- selecting a scale commits `pianoRollActiveScaleProvider`
- closing and reopening the picker reconstructs the pill from `active`
- clearing the selection clears both active and visible pill
- pending detection prefill applies once, then yields to committed active state

Suggested test names:

```dart
testWidgets('selected scale pill persists after picker rebuild', ...)
testWidgets('pending scale prefill does not erase committed active scale', ...)
testWidgets('clear resets active and removes selected scale pill', ...)
```

- [ ] **Step 2: Run the narrow test target and confirm failure**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_scale_picker_test.dart
```

Expected: fail because the committed active provider does not exist yet.

- [ ] **Step 3: Introduce committed active scale state in the store**

Mirror the proven piano/fretboard pattern in `lib/store/piano_roll_store.dart`:

```dart
final pianoRollPendingScaleProvider =
    StateProvider<DetectedScaleSnapshot?>((ref) => null);

final pianoRollActiveScaleProvider =
    StateProvider<DetectedScaleSnapshot?>((ref) => null);
```

If the app already uses a more specific active-scale type elsewhere, reuse that type instead of inventing a new one.

- [ ] **Step 4: Make the picker read from active first and use pending only as prefill**

Implementation contract in `PianoRollScalePicker`:

- on init / dependency change, reconstruct local UI state from `pianoRollActiveScaleProvider` first
- if `pending` exists, use it to prefill only once, then immediately clear `pending`
- when the user confirms or changes a scale, write the committed value to `pianoRollActiveScaleProvider`
- when the user clears the picker, clear `pianoRollActiveScaleProvider`

Pseudocode:

```dart
final active = ref.watch(pianoRollActiveScaleProvider);
final pending = ref.watch(pianoRollPendingScaleProvider);

if (pending != null) {
  _applyScaleSnapshot(pending);
  ref.read(pianoRollActiveScaleProvider.notifier).state = pending;
  ref.read(pianoRollPendingScaleProvider.notifier).state = null;
} else if (active != null) {
  _applyScaleSnapshot(active);
}
```

Use the smallest safe variation that matches the widget lifecycle already in the file.

- [ ] **Step 5: Re-run the focused tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_scale_picker_test.dart
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/store/piano_roll_store.dart \
  lib/features/piano_roll/piano_roll_scale_picker.dart \
  test/features/piano_roll/piano_roll_scale_picker_test.dart
git commit -m "fix(piano roll): persist selected scale state"
```

**Acceptance criteria:**

- the scale pill survives drawer close/reopen
- pending detection prefill no longer becomes the only source of truth
- no regression in existing scale highlight behavior

---

## Task 2: Define The Stack Builder Domain Model And Rules

**Owner:** `music-theory`  
**Scope:** builder model, canonical generation with inversions, recognition, custom-voicing detection, exact-note uniqueness rules, continuous canonical transformation helpers  
**Dependencies:** none

**Files:**

- Create: `lib/models/piano_roll_stack_builder.dart`
- Create: `lib/schema/rules/piano_roll_stack_builder_rules.dart`
- Test: `test/schema/rules/piano_roll_stack_builder_rules_test.dart`

- [ ] **Step 1: Write the rule-level regression suite first**

Required coverage:

- canonical generation supports inversions for supported chord qualities
- `G2 C3 E3 G3 C4` recognizes as `C maj`, second inversion, custom voicing
- repeated chord tones across octaves do not break root/quality recognition
- exact duplicate absolute notes are rejected
- 11th note is rejected or clipped according to the chosen API contract
- canonical retargeting after advanced customization preserves note count and stays near the prior register
- unsupported pitch-class sets degrade to `unrecognized`

Suggested test names:

```dart
test('generateCanonicalStack creates triad inversions in ascending order', ...)
test('recognizeStack identifies C major second inversion custom voicing', ...)
test('recognizeStack ignores repeated tones across octaves for identity', ...)
test('validateExactMidiUniqueness rejects duplicate absolute notes', ...)
test('enforceMaxNotes rejects stacks longer than ten notes', ...)
test('retargetCanonicalStack preserves note count and near-register continuity', ...)
test('recognizeStack returns unrecognized for unsupported pitch-class sets', ...)
```

- [ ] **Step 2: Run the rules test target and confirm failure**

Run:

```bash
flutter test test/schema/rules/piano_roll_stack_builder_rules_test.dart
```

Expected: fail because the model/rules file does not exist yet.

- [ ] **Step 3: Create the builder model**

Recommended minimum model shape:

```dart
enum PianoRollStackBuilderView { canonical, advanced }

class PianoRollStackBuilderState {
  final List<int> midiNotes;
  final int durationTicks;
  final PianoRollStackBuilderView activeView;
  final String? recognizedRoot;
  final String? recognizedQuality;
  final int? recognizedInversionIndex;
  final bool isRecognized;
  final bool isCustomVoicing;

  const PianoRollStackBuilderState({...});
}
```

If the repo already prefers richer note-entry objects than raw MIDI ints, use those. The important contract is one ordered final-note list with absolute pitch.

- [ ] **Step 4: Implement deterministic rule helpers**

Required public helpers:

- canonical generation from `root + quality + inversion + target count`
- recognition from final note list
- custom-voicing detection
- exact-note uniqueness validation
- max-note enforcement
- canonical retargeting that preserves note count and stays near current register

Suggested signatures:

```dart
PianoRollStackRecognition recognizeStack(List<int> midiNotes);
bool containsExactMidi(List<int> midiNotes, int midiNote, {int? excludingIndex});
List<int> generateCanonicalStack({
  required String root,
  required String quality,
  required int inversionIndex,
  required int noteCount,
  int? anchorMidi,
});
List<int> retargetCanonicalStack({
  required List<int> currentMidiNotes,
  required String root,
  required String quality,
  required int inversionIndex,
});
List<int> enforceMaxNotes(List<int> midiNotes, {int maxNotes = 10});
```

Guardrails:

- recognition ignores repeated chord tones across octaves for identity
- exact duplicate absolute notes are invalid for advanced add/edit
- inversion is derived from the lowest absolute note pitch class
- canonical generation returns strictly ascending notes
- retargeting preserves note count when possible and minimizes register jumps

- [ ] **Step 5: Re-run rules tests**

Run:

```bash
flutter test test/schema/rules/piano_roll_stack_builder_rules_test.dart
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add lib/models/piano_roll_stack_builder.dart \
  lib/schema/rules/piano_roll_stack_builder_rules.dart \
  test/schema/rules/piano_roll_stack_builder_rules_test.dart
git commit -m "feat(piano roll): add stack builder rules"
```

**Acceptance criteria:**

- recognized custom voicings retain parent chord identity when supported
- canonical generation and inversion contracts are test-backed
- rule output is deterministic and UI-free

---

## Task 3: Add The Stack Builder Store And Riverpod Transitions

**Owner:** `state-architect`  
**Scope:** builder state transitions, advanced edits, canonical edits, quick copy/repeat payload management, add-stack dispatch into Piano Roll  
**Dependencies:** Task 2

**Files:**

- Create: `lib/store/piano_roll_stack_builder_store.dart`
- Modify: `lib/store/piano_roll_store.dart`
- Test: `test/store/piano_roll_stack_builder_store_test.dart`
- Extend: `test/store/piano_roll_store_test.dart` when quick-stack behavior lands there

- [ ] **Step 1: Write failing store tests before implementation**

Required scenarios:

- default builder starts in canonical view with a valid canonical stack
- switching tabs preserves current final notes
- advanced add/remove/edit/reorder mutate the same final note list
- add and edit reject exact duplicate absolute notes
- 10-note cap blocks or clips the 11th note according to the chosen contract
- canonical edits after advanced customization preserve note count
- `addStack` inserts the exact current builder notes into `pianoRollProvider`
- quick action copies the current selection when there is one
- quick action repeats the latest added stack when there is no selection
- a successful add updates the latest-stack payload used by quick repeat

Suggested tests:

```dart
test('switchView preserves final notes', ...)
test('addAbsoluteNote rejects duplicate absolute note', ...)
test('replaceNoteAt rejects duplicate absolute note', ...)
test('reorderNotes updates final note order without changing count', ...)
test('changeCanonicalRoot retargets without resetting note count', ...)
test('addStack inserts current builder notes at selected column tick', ...)
test('quickAddSelectedOrLatest copies current selection to selected column', ...)
test('quickAddSelectedOrLatest repeats latest stack when nothing is selected', ...)
```

- [ ] **Step 2: Run the store test target and confirm failure**

Run:

```bash
flutter test test/store/piano_roll_stack_builder_store_test.dart
```

- [ ] **Step 3: Implement the notifier with one source of truth**

Recommended API surface:

```dart
final pianoRollStackBuilderProvider = NotifierProvider<
    PianoRollStackBuilderNotifier, PianoRollStackBuilderState>(...);

class PianoRollStackBuilderNotifier
    extends Notifier<PianoRollStackBuilderState> {
  void switchView(PianoRollStackBuilderView view);
  void setCanonicalRoot(String root);
  void setCanonicalQuality(String quality);
  void setCanonicalInversion(int inversionIndex);
  void setDurationTicks(int durationTicks);
  StackEditResult addAbsoluteNote(int midiNote);
  void removeNoteAt(int index);
  void reorderNotes(int oldIndex, int newIndex);
  StackEditResult replaceNoteAt(int index, int midiNote);
  void insertDegreeShortcut(String degree);
  void addStack();
}
```

Suggested quick-path surface in `piano_roll_store.dart` or an adjacent focused provider:

```dart
class PianoRollStackPastePayload {
  final List<PianoRollStackPasteNote> notes;
}

void rememberLatestStackPayload(PianoRollStackPastePayload payload);
void quickAddSelectedOrLatest();
```

Implementation rules:

- `midiNotes` is always the final source of truth
- canonical setters call the rules layer and update derived recognition
- advanced edits mutate `midiNotes` directly, then recompute recognition
- advanced add/edit reject exact duplicate MIDI notes and return a result the UI can surface inline
- `addStack()` writes notes into `pianoRollProvider` at `selectedColumnTick ?? 0`
- every successful stack insertion updates the remembered latest-stack payload
- quick insertion copies the selected notes when `selectedNoteIds` is non-empty, preserving relative offsets and per-note durations
- otherwise quick insertion uses the remembered latest-stack payload without mutating the current builder draft

- [ ] **Step 4: Re-run store tests**

Run:

```bash
flutter test test/store/piano_roll_stack_builder_store_test.dart
```

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/store/piano_roll_stack_builder_store.dart \
  lib/store/piano_roll_store.dart \
  test/store/piano_roll_stack_builder_store_test.dart
git commit -m "feat(piano roll): add stack builder state transitions"
```

**Acceptance criteria:**

- canonical and advanced edits are interscambiable on the same final note list
- `addStack` no longer depends on the limited composer model
- quick reuse covers both selected-stack copy and repeat-last-stack behavior
- store behavior is fully covered by focused tests

---

## Task 4: Build The Unified Stack Builder Widget

**Owner:** `instrument-renderer`  
**Scope:** builder widget, tabbed canonical/advanced UI, shared preview and footer, widget tests  
**Dependencies:** Tasks 2 and 3

**Files:**

- Create: `lib/features/piano_roll/piano_roll_stack_builder.dart`
- Test: `test/features/piano_roll/piano_roll_stack_builder_test.dart`

- [ ] **Step 1: Write focused widget tests first**

Required behaviors:

- shows `Canonico` and `Avanzato` tabs
- both tabs reflect the same final note preview
- canonical summary header shows recognized chord + `custom voicing` when appropriate
- advanced view supports add/remove/edit entry affordances
- advanced add/edit uses an inline in-drawer note picker + octave picker, not free-text parsing
- duplicate absolute note attempts surface an inline error
- add action is disabled or guarded when there are no notes
- add/edit does not open a modal dialog above the drawer
- add/edit enters a wizard state that replaces the normal advanced content instead of appending a new component below the note list

Suggested tests:

```dart
testWidgets('tabs share the same final stack preview', ...)
testWidgets('header shows recognized custom voicing badge', ...)
testWidgets('advanced actions dispatch to builder store', ...)
testWidgets('advanced add opens inline drawer wizard', ...)
testWidgets('advanced edit opens inline drawer wizard', ...)
testWidgets('wizard replaces advanced content instead of rendering below note list', ...)
testWidgets('duplicate absolute note attempt shows validation error', ...)
testWidgets('add stack action uses current builder state', ...)
```

- [ ] **Step 2: Run the widget target and confirm failure**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_stack_builder_test.dart
```

- [ ] **Step 3: Implement the widget with one shared footer and preview**

Required UI sections:

1. header:
   - recognized chord summary
   - inversion label
   - `Custom voicing` badge when recognized but non-normalized
   - `Unrecognized custom stack` fallback
2. segmented control or tab switch:
   - `Canonico`
   - `Avanzato`
3. canonical body:
   - root
   - quality
   - inversion
   - duration
4. advanced body:
   - absolute note list
   - add/remove/edit/reorder controls
   - default mode with list/actions
   - wizard mode that replaces the default advanced body while active
   - note picker + octave picker inside that wizard mode
   - live preview + confirm/cancel inside the same drawer surface
   - degree-shortcut entry
5. shared footer:
   - final note preview
   - single `Add Stack` action

Keep the implementation minimal and consistent with the current design system.
Prioritize readability on compact portrait layouts over always showing every
secondary control at once.
Do not solve this by appending another dense editor block below the note list.

- [ ] **Step 4: Re-run widget tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_stack_builder_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/piano_roll/piano_roll_stack_builder.dart \
  test/features/piano_roll/piano_roll_stack_builder_test.dart
git commit -m "feat(piano roll): add unified stack builder widget"
```

**Acceptance criteria:**

- the builder exposes one coherent UI instead of duplicated flows
- the footer preview always reflects the shared final-note source of truth
- canonical and advanced tabs are visibly interscambiable
- advanced mode no longer depends on free-text note entry or duplicate/copy actions
- add/edit stays inside the drawer instead of spawning a modal picker
- add/edit uses a wizard state, not an extra component under the note list

---

## Task 5: Integrate The Builder And Remove Duplicated Stack Flows

**Owner:** `instrument-renderer`  
**Scope:** portrait drawer integration, landscape inspector integration, legacy flow retirement, screen-level tests  
**Dependencies:** Tasks 1, 3, and 4

**Files:**

- Modify: `lib/features/piano_roll/piano_roll_screen_v2.dart`
- Remove or retire: `lib/features/piano_roll/piano_roll_stack_selector.dart`
- Remove or retire: `lib/store/piano_roll_composer_store.dart`
- Remove or retire: `lib/models/piano_roll_composer.dart`
- Extend: `test/features/piano_roll/piano_roll_screen_v2_test.dart`

- [ ] **Step 1: Add failing integration tests**

Cover these behaviors:

- portrait exposes one `Stack Builder` entry instead of separate `Stack Composer` / `Stack Selector`
- landscape shows one unified builder section
- reopening the scale drawer still shows the committed pill
- `Add Stack` from the integrated builder inserts notes through the shared store
- quick action copies the current selection when one exists
- quick action repeats the latest added stack when no selection exists

Suggested tests:

```dart
testWidgets('portrait shows one Stack Builder entry', ...)
testWidgets('landscape shows one unified Stack Builder section', ...)
testWidgets('scale drawer rebuild keeps selected scale pill visible', ...)
testWidgets('quick action copies selected stack to current column', ...)
testWidgets('quick action repeats latest stack when nothing is selected', ...)
```

- [ ] **Step 2: Run the screen-level target and confirm failure**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

- [ ] **Step 3: Replace duplicated composition surfaces**

Integration tasks:

- portrait:
  - rename the drawer entry to `Stack Builder`
  - mount the new `PianoRollStackBuilder`
  - expose one `Quick` action with dual behavior:
    - selection present → copy/paste selection
    - no selection → repeat latest stack
  - remove the old composer sheet and selector branch
- landscape:
  - replace separate composer/selector blocks with one builder section
  - expose the same quick action semantics
  - preserve responsive spacing and compact layout behavior
- remove unused legacy imports and dead code

- [ ] **Step 4: Retire obsolete model/store/widget pieces only after migration**

Safe removal checklist:

- no more references to `PianoRollStackSelector`
- no more references to `PianoRollComposerNotifier`
- no remaining tests coupled to the old composer-only state

If full removal introduces churn, keep the files temporarily but make them unreachable and document follow-up cleanup.

- [ ] **Step 5: Re-run screen tests**

Run:

```bash
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/piano_roll/piano_roll_screen_v2.dart \
  lib/features/piano_roll/piano_roll_stack_builder.dart \
  test/features/piano_roll/piano_roll_screen_v2_test.dart \
  lib/features/piano_roll/piano_roll_stack_selector.dart \
  lib/store/piano_roll_composer_store.dart \
  lib/models/piano_roll_composer.dart
git commit -m "refactor(piano roll): unify stack builder flows"
```

**Acceptance criteria:**

- there is exactly one stack-creation flow in Piano Roll
- portrait and landscape both use the same builder concept
- old composer/selector duplication is gone or fully retired from runtime

---

## Task 6: Update Product Documentation And In-App Guidance

**Owner:** general-purpose sub-agent  
**Scope:** docs sync for scale persistence and unified stack builder behavior  
**Dependencies:** Tasks 1 through 5 for final naming/API accuracy

**Files:**

- Modify: `docs/piano_roll.md`
- Modify: `lib/ui/core/app_info_panel.dart`
- Optionally update spec-adjacent doc references if the implementation renames exposed concepts

- [ ] **Step 1: Update `docs/piano_roll.md`**

Document:

- the persistent selected-scale pill behavior
- `Stack Builder` replacing `Stack Composer` and `Stack Selector`
- canonical vs advanced editing on one shared final stack
- support for inversions, repeated tones across octaves, free octave placement, and max 10 notes
- prevention of exact duplicate absolute notes in advanced mode
- quick copy of the selected stack vs repeat of the latest added stack
- behavior of `custom voicing` and `Unrecognized custom stack`

- [ ] **Step 2: Update in-app Piano Roll help copy**

Add or revise help content so users can discover:

- how the scale picker behaves after selection
- how to use `Canonico` vs `Avanzato`
- that advanced stacks can still be recognized canonically
- that advanced add/edit uses note + octave pickers
- that exact duplicate absolute notes are rejected
- how `Quick` decides between copying the selection and repeating the latest stack
- that canonical edits after advanced customization preserve the current stack shape as much as possible

- [ ] **Step 3: Verify docs against the final API and UI labels**

Checklist:

- `Stack Builder` naming matches the actual UI
- provider or method names mentioned in docs exist
- examples use real supported voicings such as `G2 C3 E3 G3 C4`

- [ ] **Step 4: Commit**

```bash
git add docs/piano_roll.md lib/ui/core/app_info_panel.dart
git commit -m "docs: update piano roll stack builder guidance"
```

**Acceptance criteria:**

- docs match shipped labels and flows
- in-app help is enough for a first-time user to discover the new builder

---

## Task 7: Review Tasks For Specialist Sub-Agents

These are explicit review-only assignments and should not introduce broad refactors.

### Review 7A: Music-Theory Correctness Review

**Owner:** `music-theory`  
**Scope:** audit-only

- [ ] Validate that inversion detection uses the lowest pitch class correctly.
- [ ] Validate that repeated tones across octaves are ignored for identity but still flag `custom voicing`.
- [ ] Validate that exact duplicate absolute notes are rejected by the advanced-edit contract.
- [ ] Validate that canonical retargeting preserves count and does not create illegal descending note order.
- [ ] Spot-check supported chord qualities against the repo’s existing chord-generation rules.

Suggested command:

```bash
flutter test test/schema/rules/piano_roll_stack_builder_rules_test.dart
```

Deliverable:

- concise findings list ordered by severity
- explicit note if no findings are discovered

### Review 7B: UX And Accessibility Review

**Owner:** `accessibility-ux`  
**Scope:** audit-only

- [ ] Verify that `Canonico` / `Avanzato` controls remain readable on compact width.
- [ ] Verify touch targets for advanced note-row actions.
- [ ] Verify the inline drawer wizard editing flow on compact width.
- [ ] Verify that entering the wizard replaces the advanced content rather than stacking another editor under the list.
- [ ] Verify that the recognized-state header is understandable in both `custom voicing` and `unrecognized` states.
- [ ] Verify that `Quick` clearly communicates whether it will copy the selection or repeat the latest stack.
- [ ] Verify that portrait and landscape maintain consistent terminology.

Suggested verification:

- compact iPhone simulator
- one wide landscape layout

Deliverable:

- concise findings list with file references when possible

### Review 7C: Code Quality Review

**Owner:** `code-quality`  
**Scope:** audit-only

- [ ] Check for dead legacy code after the migration.
- [ ] Check provider lifecycle and rebuild behavior for the scale picker.
- [ ] Check that music logic stayed out of widgets and lives in `lib/schema/rules/`.
- [ ] Check that quick-stack payload ownership lives in state/store, not in widgets.
- [ ] Check imports, naming, and notifier API consistency.

Suggested command:

```bash
flutter analyze
```

Deliverable:

- concise findings list with severity ordering

---

## Task 8: Final Verification And Release Readiness

**Owner:** orchestrating agent or final integrator  
**Scope:** end-to-end verification only  
**Dependencies:** Tasks 1 through 7

- [ ] **Step 1: Format changed paths**

Run:

```bash
dart format \
  lib/store/piano_roll_store.dart \
  lib/features/piano_roll/piano_roll_scale_picker.dart \
  lib/models/piano_roll_stack_builder.dart \
  lib/schema/rules/piano_roll_stack_builder_rules.dart \
  lib/store/piano_roll_stack_builder_store.dart \
  lib/features/piano_roll/piano_roll_stack_builder.dart \
  lib/features/piano_roll/piano_roll_screen_v2.dart \
  lib/ui/core/app_info_panel.dart \
  docs/piano_roll.md \
  test/schema/rules/piano_roll_stack_builder_rules_test.dart \
  test/store/piano_roll_stack_builder_store_test.dart \
  test/features/piano_roll/piano_roll_stack_builder_test.dart \
  test/features/piano_roll/piano_roll_scale_picker_test.dart \
  test/features/piano_roll/piano_roll_screen_v2_test.dart
```

- [ ] **Step 2: Run the narrowest relevant test targets**

Run:

```bash
flutter test test/schema/rules/piano_roll_stack_builder_rules_test.dart
flutter test test/store/piano_roll_stack_builder_store_test.dart
flutter test test/features/piano_roll/piano_roll_stack_builder_test.dart
flutter test test/features/piano_roll/piano_roll_scale_picker_test.dart
flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart
```

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

- [ ] **Step 4: Verify on compact and wide layouts**

Manual checks:

- compact iPhone portrait:
  - select a scale
  - close and reopen the drawer
  - confirm the pill remains visible
  - open `Stack Builder`
  - build a canonical stack with inversion
  - switch to `Avanzato`
  - add a note through the inline drawer wizard
  - edit an existing note through the inline drawer wizard
  - confirm the wizard replaces the normal advanced body instead of appearing below the note list
  - confirm exact duplicate note attempts show an error
  - confirm shared preview remains consistent
  - with a note selection active, use `Quick` and confirm it pastes the selected stack at the current column
  - clear selection, use `Quick`, and confirm it repeats the latest added stack
- wide / landscape:
  - confirm one builder section only
  - confirm `Quick` exposes the same dual behavior
  - confirm no overflow or collapsed controls

- [ ] **Step 5: Prepare final integration summary**

Include:

- what changed
- tests run
- review findings resolved or deferred
- any leftover risk, especially around chord-recognition edge cases

---

## Definition Of Done

- the Piano Roll scale drawer keeps the selected-scale pill after close/reopen
- there is one `Stack Builder`, not separate composer and selector flows
- `Canonico` and `Avanzato` edit the same final note list
- canonical stacks support inversion control
- advanced stacks support repeated tones across octaves, free octaves, reorder, add/edit via an inline drawer wizard with note + octave pickers, and max 10 notes
- exact duplicate absolute notes are rejected with clear feedback
- the advanced wizard replaces the normal advanced content instead of extending it downward
- `Quick` copies the current selection when one exists
- `Quick` repeats the latest added stack when nothing is selected
- recognized custom voicings such as `G2 C3 E3 G3 C4` keep their chord identity where supported
- unrecognized stacks degrade clearly instead of guessing
- documentation and in-app help match the shipped UI
- focused tests, analyzer, and manual compact/wide verification all pass
