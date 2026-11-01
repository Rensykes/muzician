# Piano Roll Select-Tap Design

## Problem

In `lib/features/piano_roll/piano_roll_grid.dart`, the Select tool claims every
primary press before hit-testing (`_onPointerDown`, `:816`) and commits the
marquee preview unconditionally on release (`_onPointerUp`, `:1042`). The
preview is only filled by `_onPointerMove`, so a stationary tap commits an empty
set:

- Clicking a note in Select does **not** select it; it clears the current
  selection, so a following Delete removes nothing.
- Double-tap refinement is unreachable, although `docs/piano_roll.md:30` and the
  tool matrix (`:414`) promise it in Select.
- Note audition and `selectColumn` are unreachable in Select, contradicting
  `docs/piano_roll.md:402`.
- Behaviour is identical for touch and left-click, and predates the pointer
  button guards.

## Goals

1. A stationary tap on a note in Select solo-selects it, auditions it, and
   updates the selected column — the same tap semantics Draw already has.
2. Double-tapping a note in Select adds or removes it from the pre-tap
   selection.
3. A stationary tap on empty space still clears the selection.
4. Dragging in Select still marquees, and releasing after movement still commits
   the intersected notes.
5. `docs/piano_roll.md` and `AGENTS.md` describe the shipped behaviour.

## Non-goals

- No modifier-key selection (shift/ctrl-click).
- No change to Draw, Scissors, Paint, Delete, pinch, scroll or long-press.
- No change to marquee commit rules after movement.

## Approaches Considered

- **A. Gate the commit on movement and reuse the tap path** — chosen. The
  marquee branch commits only when `_movedBeyondSlop`; otherwise a note hit at
  the release point runs the shared note-tap logic. Smallest change, reuses the
  existing double-tap state machine (`_lastTapTime`, `_preTapSelection`).
- **B. A second tap recognizer for Select** — rejected: the grid deliberately
  bypasses the gesture arena, and mixing in a `TapGestureRecognizer` would
  reintroduce arena conflicts with the raw pointer stream.
- **C. Treat every Select press as a tap, then start the marquee on move** —
  rejected: it would audition and select on every marquee start.

## Design

Extract the note-tap body of the existing tap branch into a private method:

```dart
void _handleNoteTap(PianoRollNote hit, PianoRollState state)
```

It keeps today's behaviour verbatim: audition via `NotePlayer.previewTimbre`,
the 300 ms double-tap check against `_lastTapNoteId`/`_lastTapTime`, the
`_preTapSelection` toggle, `selectNote` for a single tap (deselecting when the
note is already the only selection), `selectColumn(hit.startTick)`, and the
haptics. The Scissors split branch stays in `_onPointerUp` untouched.

In `_onPointerUp`'s marquee branch, before committing:

- If `_movedBeyondSlop` is false, hit-test the release point. On a hit, call
  `_handleNoteTap(hit, state)` and clear the marquee state without calling
  `setSelection`. On a miss, keep today's behaviour: commit the (empty) preview,
  which clears the selection.
- If `_movedBeyondSlop` is true, commit the preview exactly as today.

The marquee state reset (`_marqueeStart`, `_marqueeCurrent`, `_marqueeRect`,
`_marqueePreviewIds`, `_dragMode`, `_movedBeyondSlop`, `_totalPointerDelta`)
runs on both paths.

## Behaviour Table

| Gesture in Select | Before | After |
|---|---|---|
| Tap a note | Selection cleared | Note solo-selected, auditioned, column updated |
| Double-tap a note | Selection cleared | Note toggled in/out of the pre-tap selection |
| Tap empty space | Selection cleared | Selection cleared (unchanged) |
| Drag over notes | Marquee commit | Marquee commit (unchanged) |
| Drag starting on a note | Marquee commit | Marquee commit (unchanged) |

## Verification

New tests in `test/features/piano_roll/piano_roll_grid_test.dart`:

- Tap a note in Select solo-selects it and sets `selectedColumnTick` to its
  start tick.
- Tap note A, then double-tap note B, leaves both selected.
- With a note already selected, a tap on empty space clears the selection.

The whole file must stay green, which covers the existing marquee, pinch, paint,
delete, scissors and keyboard suites.

## Docs

- `docs/piano_roll.md`: Select tool matrix row gains solo-select on tap; the
  `onPointerUp` implementation row notes the stationary-tap path.
- `AGENTS.md`: record the raw-`Listener` input rule (primary-button guard plus
  `onPointerCancel` reset) and the Select tap-vs-marquee rule as persistent
  repository guidance.
