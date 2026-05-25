# Piano Roll V2 Parity And DAW Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Piano Roll V2 as a real, parity-complete editor surface backed by shared UI-agnostic logic, while adding first-class piano-roll save/load, safe web support, and a real landscape layout without regressing any existing V1 behavior.

**Architecture:** Preserve `PianoRollState` as the canonical editable timeline, extract duplicated theory/import/composer logic into shared rules and small focused providers, add `PianoRollSnapshot` to the shared save system, and let both V1 and V2 render the same domain contracts. Treat V1 as the behavioral baseline and V2 as the target product shell.

**Tech Stack:** Flutter, Riverpod `NotifierProvider` and derived providers, `flutter_test`, existing shared save system, existing piano-roll playback and hum stores, shared theory helpers in `lib/utils/note_utils.dart`, mobile verification with `serve-sim` when simulator access is available.

---

## Brainstorm Summary

### Option 1: Directly wire V1 widgets into the V2 mockup

- Pros: quickest visible parity
- Cons: keeps V2 local fake state, preserves widget duplication, and does not meet the “logic must be UI agnostic” requirement

### Option 2: Extract shared Piano Roll foundations, then recompose V1 and V2

- Pros: best long-term architecture, clear subagent ownership, safe path for web and landscape, and the cleanest route to first-class piano-roll persistence
- Cons: requires more sequencing discipline and a larger initial diff

### Option 3: Full DAW shell rewrite

- Pros: maximum design freedom
- Cons: too large, too risky, and needlessly discards the strong V1 contracts already in the repo

### Recommendation

Choose **Option 2**. The codebase already has real store, grid, playback, hum,
and test coverage. External agents should build on those contracts instead of
rewriting them.

---

## Locked Product Decisions

- V2 is the target product surface, but V1 remains available as a compatibility shell until explicit sign-off.
- Piano Roll note data remains canonical in `pianoRollProvider`.
- Shared logic must move out of V1-only and V2-only widget-local state.
- `PianoRollSnapshot` is in scope and required.
- `PianoRollSaveStackLoader` remains the cross-instrument importer for Fretboard and Piano saves.
- Hum to MIDI remains mobile-only. Web must not expose a broken record flow.
- Landscape mode is required and must be adaptive, not just resized portrait.
- This initiative does not add looping, velocity lanes, multi-track sequencing, undo/redo, or MIDI export.

---

## File Structure

### Create

- `lib/models/piano_roll_composer.dart`
  Shared immutable state for root, quality, and duration choices used by both shells.
- `lib/schema/rules/piano_roll_import_rules.dart`
  Pure stack-building and snapshot-import helpers moved out of widgets.
- `lib/store/piano_roll_composer_store.dart`
  Riverpod store for shared composer state and shared “add stack” behavior.
- `lib/features/piano_roll/piano_roll_save_panel.dart`
  First-class Piano Roll save/load/update UI.
- `lib/features/piano_roll/piano_roll_screen_v2.dart`
  Real V2 surface backed by providers instead of mock state.
- `test/schema/rules/piano_roll_import_rules_test.dart`
  Pure tests for stack building and save-import mapping.
- `test/store/piano_roll_composer_store_test.dart`
  Tests for composer defaults, mutations, and add-stack routing.
- `test/features/piano_roll/piano_roll_screen_v2_test.dart`
  Widget tests for V2 parity-critical behavior.
- `test/features/piano_roll/piano_roll_save_panel_test.dart`
  Widget tests for piano-roll save/load UI.

### Modify

- `lib/utils/note_utils.dart`
  Keep as single source of truth for chord/scale catalogs and shared detection formatting.
- `lib/models/piano_roll.dart`
  Add only canonically persisted editor fields if absolutely required; avoid bloating it with panel-local UI.
- `lib/models/save_system.dart`
  Add `PianoRollSnapshot` and update `InstrumentSnapshot.fromJson`.
- `lib/store/piano_roll_store.dart`
  Add shared editor actions that must no longer live in widget-local code.
- `lib/store/save_system_store.dart`
  Support piano-roll snapshot save/load/update flows.
- `lib/features/piano_roll/piano_roll_stack_selector.dart`
  Replace local chord catalog and local add-stack logic with composer provider usage.
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
  Replace embedded import mapping logic with shared import rules and filter behavior.
- `lib/features/piano_roll/piano_roll_detection_panel.dart`
  Replace local detection catalog with shared exact-note analysis helpers.
- `lib/features/piano_roll/piano_roll_grid.dart`
  Preserve existing gestures, then add web/landscape-safe interaction improvements.
- `lib/features/piano_roll/piano_roll_hum_recorder.dart`
  Gate by platform capabilities and expose the same behavior inside V2.
- `lib/features/piano_roll/piano_roll_toolbar.dart`
  Keep working as the shared config surface until V2 consumes the same provider-backed widgets.
- `lib/main.dart`
  Keep V1 wired to shared providers and route the mockup launcher to the real V2 screen.
- `lib/ui/core/app_info_panel.dart`
  Update Piano Roll help text for V2, web shortcuts, and landscape behavior.
- `docs/piano_roll.md`
  Update architecture, save semantics, V2 layout, web gating, and gesture documentation.

### Consider Splitting During Implementation

- `lib/features/piano_roll/piano_roll_grid.dart`
  Split by painters vs. gesture/controller logic if the diff becomes hard to review.
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
  Split by import mapping vs. panel UI once shared rules are introduced.

---

## Task 1: Shared Theory And Import Foundations

**Owner:** `music-theory`

**Reviewers after implementation:** spec compliance reviewer, then `code-quality`

**Goal:** Remove Piano Roll’s duplicated chord, scale, and snapshot-import logic from widgets by consolidating it into shared theory and pure rules.

**Files to read first:**

- `lib/utils/note_utils.dart`
- `lib/features/piano_roll/piano_roll_stack_selector.dart`
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
- `lib/features/piano_roll/piano_roll_detection_panel.dart`
- `lib/models/save_system.dart`
- `test/utils/note_utils_test.dart`

**Files to create or modify:**

- Create: `lib/schema/rules/piano_roll_import_rules.dart`
- Modify: `lib/utils/note_utils.dart`
- Modify: `lib/features/piano_roll/piano_roll_stack_selector.dart`
- Modify: `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
- Modify: `lib/features/piano_roll/piano_roll_detection_panel.dart`
- Create: `test/schema/rules/piano_roll_import_rules_test.dart`
- Modify: `test/utils/note_utils_test.dart`

**Implementation contract:**

- Add pure helpers for:
  - `bestMidiInRangeForPitchClass(...)`
  - `buildChordStackMidis(...)`
  - `extractSnapshotImportMidis(...)`
- Keep `note_utils.dart` as the source of truth for chord/scale catalogs.
- Detection panel must use shared exact-note APIs:
  - `detectChordResultsFromExactNotes(...)`
  - `detectScaleResultsFromExactNotes(...)`
  - `formatChordSymbol(...)`
  - `formatScaleLabel(...)`
- `PianoRollSaveStackLoader` must keep importing only Fretboard and Piano snapshots.
- Remove local duplicates such as `_chordIntervals`, `_noteToPC`, `_bestMidiInRange`, and the local `_detect(...)` catalog when the shared helpers replace them.

**TDD checklist:**

- [ ] Write failing pure tests for chord-stack building from canonical root/quality values.
- [ ] Write failing pure tests for exact import mode from `FretboardSnapshot`.
- [ ] Write failing pure tests for exact import mode from `PianoSnapshot`.
- [ ] Write failing pure tests for pitch-class import mode centering inside the current pitch range.
- [ ] Write failing pure tests proving the detection panel can source its chord and scale labels from shared exact-note APIs.
- [ ] Run only the targeted test files and confirm they fail for the expected missing-helper or old-behavior reasons.
- [ ] Implement the minimal shared helpers and rewire the three widgets to call them.
- [ ] Re-run the targeted tests and confirm they pass.

**Targeted test commands:**

- `flutter test test/schema/rules/piano_roll_import_rules_test.dart`
- `flutter test test/utils/note_utils_test.dart`

**Expected review focus:**

- no theory duplication remains in Piano Roll widgets
- no widget parses formatted harmonic strings back into canonical data when a typed result exists
- import helpers stay pure and UI-free

**Suggested commit message:** `refactor: share piano roll theory and import helpers`

---

## Task 2: Shared Composer And Editor-State De-Localization

**Owner:** `state-architect`

**Reviewers after implementation:** spec compliance reviewer, then `code-quality`

**Goal:** Move V1/V2 shared composer and editor actions out of widget-local state so both shells can render the same behavior.

**Files to read first:**

- `lib/models/piano_roll.dart`
- `lib/store/piano_roll_store.dart`
- `lib/features/piano_roll/piano_roll_stack_selector.dart`
- `lib/features/piano_roll/piano_roll_screen_v2_mockup.dart`
- `lib/features/piano_roll/piano_roll_toolbar.dart`
- `test/store/piano_roll_store_test.dart`

**Files to create or modify:**

- Create: `lib/models/piano_roll_composer.dart`
- Create: `lib/store/piano_roll_composer_store.dart`
- Modify: `lib/store/piano_roll_store.dart`
- Modify: `lib/features/piano_roll/piano_roll_stack_selector.dart`
- Modify: `lib/features/piano_roll/piano_roll_screen_v2_mockup.dart`
- Create: `test/store/piano_roll_composer_store_test.dart`
- Modify: `test/store/piano_roll_store_test.dart`

**Implementation contract:**

- Add a shared immutable composer state with:
  - `root`
  - `quality`
  - `durationTicks`
- Add provider actions to:
  - set root
  - set quality
  - set duration
  - add the current stack at `selectedColumnTick` or fallback anchor
- V1 stack selector and V2 dock must stop owning separate product logic for root/quality/duration.
- Keep `PianoRollState` focused on editor state. Do not move panel-only open/close UI into the canonical store.
- Add a simple capability provider or helper for platform gating if state-layer ownership is needed by multiple widgets.

**TDD checklist:**

- [ ] Write failing composer-store tests for default values and mutations.
- [ ] Write failing tests that prove add-stack uses `selectedColumnTick` when present.
- [ ] Write failing tests that prove add-stack falls back to the shared import anchor when no column is selected.
- [ ] Write failing tests that prove composer state is reusable across V1 and V2 widgets.
- [ ] Run targeted store tests and confirm failure.
- [ ] Implement the composer model/store and minimal editor-store changes.
- [ ] Rewire V1 stack selector and V2 mock composer controls to the shared provider.
- [ ] Re-run the targeted tests and confirm pass.

**Targeted test commands:**

- `flutter test test/store/piano_roll_composer_store_test.dart`
- `flutter test test/store/piano_roll_store_test.dart`

**Expected review focus:**

- widget-local product logic removed from V2 dock
- V1 and V2 render the same composer contract
- provider design stays small and immutable

**Suggested commit message:** `refactor: share piano roll composer state`

---

## Task 3: Piano Roll Snapshot Persistence

**Owner:** `save-system`

**Reviewers after implementation:** spec compliance reviewer, then `code-quality`

**Goal:** Make Piano Roll a first-class saved instrument without breaking the existing save browser contract or cross-instrument stack import flow.

**Files to read first:**

- `lib/models/save_system.dart`
- `lib/store/save_system_store.dart`
- `lib/features/fretboard/fretboard_save_panel.dart`
- `lib/features/piano/piano_save_panel.dart`
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
- `lib/store/piano_roll_store.dart`

**Files to create or modify:**

- Modify: `lib/models/save_system.dart`
- Modify: `lib/store/save_system_store.dart`
- Create: `lib/features/piano_roll/piano_roll_save_panel.dart`
- Modify: `lib/features/piano_roll/piano_roll_feature.dart`
- Modify: `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
- Create: `test/features/piano_roll/piano_roll_save_panel_test.dart`
- Modify: `test/store/piano_roll_store_test.dart`
- Create or modify: `test/store/save_system_store_test.dart`

**Implementation contract:**

- Add `PianoRollSnapshot extends InstrumentSnapshot`.
- Persist:
  - `config`
  - `notes`
  - `pitchRangeStart`
  - `pitchRangeEnd`
  - `selectedColumnTick`
  - `snapTicks`
  - `highlightedNotes`
- Do not persist:
  - `selectedNoteIds`
  - playback transport state
  - `latestImportedRange`
- Update `InstrumentSnapshot.fromJson(...)` to recognize the new subtype.
- Audit every `switch (snapshot)` or subtype check and make it exhaustive.
- Add a dedicated Piano Roll save/load panel. Do not overload the stack-import loader with full-roll loading responsibilities.
- Keep the stack-import loader filtered to Fretboard and Piano saves only.

**TDD checklist:**

- [ ] Write a failing round-trip serialization test for `PianoRollSnapshot`.
- [ ] Write a failing load-apply test proving a saved roll restores notes, timeline config, pitch window, snap value, and selected column.
- [ ] Write a failing widget test for the new Piano Roll save panel.
- [ ] Write a failing regression test proving the stack-import loader still ignores full Piano Roll snapshots.
- [ ] Run targeted tests and confirm failure.
- [ ] Implement the snapshot, store wiring, and panel.
- [ ] Re-run targeted tests and confirm pass.

**Targeted test commands:**

- `flutter test test/features/piano_roll/piano_roll_save_panel_test.dart`
- `flutter test test/store/save_system_store_test.dart`
- `flutter test test/store/piano_roll_store_test.dart`

**Expected review focus:**

- serialization completeness
- no broken exhaustive snapshot handling
- save panel owns full-roll persistence, loader remains cross-instrument stack import only

**Suggested commit message:** `feat: add piano roll save snapshots`

---

## Task 4: Grid Interaction, Web Support, And Landscape Foundation

**Owner:** `instrument-renderer`

**Reviewers after implementation:** spec compliance reviewer, then `accessibility-ux`, then `code-quality`

**Goal:** Preserve the current advanced grid behavior while making the editor feel native on web/desktop and usable in landscape.

**Files to read first:**

- `lib/features/piano_roll/piano_roll_grid.dart`
- `lib/main.dart`
- `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- `lib/features/piano_roll/piano_roll_toolbar.dart`
- `test/features/piano_roll/piano_roll_grid_test.dart`

**Files to create or modify:**

- Modify: `lib/features/piano_roll/piano_roll_grid.dart`
- Modify or create: `lib/features/piano_roll/piano_roll_screen_v2.dart`
- Modify: `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- Modify: `lib/main.dart`
- Modify: `test/features/piano_roll/piano_roll_grid_test.dart`
- Create or modify: `test/features/piano_roll/piano_roll_screen_v2_test.dart`

**Implementation contract:**

- Preserve existing gesture invariants:
  - raw `Listener`
  - pinch zoom
  - resize handle
  - long-press delete
  - playback auto-scroll
- Add:
  - ruler drag scrub for `selectedColumnTick`
  - double-tap empty-cell insertion using the current snap length
  - web/desktop keyboard shortcuts:
    - `Space`
    - `Delete` / `Backspace`
  - pointer-signal zoom helpers for desktop/web where appropriate
  - explicit web gating for Hum to MIDI
- Build a real landscape arrangement:
  - larger persistent grid area
  - side inspector or utility rail
  - no long portrait-only card stack in landscape
- If the grid file becomes unsafe to review, split it by responsibility.

**TDD checklist:**

- [ ] Write failing grid tests for ruler scrubbing.
- [ ] Write failing grid tests for double-tap empty-cell snap-length insertion.
- [ ] Write failing widget tests for keyboard shortcut delete/play behavior.
- [ ] Write failing widget tests proving hum controls are hidden or replaced on web.
- [ ] Write failing widget tests for landscape layout presence of both grid and utility surface.
- [ ] Run targeted widget tests and confirm failure.
- [ ] Implement the minimal interaction and adaptive-layout changes.
- [ ] Re-run targeted widget tests and confirm pass.

**Targeted test commands:**

- `flutter test test/features/piano_roll/piano_roll_grid_test.dart`
- `flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart`

**Accessibility review checklist:**

- verify touch target size for resize handle affordances and any new toolbar targets
- verify landscape focus order and semantics labels
- verify web-only keyboard shortcuts do not hide required tap alternatives

**Suggested commit message:** `feat: adapt piano roll editor for web and landscape`

---

## Task 5: Real V2 Shell Parity Wiring

**Owner:** `instrument-renderer`

**Reviewers after implementation:** spec compliance reviewer, then `accessibility-ux`, then `code-quality`

**Goal:** Replace the V2 mockup’s fake state with real provider-backed surfaces and cover every V1 capability inside the V2 shell.

**Files to read first:**

- `lib/features/piano_roll/piano_roll_screen_v2_mockup.dart`
- `lib/features/piano_roll/piano_roll_toolbar.dart`
- `lib/features/piano_roll/piano_roll_scale_picker.dart`
- `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- `lib/features/piano_roll/piano_roll_detection_panel.dart`
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart`
- `lib/features/piano_roll/piano_roll_save_panel.dart`
- `lib/main.dart`

**Files to create or modify:**

- Create or replace: `lib/features/piano_roll/piano_roll_screen_v2.dart`
- Modify: `lib/features/piano_roll/piano_roll_screen_v2_mockup.dart`
- Modify: `lib/main.dart`
- Modify: `lib/features/piano_roll/piano_roll_feature.dart`
- Modify: `test/features/piano_roll/piano_roll_playback_config_test.dart`
- Modify: `test/features/piano_roll/piano_roll_hum_recorder_test.dart`
- Create or modify: `test/features/piano_roll/piano_roll_screen_v2_test.dart`

**Implementation contract:**

- V2 must render all parity-critical surfaces:
  - playback
  - edit
  - pitch
  - scale
  - hum
  - stack composer
  - cross-instrument save import
  - piano-roll save/load
  - detection
  - selected-column status
- Transport strip must read the real playback provider, not local `_playing`.
- Composer dock must read the shared composer provider, not local `_root`, `_quality`, `_duration`.
- The header chip should reflect real harmonic or scale context instead of fake mock text.
- Keep V1 wired to the same shared providers and shared widgets wherever reasonable.
- The mockup launcher in `main.dart` should open the real V2 implementation.

**TDD checklist:**

- [ ] Write failing widget tests proving the V2 transport reacts to the real playback provider.
- [ ] Write failing widget tests proving the V2 composer dock mutates shared composer state and adds real stacks.
- [ ] Write failing widget tests proving the V2 shell exposes hum/import/detection/save surfaces.
- [ ] Write failing widget tests proving selected-column status remains visible after grid interaction.
- [ ] Run targeted widget tests and confirm failure.
- [ ] Implement the V2 screen and minimal V1 compatibility rewiring.
- [ ] Re-run targeted widget tests and confirm pass.

**Targeted test commands:**

- `flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart`
- `flutter test test/features/piano_roll/piano_roll_playback_config_test.dart`
- `flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart`

**Accessibility review checklist:**

- verify parity surfaces remain discoverable in V2
- verify any icon-only V2 controls have semantics or tooltips
- verify landscape utility rail remains readable and tappable

**Suggested commit message:** `feat: wire piano roll v2 to shared editor logic`

---

## Task 6: Documentation, Help Surface, And Full Verification

**Owner:** `state-architect` for docs/integration updates, then `code-quality` for final audit

**Reviewers after implementation:** spec compliance reviewer, then `accessibility-ux`, then `code-quality`

**Goal:** Bring the docs and help surfaces up to date and produce proof that the shipped behavior works across mobile and web constraints.

**Files to read first:**

- `docs/piano_roll.md`
- `lib/ui/core/app_info_panel.dart`
- the completed diffs from Tasks 1–5

**Files to modify:**

- `docs/piano_roll.md`
- `lib/ui/core/app_info_panel.dart`
- any affected tests that describe help text or labels

**Documentation contract:**

- Document the real V2 architecture and relationship to V1.
- Document `PianoRollSnapshot`.
- Document web support with explicit Hum-to-MIDI exclusion.
- Document landscape layout.
- Document new interactions:
  - ruler scrub
  - double-tap empty-cell snap insertion
  - keyboard shortcuts

**Verification checklist:**

- [ ] Run the targeted piano-roll test suite.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter build web --release`.
- [ ] If an iOS simulator is available, perform a manual smoke pass using `serve-sim`.

**Verification commands:**

- `flutter test test/store/piano_roll_store_test.dart`
- `flutter test test/store/piano_roll_composer_store_test.dart`
- `flutter test test/store/piano_roll_playback_store_test.dart`
- `flutter test test/store/hum_to_midi_store_test.dart`
- `flutter test test/schema/rules/piano_roll_import_rules_test.dart`
- `flutter test test/schema/rules/piano_roll_playback_rules_test.dart`
- `flutter test test/features/piano_roll/piano_roll_grid_test.dart`
- `flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart`
- `flutter test test/features/piano_roll/piano_roll_playback_config_test.dart`
- `flutter test test/features/piano_roll/piano_roll_save_panel_test.dart`
- `flutter test test/features/piano_roll/piano_roll_screen_v2_test.dart`
- `flutter analyze`
- `flutter build web --release`

**`serve-sim` smoke pass if simulator is available:**

- Start or attach to a booted iPhone simulator.
- Verify portrait:
  - add note
  - move note
  - resize note
  - play/stop
  - open save/import/detection surfaces
- Rotate to landscape and verify:
  - grid remains primary
  - utilities remain reachable
  - state survives rotation
- Verify Hum to MIDI only on mobile-capable build paths.

**Suggested commit message:** `docs: finalize piano roll v2 parity and daw guidance`

---

## Subagent Review Workflow

After each task:

1. Dispatch an implementer subagent with the full task text and relevant file paths.
2. Run a spec-compliance review against this plan and the design spec.
3. Run a code-quality review.
4. For Tasks 4–6, also run an accessibility-ux review.
5. Do not advance until open review findings are fixed and re-reviewed.

Use the repo’s specialist prompts:

- `music-theory` for Task 1
- `state-architect` for Tasks 2 and 6 integration ownership
- `save-system` for Task 3
- `instrument-renderer` for Tasks 4 and 5
- `accessibility-ux` for review-only passes
- `code-quality` for review-only passes

---

## Completion Criteria

- V2 exposes every currently shipped V1 Piano Roll capability.
- V1 and V2 share provider-backed logic for composer and editor behavior.
- Piano Roll has first-class save/load through `PianoRollSnapshot`.
- Cross-instrument stack import from Fretboard and Piano still works.
- Shared theory/import duplication is removed from Piano Roll widgets.
- Web builds cleanly with Hum to MIDI safely gated out.
- Landscape mode is usable and verified.
- Docs and help text are updated.
- Targeted tests pass.
- `flutter analyze` passes.
- `flutter build web --release` passes.
- Manual simulator smoke test is attempted and reported when environment allows.
