# Interactive Coach-Mark Guide — Design

**Date:** 2026-06-13
**Branch:** `feature/song-writer-complete` (continuation)
**Goal:** An in-app, step-through coach-mark tour for the Song and Writer pages —
a spotlight overlay that highlights real UI elements one at a time with a tooltip,
launched from a `?` button in each header.

---

## Context

- The app's only existing guidance is `lib/ui/core/app_info_panel.dart` — a static
  tabbed reference sheet (Fretboard / Piano / Piano Roll), no Song/Writer tabs, not
  interactive.
- No coach-mark / showcase package is in `pubspec.yaml`. The app already uses
  `OverlayEntry` (e.g. `lib/features/songwriter/songwriter_undo.dart`), so the
  overlay engine is hand-rolled — no new dependency.
- Theme tokens live in `lib/theme/muzician_theme.dart` (`glassBg`, `glassBorder`,
  `surface`, `sky`, `textPrimary`, `textSecondary`, `textMuted`).
- Decided: **help-button-only** launch (no auto-run, no persisted "seen" flag).

## Non-goals

- No auto-trigger on first visit, no persistence.
- No scripted "sandbox" that builds a demo project.
- No changes to the existing `app_info_panel` instrument tabs.

---

## 1. Overlay engine — `lib/ui/core/coach_overlay.dart`

A reusable, page-agnostic coach-mark engine.

### Data model

```dart
/// One step of a coach tour: highlights [key]'s widget with a [title]/[body]
/// tooltip. A step whose key is not currently mounted is skipped.
class CoachStep {
  const CoachStep({required this.key, required this.title, required this.body});
  final GlobalKey key;
  final String title;
  final String body;
}
```

### Entry point

```dart
/// Starts a coach tour over the current screen. No-op if [steps] is empty or
/// none of the step keys are mounted.
void startCoachTour(BuildContext context, List<CoachStep> steps);
```

- Inserts a single `OverlayEntry` into the root `Overlay`.
- Internally tracks the current step index. "Next"/"Back" move through the
  **mountable** steps (a step whose `key.currentContext == null` at advance-time
  is skipped). "Skip"/"Done" remove the entry.
- If, when resolving the current step, no remaining step is mountable, the tour
  ends.

### Rendering

The overlay stacks two layers inside the entry's builder:

1. **Scrim + spotlight** — a `CustomPaint` filling the screen. It paints a
   translucent black scrim (`Colors.black54`) with the target rect punched out
   (rounded-rect, ~8 px padding, ~12 px radius) using
   `Path.combine(PathOperation.difference, …)`. A tap on the scrim advances to
   the next step (mirrors "Next"); a small "Skip tour" affordance remains on the
   card. The cutout itself ignores pointers so the highlighted control is
   visually framed but not accidentally triggered (the scrim captures taps).

2. **Tooltip card** — a glass card (`glassBg` + `glassBorder`, radius 14)
   positioned just below the target rect, or above it when the target sits in the
   lower third of the screen. Contents:
   - title (`textPrimary`, w700),
   - body (`textSecondary`),
   - a row of step dots (filled = current),
   - `Back` (hidden on first step), `Skip` (text), `Next` / `Done` (filled).

   The card is horizontally clamped to stay within 12 px of the screen edges and
   capped at ~320 px wide.

### Target geometry

```dart
Rect? _targetRect(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return null;
  final offset = box.localToGlobal(Offset.zero);
  return offset & box.size;
}
```

### Orientation / layout changes

The entry rebuilds against live rects via a `LayoutBuilder` + an
`OrientationBuilder`-style check. To keep it simple and robust: the overlay reads
`MediaQuery.size` on each build; if the size changed since the tour started, the
tour dismisses itself (the user re-opens from `?`). This avoids stale rects on
rotation without a recompute dance.

### Lifecycle / safety

- `startCoachTour` is a no-op when `steps` is empty or every key is unmounted.
- The entry removes itself on Done/Skip and on size-change dismissal.
- Uses a post-frame callback before the first paint so freshly built target keys
  have a `RenderBox`.

---

## 2. Step scripts

### Song — `lib/features/song/song_coach_steps.dart`

```dart
List<CoachStep> songCoachSteps(SongCoachKeys k);
```

A `SongCoachKeys` struct carries the `GlobalKey`s the screen owns. Steps (each
skipped if its key is absent):

1. **Transport** — "Play, loop, and practice tempo. Loop region, ½×/¾× practice
   speed, metronome, count-in, and snap all live here."
2. **Ruler** — "Tap to move the playhead. Long-press-drag to set a loop region.
   Double-tap to drop a section marker."
3. **Add Track** — "Add note, drum, or audio tracks."
4. **First track header** (or, if no tracks, the empty-state hint) — "Mute, solo,
   and the ⋯ menu (volume, reorder, rename)."
5. **Timeline lane** — "Long-press a lane to add a clip; tap a clip to select it
   and open the action bar (split, transpose, trim, duplicate, move)."
6. **Overflow ⋮** — "New song, Import from Writer, and Export WAV."

### Writer — `lib/features/songwriter/songwriter_coach_steps.dart`

```dart
List<CoachStep> writerCoachSteps(WriterCoachKeys k);
```

1. **Config strip** — "Set the key and tempo, play the arrangement, toggle the
   metronome."
2. **A bar cell** (or the empty hint) — "Tap a bar to drop a chord from the
   wheel."
3. **Section heading** — "The ⋯ menu adds drum lanes and sets repeats."
4. **Add section** — "Build the song's structure section by section."
5. **Overflow ⋮** — "Save / load and edit the song structure."

Steps whose target may be conditional (a placed clip, a section) fall back to an
always-present anchor (the lane region / the empty-state hint / the add button).

---

## 3. Launch buttons + keys

- **Song** (`lib/features/song/song_screen.dart`): the screen becomes/stays a
  `ConsumerStatefulWidget` (already is) and owns the `GlobalKey`s. A `?`
  `IconButton` is added to the header (full layout) and to the trailing icons in
  compact/landscape mode, calling
  `startCoachTour(context, songCoachSteps(keys))`. Keys are attached to: the
  `_SongTransportStrip`, the measure ruler, the Add-Track button, the overflow
  menu button, the first track row / empty hint, and the timeline body.
- **Writer** (`lib/features/songwriter/songwriter_header.dart` +
  `songwriter_screen_sheet.dart`): a `?` `IconBtn` next to the existing overflow
  button. Because the targets (config strip, bar cells, add-section) live in the
  sheet, the keys are created in `SongwriterScreenSheet` and threaded to the
  header via a callback, or the header exposes an `onStartTour` callback the
  sheet wires up. The sheet owns the keys; the header just triggers.

The exact key-ownership wiring is a plan detail; the contract is: **the widget
that builds the target attaches the key; the header only calls
`startCoachTour`.**

---

## 4. Testing

- **Engine widget test** (`test/ui/coach_overlay_test.dart`): pump a scaffold
  with two keyed boxes; `startCoachTour` with 2 steps; assert step-1 title shown;
  tap `Next`; assert step-2 title; tap `Skip`/`Done`; assert overlay gone. A
  third case: a step with an unmounted key is skipped (no crash, lands on the
  next mountable step).
- **Song launch test**: pump `SongScreen`, tap the `?` button, assert the first
  coach title appears. (Writer analogous if cheap; otherwise covered by the
  engine + manual sim.)
- `flutter analyze` clean; full `flutter test` green.
- Simulator: run both tours in portrait and landscape; confirm spotlight tracks
  the right elements and the card stays on-screen.

---

## Out of scope / follow-up

- Auto-run on first visit + "seen" persistence (deferred by decision).
- Coach tours for Fretboard / Piano / Roll.
- Animated GIF demos inside steps.
