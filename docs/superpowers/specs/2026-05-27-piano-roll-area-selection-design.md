# Piano Roll Area Selection Design

Date: 2026-05-27
Status: Draft written from approved brainstorming decisions
Scope: Piano Roll multi-note area selection redesign

## Goal

Replace the current Piano Roll multi-selection workflow with a mobile-first,
spatial selection model that can quickly capture:

- note groups that are not vertically aligned on one column
- melodic sequences spread across time
- mixed patterns that need later move, resize, split, or delete operations

The new interaction must work on both mobile and desktop, with primary UX focus
on mobile.

## Problem Statement

The current Piano Roll multi-selection flow is too narrow for real editing:

- double-tap on a note can add or remove one note from the current selection
- the explicit `Multi-select` action selects notes only at the current column

This is useful for local refinement, but not for quickly selecting a phrase,
motif, diagonal pattern, or arbitrary group of notes on the grid.

The missing capability is an explicit area-selection workflow.

## Non-Goals

- no freeform lasso selection in this step
- no additive or subtractive marquee variants in this step
- no automatic gesture overloading on the existing `Draw` tool
- no changes to ruler semantics for `selectedColumnTick`
- no redesign of note move/resize/split behavior after selection is built

## Current State Audit

Today the Piano Roll supports multi-selection in two ways:

1. hidden gesture:
   - double-tap on an existing note to add/remove it from selection
2. explicit but limited action:
   - `selectNotesAtTick(tick)` selects all notes active at one column

This creates three product issues:

- selection is discoverable only in part
- explicit selection is column-bound instead of area-bound
- mobile users do not have a fast way to select a phrase before editing it

The existing selection state itself is fine:

- `selectedNoteIds` already represents arbitrary note groups
- move, batch resize, split-selected, and delete-selected already operate on
  groups

So the missing piece is not the downstream editing pipeline. The missing piece
is how users build the selection.

## Locked Product Decisions

- The new workflow is based on a dedicated `Select` mode.
- `Select` must work on both mobile and desktop.
- `Select` is explicit, not hidden behind a drag gesture on the normal grid.
- In `Select`, dragging on the grid draws a rectangular selection box.
- The box selects notes that it intersects even partially.
- A new box always replaces the current selection.
- Double-tap on a note remains available to refine selection after the box.
- The current column-based `Multi-select` action may remain as a secondary
  shortcut, but not as the primary multi-selection workflow.
- `selectedColumnTick` and note selection remain separate concepts.

## Recommended Approach

Introduce a new explicit Piano Roll tool named `Select`, implemented as a
marquee-selection mode with rectangular hit testing and live preview.

### Why this approach

- easiest model to understand on mobile
- predictable on desktop with mouse and trackpad
- avoids conflict with existing `Draw` drag-to-move and drag-to-scroll flows
- reuses the already-correct downstream selection/editing state
- keeps the approved double-tap refinement path

## Design

## 1. Interaction Model

### Primary flow

Users build selection in two steps:

1. switch to `Select`
2. drag a rectangle around the target notes

After the group is selected, users switch back to:

- `Draw` to move or resize
- `Scissors` to split
- existing delete actions to remove the group

### Selection semantics

- every new marquee replaces the current selection
- partial intersection counts as selected
- empty marquee result clears selection
- double-tap on a note can still add/remove individual notes from the current
  selection

This gives a simple mental model:

- `Select` builds the group
- other tools edit the group

## 2. Tool Semantics Across Modes

### Draw

`Draw` stays editing-first:

- tap empty cell: add note
- tap note: solo-select
- double-tap note: add/remove from selection
- drag selected note: move group
- drag note edge: resize group
- drag empty area: scroll

### Select

`Select` becomes selection-first:

- tap note: solo-select that note
- double-tap note: add/remove from selection
- one-finger drag anywhere on grid: draw marquee box
- releasing the drag: replace selection with intersected notes
- no move behavior
- no resize behavior
- no one-finger scroll behavior

### Scissors

`Scissors` remains unchanged in principle:

- tap selected note: split whole selection at the tapped tick
- tap unselected note: split just that note

### Ruler

Ruler interactions remain independent:

- tap ruler: set `selectedColumnTick`
- drag ruler: scrub `selectedColumnTick`

Area selection must not redefine the ruler or fuse note selection with column
selection.

## 3. Mobile-First Gesture Rules

The critical conflict on mobile is drag ownership.

To avoid ambiguity:

- one-finger drag in `Select` belongs to marquee selection
- two-finger pinch remains zoom
- two-finger pan is used for grid navigation while `Select` is active

This keeps `Select` clean on mobile:

- one finger selects
- two fingers navigate/zoom

Desktop keeps the same logical model:

- mouse drag in `Select` draws the marquee
- wheel / modifiers continue to support zoom as they already do
- trackpad users still have explicit mode separation instead of hidden gesture
  overloading

## 4. Visual Feedback

### While dragging

The grid shows:

- a rectangular marquee overlay
- a light translucent fill
- a high-contrast border
- live highlight on notes currently intersected by the marquee

### After release

- selected notes keep the existing selected-note styling
- marquee overlay disappears
- if nothing was intersected, no notes remain selected

### Tool visibility

When `Select` is active:

- the tool segment clearly shows `Select` as active
- a short contextual hint may appear, such as `Drag to select notes`

The goal is to make selection feel intentional, not hidden.

## 5. Shell Changes

### Tool segment

Add `Select` to the Piano Roll tool segment alongside the existing tools.

Recommended ordering:

- `Draw`
- `Select`
- `Scissors`
- existing secondary tools if still retained

### Existing selection action

The current column-scoped `Multi-select` action is not removed immediately, but
is reframed as a shortcut:

- useful when the user wants the current vertical slice
- not the main answer to multi-selection anymore

### Existing actions that stay valuable

- `Clear`
- `Delete`
- selection status summary

These become more useful once users can capture larger note groups.

## 6. Architecture

### Persistent state

No new persistent selection model is required.

The source of truth remains:

- `PianoRollState.selectedNoteIds`

### Ephemeral interaction state

Marquee drag state should remain local to the grid widget layer because it is
purely transient interaction UI:

- drag start point
- current drag point
- active marquee rectangle
- live intersected note ids during drag

Only the final selected ids are committed to the store when the drag ends, or
on pointer-up. During drag, the grid may preview the candidate selection
locally, but store-level selection changes should stay final and deliberate.

### Store additions

The store likely only needs small selection helpers, for example:

- `setSelection(Set<String> ids)` reuse
- optional helper for clearing selection on empty marquee result

The main logic belongs in grid hit testing and rectangle-note intersection, not
in global app state.

## 7. Hit Testing Rules

The marquee must operate on note rectangles in grid space.

A note is selected if:

- the marquee rectangle overlaps the rendered note rectangle at all

Not required in this step:

- containment-only selection
- fuzzy proximity halos
- lasso polygon intersection

This keeps the selection rule explicit and easy to test.

## 8. Documentation And Help

Update:

- `docs/piano_roll.md`
- Piano Roll tab inside `lib/ui/core/app_info_panel.dart`

The docs must teach the new primary workflow clearly:

1. switch to `Select`
2. drag a box around notes
3. switch to `Draw` to move/resize
4. switch to `Scissors` to split
5. use double-tap to refine individual notes

The previous “Multi-select at column” wording must be demoted so it is no
longer interpreted as the main multi-selection feature.

## 9. Testing

Minimum expected coverage:

- grid/widget tests for marquee drag selection
- intersection behavior test: partially touched notes are selected
- empty marquee result clears selection
- selection replacement test: second marquee replaces first selection
- mode separation tests:
  - `Draw` drag still scrolls/moves instead of marquee-selecting
  - `Select` drag does not move notes
- persistence test:
  - selection built in `Select` is still editable in `Draw`
- shell test for `Select` tool visibility
- help/docs updates validated against the new behavior

## 10. Risks And Boundaries

### Main risk

The grid already multiplexes many pointer behaviors:

- tap
- double-tap
- long press
- move
- resize
- paint/delete brush
- pinch zoom
- ruler scrub

Adding marquee logic inside that surface can regress other interactions if the
mode boundaries are not strict.

### Risk mitigation

- keep marquee available only in explicit `Select`
- do not overload `Draw`
- keep ephemeral drag-box state local
- verify at least one compact mobile viewport and one wide layout

## Design Summary

The Piano Roll multi-selection redesign is a focused shift from column-based and
gesture-hidden selection toward an explicit spatial workflow:

- add an explicit `Select` tool
- use a rectangular marquee
- select notes on partial overlap
- replace selection on every new marquee
- preserve double-tap refinement
- keep downstream group editing behavior unchanged

This delivers the missing ability to quickly capture note groups and phrases,
especially on mobile, without destabilizing the rest of the Piano Roll editing
model.
