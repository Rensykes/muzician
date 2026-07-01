# Songwriter — play from a chosen bar (mid-section start)

**Status:** design
**Date:** 2026-06-29
**Branch:** feature/songwriter-audio-daw

## Problem

The Songwriter transport always starts at tick 0 (top of the song). There is no
way to start playback from the middle of a section — e.g. to rehearse bar 5 of
an 8-bar section onward. We want a "Play from here" affordance on a bar that
starts the transport at that bar and continues through the rest of the song.

## Decisions (from brainstorming)

- **Trigger:** a **"Play from here"** item in the bar action sheet (tapping a
  bar). Bar tap/long-press are already taken (edit/add, remove), and a menu item
  is discoverable and non-conflicting.
- **Scope:** start at the chosen bar's global position and **continue through
  the rest of the song** (a transport seek), mirroring the Song feature.
- **Granularity:** bar-level (no sub-bar/beat seek).

## Approach

Mirror the Song transport's existing `startTick` seek. The Song
`SongPlaybackNotifier.startPlayback({startTick})` already: filters events to
`tick >= start`, starts the loop at `start`, and in `fireAudioForTick` seeks
**into** clips that span the start (`offsetIntoAsset(nowMs)`) while skipping
clips that already ended. The Songwriter transport's `fireAudio` is structurally
identical, so the only real work is starting the loop at `start`, skipping
earlier events, and fixing the pacer.

Rejected: a separate section sub-transport (duplicates transport logic); a
persistent draggable seek cursor (more UI than the chosen bar-menu trigger).

### Data flow

```
bar action sheet "Play from here" (section, localBar)
   │ sectionBarGlobalTick(sections, config, sectionId, localBar)  ← new pure rule
   ▼
songwriterPlaybackProvider.startPlayback(startTick: globalTick)
   ▼
tick loop from `start` → endTick, pacing off elapsedTicks(0-based);
events filtered to tick >= start; audio clips spanning `start` seek in.
```

## Components

### 1. Pure rule — `sectionBarGlobalTick`

`lib/schema/rules/songwriter_playback_rules.dart`

```dart
/// Global transport tick for [localBar] within the FIRST occurrence of
/// [sectionId] on the flattened timeline. A repeated section maps to its first
/// occurrence. Returns 0 if the section isn't found or [localBar] <= 0 clamps.
int sectionBarGlobalTick(
  List<SongSection> sections,
  SongwriterConfig config,
  String sectionId,
  int localBar,
);
```

- `measureTicks = config.ticksPerBeat * config.beatsPerBar`.
- Find the first `expandSections(sections)` entry whose `sectionId` matches; take
  its `globalStartBar`. Return `(globalStartBar + localBar.clamp(0, ...)) * measureTicks`.
- Clamp `localBar` into the section: `0 .. section.lengthBars - 1` (a start past
  the section end would skip it; clamp keeps it inside).
- Section not found → return 0 (transport starts at top — safe fallback).

### 2. Transport — `startPlayback({int startTick = 0})`

`lib/store/songwriter_playback_store.dart`

Change `startPlayback({Duration? tickDurationOverride})` →
`startPlayback({int startTick = 0, Duration? tickDurationOverride})`.

- After computing `endTick`: `final start = startTick.clamp(0, endTick);`
  If `start >= endTick` → set `completed` and return (matches the existing
  `endTick <= 0` early-out).
- Initial state: `currentTick: start` (instead of 0).
- Before the loop, advance `eventIndex` past events earlier than `start`:
  `while (eventIndex < events.length && events[eventIndex].tick < start) eventIndex++;`
- **Pacer fix (required):** the loop currently paces with `awaitBoundary(tick)`.
  Starting at `tick = start` would make the first `awaitBoundary(start)` wait
  `tickDuration * start` (the wall clock is ~0). Introduce a monotonic
  `var elapsedTicks = 0;` and pace with `awaitBoundary(elapsedTicks)`, matching
  the Song loop. Loop: `for (var tick = start; tick < endTick; tick++) { if (elapsedTicks > 0) await pacer.awaitBoundary(elapsedTicks); ... elapsedTicks++; }`.
- Everything else (metronome on `tick % beatTicks`, event firing, `fireAudio`)
  is unchanged. `fireAudio` already fires clips with `startMs <= nowMs` using
  `offsetIntoAsset(nowMs)` (so a clip spanning `start` plays from the right
  offset) and stops clips whose `endMs <= nowMs` (so clips fully before `start`
  are armed+stopped on the first tick, as in the Song transport).
- `stopPlayback()` unchanged. The header Play button keeps calling
  `startPlayback()` (start 0).

### 3. UI — "Play from here" bar action

`lib/features/songwriter/songwriter_screen_sheet.dart`

The bar action sheets (`_onTapEmpty`, `_onTapBlock`) gain a "Play from here" row
(icon `Icons.play_arrow`). On tap it:
1. resolves the tapped bar's `localBar` + `sectionId` (already in scope at the
   tap site),
2. `final t = sectionBarGlobalTick(sections, config, sectionId, localBar);`
3. `ref.read(songwriterPlaybackProvider.notifier).stopPlayback();`
   then `unawaited(...startPlayback(startTick: t));`
4. closes the sheet.

If a single shared bar-menu builder exists, add the row once there; otherwise
add it to both the empty-cell and block sheets so it's available on any bar.

## Error handling / edge cases

- `startTick <= 0` → behaves like the header Play (start at top).
- `startTick >= endTick` (e.g. last bar of the song, empty song) → no-op /
  completed, no crash.
- Repeated section (×N): "Play from here" starts at the **first** occurrence's
  position and continues through the repeats + later sections.
- Already playing: `startPlayback` returns early (existing guard); the action
  calls `stopPlayback()` first so "Play from here" while playing re-seeks.
- Audio clip spanning the start bar: plays from the correct in-asset offset
  (existing `fireAudio` / `offsetIntoAsset`).

## Testing

Unit (pure rule) — `test/schema/rules/songwriter_playback_rules` (or the
existing playback-rules test):
- `sectionBarGlobalTick`: bar 0 of the first section → 0; bar 2 of a section
  starting at global bar 4 → `(4+2)*measureTicks`; repeated section → first
  occurrence; unknown section → 0; `localBar` clamped to the section length.

Store — `test/store/songwriter_playback_test.dart` (fake sinks + fast tick):
- `startPlayback(startTick: N)` sets `currentTick` to N at start.
- Events before N do **not** fire; events at/after N fire (assert note/drum sink
  receives the at-N event, not an earlier one).
- Completes at `endTick`.
- `startTick` past the end → no events fired, completes immediately.
- `startTick: 0` → unchanged from today (regression guard).

Widget (light) — the bar sheet exposes a "Play from here" row keyed
`sw-bar-play-from-here`; tapping it calls `startPlayback` with the bar's tick.

## Out of scope

- Persistent seek cursor / the header Play resuming from the last point.
- Sub-bar (beat) granularity; scrubbing/dragging a playhead.
- Section-only or looped-from-bar playback (chosen scope is play-through).
