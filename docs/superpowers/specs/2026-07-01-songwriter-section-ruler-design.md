# Songwriter — per-section ruler with a parked start playhead

**Status:** design
**Date:** 2026-07-01
**Branch:** feature/songwriter-audio-daw

## Problem

Playback can only start mid-song via the chord-bar menu's "Play from here". In a
section with no chord lane (only audio/drum lanes) there is no bar to tap, and
there is no visible, lane-independent way to set/see where playback will start.
We want a ruler strip per section with a draggable playhead: tap/drag to park the
start position, and the header Play button resumes from there.

## Decisions (from brainstorming)

- **Scope:** one ruler per section card (fits the stacked-section layout).
- **Interaction:** park-then-play — tap/drag the ruler to set a start playhead at
  a bar; the header Play button starts from it (top of song if unset). The
  playhead also tracks the live position during playback.
- **Keep** the chord-bar-menu "Play from here" (immediate play) alongside.

## Approach

A dedicated `songwriterStartTickProvider` holds the parked start tick (persists
while idle; the transport state can't, since it resets on stop). A new
`_SectionRuler` widget renders a bar ruler per section, sets the provider on
tap/drag (reusing `sectionBarGlobalTick`), and draws the parked marker (via
`activePositionForBar`) plus the live playhead (reusing `SongwriterRowPlayhead`).
The header Play reads the provider for its `startTick`.

Rejected: parking in the transport state (resets on stop); dragging the existing
per-lane playhead (a separate ruler was requested).

### Data flow

```
_SectionRuler tap/drag on bar b (sectionId, instanceIndex)
   │ sectionBarGlobalTick(sections, config, sectionId, b, instanceIndex: …)   [existing rule]
   ▼
songwriterStartTickProvider.setTick(globalTick)          ← parked start (persists)
   │                                    │
   │ parked marker                      │ header Play
   ▼                                    ▼
activePositionForBar(sections, tick~/measureTicks)   startPlayback(startTick: parkedTick)  [existing]
   → draw marker in the matching        during playback: SongwriterRowPlayhead sweeps
     section/instance ruler
```

## Components

### 1. Parked-start state — `songwriterStartTickProvider`

`lib/store/songwriter_playback_store.dart` (co-located with the transport)

```dart
class SongwriterStartTickNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void setTick(int tick) => state = tick < 0 ? 0 : tick;
  void reset() => state = 0;
}

final songwriterStartTickProvider =
    NotifierProvider<SongwriterStartTickNotifier, int>(
      SongwriterStartTickNotifier.new,
    );
```

- Holds a global tick, default 0 (top). Persists across stop (idle cursor).
- No upper clamp here — `startPlayback` already clamps to `[0, endTick)`, and the
  ruler only ever produces valid in-section ticks.

### 2. `_SectionRuler` widget

`lib/features/songwriter/songwriter_section_ruler.dart` (new)

```dart
class SongwriterSectionRuler extends ConsumerWidget {
  const SongwriterSectionRuler({
    super.key,
    required this.section,
    required this.instanceIndex,
  });
  final SongSection section;
  final int instanceIndex;
  // build: read sections+config from songwriterProvider.
}
```

- Renders a `LayoutBuilder` strip of `section.lengthBars` equal cells, each with a
  faint divider + a 1-based bar number (mirrors `_BarDividerPainter` styling).
- **Set start:** `GestureDetector` with `onTapDown` + `onHorizontalDragUpdate`
  maps the local x to a bar `b = (dx / cellWidth).floor().clamp(0, lengthBars-1)`,
  then `ref.read(songwriterStartTickProvider.notifier).setTick(sectionBarGlobalTick(sections, config, section.id, b, instanceIndex: instanceIndex))`.
- **Parked marker:** watch `songwriterStartTickProvider`; map to a bar
  (`tick ~/ measureTicks`) → `activePositionForBar(sections, bar)`; if it resolves
  to this `section.id`/`instanceIndex`, draw a marker (small downward triangle +
  a thin line) at that `localBar`. Otherwise draw nothing.
- **Live playhead:** overlay `SongwriterRowPlayhead(sectionId: section.id,
  instanceIndex: instanceIndex, rowStartBar: 0, barsInRow: section.lengthBars)` so
  it sweeps during playback (existing widget; `IgnorePointer`, renders only when
  active). It sits above the parked marker.
- Height ~18px; `MuzicianTheme` colors (`sky` for the marker/line, `textMuted`
  for numbers), consistent with `_BarDividerPainter`.
- Keys: root `Key('sectionRuler_${section.id}_$instanceIndex')`; the parked marker
  `Key('sectionRulerMarker')` when present (for widget tests).

### 3. Insert into the section card

`lib/features/songwriter/songwriter_screen_sheet.dart` — in the section-instance
`build` (the `Column` that currently starts with the optional repeat label then
`_BarRow`), insert the ruler above `_BarRow`:

```dart
        SongwriterSectionRuler(
          section: section,
          instanceIndex: instanceIndex,
        ),
        const SizedBox(height: 6),
        _BarRow(...),
```

### 4. Header Play reads the parked tick

`lib/features/songwriter/songwriter_header.dart` — the play button currently:
`playing ? t.stopPlayback() : t.startPlayback();`
→ `playing ? t.stopPlayback() : t.startPlayback(startTick: ref.read(songwriterStartTickProvider));`
(The header is a `ConsumerWidget`; `ref` is in scope.)

## Error handling / edge cases

- Parked tick past the song end (e.g. section shrunk after parking): `startPlayback`
  clamps to `[0, endTick)`; the marker simply won't resolve to any section and is
  not drawn.
- Section with 0 bars: `lengthBars` floors to 1 (as elsewhere); ruler shows one
  cell.
- Tapping bar 0: parks at that section's start (or tick 0 for the first section) —
  a natural "back to start" for the first section.
- Repeated section (×N): each instance's ruler parks at its own occurrence via
  `instanceIndex`; the marker shows only in the instance that matches the parked
  tick.
- While playing: tapping the ruler re-parks (updates the provider) but does not
  itself restart; the live playhead keeps sweeping. (Re-seek stays the bar-menu's
  job / a future enhancement.)

## Testing

Store — `test/store/songwriter_playback_test.dart`:
- `songwriterStartTickProvider`: default 0; `setTick(48)` → 48; `setTick(-5)` → 0;
  `reset()` → 0.

Widget — `test/features/songwriter/songwriter_section_ruler_test.dart` (new):
- Pump `SongwriterSectionRuler` for a 4-bar section in a `ProviderScope` with a
  seeded project; tap at the 3rd cell's x → `songwriterStartTickProvider` becomes
  `2 * measureTicks` (bar index 2).
- With the provider set to a bar inside the section, the parked marker
  (`Key('sectionRulerMarker')`) is present; set to a tick outside → absent.

Rule + mapping (`sectionBarGlobalTick`, `activePositionForBar`) already covered by
existing tests; no new rule tests needed.

Manual (device): tap/drag a section's ruler → marker moves; press header Play →
starts from the marked bar; during playback the live playhead sweeps the ruler.

## Out of scope

- Sub-bar (beat) parking / fine scrubbing.
- A single horizontal multi-section timeline.
- Auto-scroll to keep the playhead on screen.
- Re-seek-on-ruler-tap while already playing.
