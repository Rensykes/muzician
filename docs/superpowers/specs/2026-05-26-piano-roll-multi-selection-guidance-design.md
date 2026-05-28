# Piano Roll Multi-Selection And Interaction Guidance Design

Date: 2026-05-26
Status: Draft written from repo audit and simulator review
Scope: Piano Roll V2 note multi-selection management and in-product interaction guidance

## Goal

Make note multi-selection in Piano Roll V2 explicit, manageable, and teachable
without changing the core raw-pointer grid architecture.

The result should let users:

- understand the difference between selected column and selected notes
- build or clear a multi-selection without relying on hidden behavior alone
- apply group actions intentionally
- discover the existing gesture vocabulary from inside the Roll surface

## Current State Audit

The current implementation already contains the foundations for multi-selection,
but they are not surfaced as a first-class user flow.

### What already exists

- `PianoRollState.selectedNoteIds` is already canonical state for note selection.
- Double-tap on an existing note toggles it into or out of the selection.
- Dragging a selected note moves the whole selected group when more than one
  note is selected.
- `Delete` and `Backspace` already delete the current selection on desktop/web.

### What is missing

1. **Explicit selection management actions**
   - There is no store-level `clearSelection()` or `deleteSelectedNotes()`.
   - The only visible control for multi-selection is a small overlay pill inside
     the grid when `selectedNoteIds.length > 1`.

2. **A discoverable way to select a group at the current column**
   - Users can scrub to a chord column, but there is no explicit "select all
     notes at this column" action.
   - This makes group editing of stacked notes much harder than it needs to be.

3. **Confusing status language**
   - The current status widgets prioritize selected-column information, not note
     selection information.
   - In practice this hides the fact that a note selection is active and ready
     for group actions.

4. **No Roll-local access to help**
   - The shared `showAppInfoPanel(..., initialTab: 2)` already documents many
     piano-roll gestures, but Piano Roll V2 does not expose a direct help entry
     point in its own shell.

5. **Help copy documents hidden gestures but not the mental model**
   - The existing help text says double-tap toggles multi-select, but it does
     not clearly explain:
     - selected column vs selected notes
     - how group drag works
     - how to clear a selection
     - how to select all notes at the current column

### Simulator observations

An iPhone 17 Pro simulator review on 2026-05-26 confirmed the code audit:

- portrait mode shows the grid and action bar, but no Roll-local help action
- the action bar status emphasizes column state, not note selection state
- landscape mode provides more room, but still does not expose selection
  guidance as part of the inspector flow

## Brainstormed Approaches

### Option 1: Documentation-only fix

Add a help entry point and update the copy in `AppInfoPanel`, but do not change
selection actions or status components.

Pros:

- very small diff
- low regression risk

Cons:

- users still need to discover multi-selection through double-tap
- no explicit batch-selection or batch-action affordances

### Option 2: Small product-surface upgrade on top of existing selection state

Keep the current gesture engine, but add explicit selection actions, clearer
status, and Roll-local help.

Pros:

- smallest change that materially improves usability
- preserves `Listener`-based grid interaction
- no new long-lived state model required

Cons:

- does not add marquee/lasso selection
- still relies on double-tap for additive note-by-note selection

### Option 3: Full DAW-style selection rework

Add selection mode, lasso/marquee, modifier-key behavior, and a dedicated
selection toolbar.

Pros:

- richest long-term editing model

Cons:

- too large for the current request
- high gesture-regression risk in `PianoRollGrid`
- unnecessary before validating the simpler explicit-action layer

### Recommendation

Choose **Option 2**.

The repo already has working selection state and group drag. The missing value
is not a brand-new selection engine; it is explicit management and guidance.

## Locked Decisions

- `selectedColumnTick` and `selectedNoteIds` remain separate concepts.
- The raw `Listener` grid architecture stays in place.
- Double-tap note toggle remains supported; it is clarified, not removed.
- This scope adds explicit selection actions, not marquee/lasso selection.
- No new persistent preferences are introduced for guide visibility.
- The Roll help entry point reuses the existing shared app info sheet instead
  of introducing a second overlapping documentation system.

## Product Design

### 1. Selection Model

### Column selection

Column selection remains timeline-oriented and drives:

- harmonic detection
- add-stack anchor
- playback start point
- selected-column highlight

### Note selection

Note selection remains note-oriented and drives:

- group drag
- batch delete
- selection summary UI

### New explicit actions

The product should expose these selection actions explicitly:

- `clearSelection`
- `deleteSelectedNotes`
- `selectNotesAtTick`

`selectNotesAtTick` should convert the notes active at the current column into
the current note selection. This gives users a practical, explicit way to work
with chord stacks and other vertical groups.

### 2. Portrait UI

Portrait should stay compact and preserve the current fixed-height action bar,
but selection state should become more legible.

### App bar actions

Add a help action next to settings in `PianoRollScreenV2`:

- Help icon opens `showAppInfoPanel(context, initialTab: 2)`
- Settings icon continues to open the existing Roll settings sheet

### Status row behavior

The first row of `_PortraitActionBar` should prioritize note selection when it
exists:

- when `selectedNoteIds.isNotEmpty`: show `N selected`
- otherwise: show the existing column status summary

### Selection actions

When a column is selected and contains notes, expose a compact action to select
all notes at that column.

When a note selection exists, expose compact actions to:

- clear the selection
- delete the selection
- open guidance

These actions can live in the action bar and/or the existing grid overlay, but
they should be explicit and reachable without a hidden gesture.

### 3. Landscape UI

Landscape already has a dedicated utility rail, so it should surface the same
selection actions without introducing another modal layer.

The `Selection` section should show:

- current column summary
- selected note count when present
- `Select column notes`
- `Clear selection`
- `Delete selection`
- `Guide`

This keeps wide layouts dense without hiding key edit actions.

### 4. Guidance Surface

The guidance system has two layers:

### Primary guidance surface

Reuse `showAppInfoPanel(context, initialTab: 2)` as the canonical help sheet.

The Piano Roll tab should gain a clearer subsection covering:

- selected column vs selected notes
- tap note to solo-select
- double-tap note to add/remove from selection
- drag one selected note to move the entire group
- delete selected notes with UI action or keyboard shortcut
- select all notes at the current column for stack edits

### Inline guidance

Selection-related UI should include short operational copy near the actions,
for example:

- `2 selected`
- `Select column notes`
- `Clear`
- `Delete`

This avoids forcing users to open the full guide for basic next-step decisions.

### 5. Accessibility And Feedback

- Every new icon-only action should have clear semantics/tooltip text.
- Selection actions should remain at least 44x44 logical pixels where possible.
- Use differentiated haptics:
  - `selectionClick` for lightweight selection changes
  - `mediumImpact` for destructive group actions like delete-selection
- Help copy should avoid assuming desktop-only input.

## Architecture

### Store Changes

Keep `PianoRollState` unchanged. Add focused methods to
`PianoRollNotifier` instead of new model fields:

- `clearSelection()`
- `deleteSelectedNotes()`
- `selectNotesAtTick(int tick)`

This keeps the change UI-agnostic and reusable across portrait, landscape, and
grid surfaces.

### Widget Changes

### `lib/features/piano_roll/piano_roll_grid.dart`

- replace direct loop-based delete shortcut logic with
  `notifier.deleteSelectedNotes()`
- replace the existing multi-select pill with a clearer action cluster or keep
  the pill but back it with the new store APIs

### `lib/features/piano_roll/piano_roll_screen_v2.dart`

- add Roll-local help entry point
- update selection status presentation
- add explicit selection actions in portrait and landscape

### `lib/ui/core/app_info_panel.dart`

- enrich the Piano Roll tab with a selection-management subsection
- clarify the difference between note selection and column selection

## Testing Strategy

### Store tests

Add or update `test/store/piano_roll_store_test.dart` for:

- `clearSelection()`
- `deleteSelectedNotes()`
- `selectNotesAtTick(...)`

### Grid tests

Add or update `test/features/piano_roll/piano_roll_grid_test.dart` for:

- double-tap existing note adds/removes it from selection
- group drag still moves all selected notes
- delete shortcut routes through the store-level batch delete

### Screen tests

Add or update `test/features/piano_roll/piano_roll_screen_v2_test.dart` for:

- help action presence in portrait
- selection summary changes when note selection exists
- selection actions appear in landscape rail

### Manual verification

Verify on:

- one compact portrait simulator/device
- one wide/landscape viewport

Recommended manual checks:

- select one note, then build a multi-selection
- select notes at current column
- drag the selected group
- clear the selection
- delete the selection
- open the Roll help sheet from both portrait and landscape

## Non-Goals

This design intentionally does not include:

- marquee/lasso selection
- modifier-key selection models
- duplicate-selection commands
- undo/redo
- persistence of help-dismissal state

## Assumption

This plan assumes "gestire le selezioni multiple" means making multi-selection
practical and explicit for note editing, not introducing a DAW-grade lasso or
desktop modifier system in this iteration.
