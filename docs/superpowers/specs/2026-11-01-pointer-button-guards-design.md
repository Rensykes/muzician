# Pointer Button Guards for Canvas Gestures — Design

## Problem

Three canvases drive gestures from a raw `Listener` instead of the gesture
arena, and none of them check which mouse button started the event:

- `lib/features/piano_roll/piano_roll_grid.dart:1426` — `_onPointerDown`
  (`:810`) starts marquee select, paint brush, delete brush, note move or note
  resize for **any** button. There is no `onPointerCancel`, and `_pointers`
  is only cleaned up in `_onPointerUp` (`:1034`).
- `lib/features/fretboard/fretboard.dart:225` — `onPointerDown` records
  `_pointerDownLocal` for any button, so a right-click plays/selects a note.
  `onPointerCancel` already resets the down position (`:247`).
- `lib/features/songwriter/songwriter_melody_timeline.dart:500` — `_start`
  (`:76`) begins a block drag for any button. `onPointerCancel` already
  exists (`:506`).

On web, a right-click in the Piano Roll therefore starts a gesture *and*
opens the browser context menu. The menu steals the pointer stream, so
`PointerUp` never arrives: `_dragMode` stays armed, `_marqueeRect` keeps
painting, brushes stay active, and the stale `_pointers` entry makes the next
touch look like a second finger (spurious pinch/zoom).

## Goals

1. Secondary/tertiary mouse buttons never start or drive a canvas gesture in
   Piano Roll, Fretboard, or the Writer melody timeline.
2. An interrupted pointer (browser menu, app switch, touch cancel) fully
   clears Piano Roll gesture state, so no marquee, brush, or drag stays armed.
3. Regression tests cover both behaviours.

## Non-goals

- Not suppressing the browser context menu. Right-click on web still opens the
  browser's own menu; the app simply ignores the event. Option A/C from the
  discussion stays available as a separate one-line change if wanted later.
- No change to text-field Copy/Paste context menus on desktop or web.
- No change to wheel zoom/scroll, pinch zoom, long-press, tool semantics, or
  the shared gesture arena widgets (`GestureDetector` already ignores
  non-primary buttons).

## Approaches Considered

- **A. Web-only `BrowserContextMenu.disableContextMenu()`** — rejected: stops
  the menu but the drag still starts from the right button, and it removes
  Copy/Paste menus from every web text field.
- **B. Button guards plus cancel handling** — chosen: fixes the cause on all
  platforms and also covers cancelled pointers.
- **C. B + A** — deferred. Can be added later without reworking B.

## Design

### Shared guard

Add `lib/utils/pointer_buttons.dart`:

```dart
bool isPrimaryPointerButton(PointerEvent event) =>
    event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;
```

`buttons == 0` is treated as primary so touch and stylus input, which may not
report a button mask, keep working. Mouse middle/right/back/forward buttons
return false. One helper keeps the three call sites consistent and testable.

### Piano Roll (`piano_roll_grid.dart`)

- `_onPointerDown`: return early when `isPrimaryPointerButton` is false, before
  touching `_pointers`, timers, or drag state.
- `_onPointerMove`: return early when the pointer is not tracked in
  `_pointers`, and when its `buttons` are non-zero without the primary button.
  This prevents a secondary button pressed mid-drag from continuing a move.
- `_onPointerUp`: return early when the pointer is not tracked in `_pointers`,
  so a right-button release cannot fall through to the tap branch and select or
  preview a note.
- New `_onPointerCancel`: remove the pointer from `_pointers`, cancel the
  long-press timer, and reset `_dragMode`, `_dragNoteId`, `_marqueeStart`,
  `_marqueeCurrent`, `_marqueeRect`, `_marqueePreviewIds`, `_paintBrushedCells`,
  `_deleteBrushedNoteIds`, multi-drag originals, `_pinching`, `_movedBeyondSlop`,
  `_longPressConsumed`, and `_totalPointerDelta`. Marquee/brush visuals are
  cleared inside `setState`; no further manual scrolling can happen, since
  scrolling is move-event driven and the pointer and drag state have been
  cleared above.
- Note edits already applied before the cancel stay at their last position (no
  revert). A lost pointer should not silently undo a deliberate drag, and the
  right-click case has no moves to undo.
- Wire `onPointerCancel: (e) => _onPointerCancel(e)` on the grid `Listener`.

### Fretboard (`fretboard.dart`)

- Ignore `onPointerDown` when `isPrimaryPointerButton` is false, so
  `_pointerDownLocal` is never armed by a right-click. Existing
  `onPointerCancel` reset stays as is.

### Writer melody timeline (`songwriter_melody_timeline.dart`)

- Return early from `_start` when `isPrimaryPointerButton` is false. Existing
  cancel handling stays as is.

## Verification

- `test/features/piano_roll/piano_roll_grid_test.dart`: secondary-button down
  selects nothing and starts no marquee; secondary down with the paint tool
  adds no note; a cancelled primary drag leaves no marquee preview and a later
  primary drag still works.
- `test/features/fretboard/`: secondary-button down leaves the selection
  unchanged.
- `test/features/songwriter/`: secondary-button down starts no block drag.
- `dart format`, `flutter analyze`, and the three narrow test files.
- Manual web check (`flutter run -d chrome`): right-click with select, paint,
  delete, and scissors tools, then confirm the tools still work and nothing is
  left armed.

## Docs

`docs/piano_roll.md` notes that non-primary mouse buttons are ignored on web
and desktop; `docs/fretboard.md` and `docs/songwriter.md` get a matching line.
