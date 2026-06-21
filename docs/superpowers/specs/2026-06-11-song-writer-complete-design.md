# Song & Writer Completion — Design

**Date:** 2026-06-11
**Branch:** `feature/song-writer-complete` (off `merge/writer-unified`)
**Goal:** Complete the Song and Writer sections: audible playback of the full song in both,
a rich set of Song arranger enhancements, and responsive portrait + landscape layouts for
both screens.

---

## Context (state at branch point)

- **Writer** (`lib/features/songwriter/`): the active UI is the sheet variant
  (`songwriter_screen_sheet.dart`, mounted by the 12-line `songwriter_screen.dart` wrapper).
  It renders sections as chord-sheet rows with lyrics and drum lanes. The transport
  (`lib/store/songwriter_playback_store.dart`) is a **bar-clock metronome only** — harmony
  blocks, save blocks, and drum lanes are silent. There is no playhead indication in the
  sheet UI.
- **Song** (`lib/features/song/`): pattern-based clip arranger with note, drum, and audio
  tracks. Playback works end-to-end (`lib/store/song_playback_store.dart`: tick loop, note
  sink via `NotePlayer`, drum sink, `audioplayers` clip sink). The timeline
  (`song_arranger_timeline.dart`) supports long-press clip creation, in-lane move/resize,
  audio peak rendering, ruler seek. Clips render as flat colored blocks with no content
  preview; clip drag is in-lane only.
- **Orientation:** iOS Info.plist allows landscape; only Piano Roll has a width-adaptive
  layout. Song and Writer are portrait-shaped. Known issue: Writer header chips clip on
  narrow widths.
- **Models:** `lib/models/songwriter.dart` (`SongwriterProjectSnapshot`, sections → lanes
  → blocks; `SongLaneKind { harmony, save, drum }`; `drumPatterns` reuse
  `DrumPattern`/`DrumLaneSequence` from `lib/models/song_project.dart`, tick-based).
  `chordNotes` on harmony blocks is `List<String>` of note names.
- **Tick conventions:** ticksPerQuarter = 4; `beatTicks = beatUnit == 8 ? 2 : 4`;
  `measureTicks = beatTicks * beatsPerBar`; tick duration =
  `durationForTickDelta(1, tempo)`.

---

## 1. Writer playback engine

Extend `SongwriterPlaybackNotifier` from a bar-clock to a **tick clock** (same tick
conventions as the Song transport).

New pure rule in `lib/schema/rules/songwriter_playback_rules.dart`:

```dart
List<SongwriterPlaybackEvent> flattenPlaybackEvents(SongwriterProjectSnapshot project)
```

- Expands sections via existing `expandSections` (section repeats) and `tileLaneBlocks`
  (lane repeats) into a global tick timeline.
- **Harmony blocks** → chord pitches fire at the block's start bar and at every bar
  boundary inside the block (per-bar stab). Pitches resolved from `chordNotes` (note name →
  midi around octave 4) with fallback to `chordRootPc` + `chordQuality` interval map.
- **Save blocks** → resolve snapshot via existing `resolveBlockSnapshot` (embedded →
  live save → broken). Fretboard snapshots map string+fret → midi; piano snapshots map
  selected keys → midi. Same per-bar firing as harmony. Broken blocks are silent.
- **Drum lane blocks** → referenced `DrumPattern` events at native tick resolution,
  tiled across the block's bar span, clipped to block end.
- Events are sorted by tick; the notifier walks them exactly like
  `SongPlaybackNotifier`'s loop (version-guarded async loop, `Future.delayed` per tick).
- Sinks: existing `NotePlayer` chord sink (injectable provider, test-overridable),
  existing `drumPatternPlaybackSinkProvider`, metronome unchanged (gated by
  `settingsProvider.metronomeEnabled`).
- State gains `currentTick`; `currentBar` derived for UI.

## 2. Writer playhead in sheet UI

- Active chord cell and active bar get a highlight tint while playing (watch
  `currentBar`, map global bar → section instance + local bar via existing
  `sectionAtGlobalBar` maths extended for per-instance rows).
- Sheet auto-scrolls to keep the active section row visible.
- Play/stop already in `SongwriterHeader` — unchanged entry point.

## 3. Song transport upgrades

All on `SongPlaybackState` / `SongPlaybackNotifier`:

- **Loop region:** `loopStartTick` / `loopEndTickExclusive` (nullable pair). Horizontal
  drag on the measure ruler sets the region (snapped to measures); tap on region clears
  it. Tick loop wraps: when `tick == loopEnd`, jump to `loopStart` (audio clips stopped
  and re-fired). Region painted on ruler.
- **Practice tempo:** `tempoMultiplier` (0.5 / 0.75 / 1.0) in playback state; scales tick
  duration only. Chip cycle control in transport.
- **Auto-follow:** during playback the timeline scroll keeps the playhead in view;
  pauses while the user is touching the scroll view; toggle in transport overflow.
- **Count-in:** optional 1-measure metronome count-in before tick 0. Metronome
  on/off toggle surfaced in the Song transport (reuses settings flag).
- **Per-track volume:** `volume` (0.0–1.0, default 1.0) added to `SongTrack`
  (JSON-migrated, default when absent). Slider in track header menu. Note sink, drum
  sink (replaces hardcoded 0.8), and audio sink all honor it.

## 4. Clip previews + readability

In `_ClipLanePainter`:

- **Note clips:** mini thumbnail — note rects scaled to the pattern's pitch range,
  x scaled tick→width, drawn inside the clip body (same approach as
  `save_preview_thumbnail.dart`).
- **Drum clips:** step-dot grid — one row per used lane, dots at hit ticks.
- **Audio clips:** keep peaks.
- Clip label (pattern name) drawn when clip wide enough; shared-pattern badge made
  explicit (link icon + count); slight track-color contrast tuning for readability.

## 5. Drag & drop + clip ops

- **Cross-track drag:** vertical drag during clip move targets another track of the
  same type; drop relocates the clip (collision-checked, snap preserved). Invalid
  targets show no-drop affordance.
- **Duplicate clip:** action-bar button; copy placed immediately after the original
  (same pattern reference; collision-checked).
- **Copy/paste:** copy in action bar stores clip ref; paste via long-press menu on a
  compatible track at snapped position.
- **Transpose:** note clips get ±1 semitone / ±12 buttons in the action bar
  (pattern-level edit; shared patterns transpose all instances — same semantics as
  pattern editing today).
- **Snap selector:** measure ↔ beat toggle, used by create/move/resize/paste.
- **Track reorder:** drag handle in track header; inline rename (existing rename moved
  inline).

## 6. Split + audio trim

- **Split at playhead** (note + drum clips): clip splits into two; each half gets a
  **unique** sliced pattern (Make-Unique semantics — other instances of a shared
  pattern unaffected). Pure rule: `splitNotePattern(pattern, tick)` /
  `splitDrumPattern(pattern, tick)`.
- **Audio trim/fade:** `trimStartMs`, `trimEndMs`, `fadeInMs`, `fadeOutMs` on audio
  clips (JSON-migrated defaults 0). Sink honors trim offsets (seek + early stop) and
  fades (volume ramp). Trim handles in clip action bar (numeric stepper v1, not
  waveform drag). Audio split enabled after trim lands (split = two clips with
  adjusted trims).

## 7. Markers + zoom

- **Markers:** `SongMarker { id, tick, label, color }` list on `SongProject`
  (JSON-migrated, default empty). Long-press on ruler adds; tap marker flag edits/
  deletes. Painted as labeled flags on ruler.
- **Pinch zoom:** horizontal scale gesture on timeline adjusts measure width between
  min/max (Piano Roll's pattern reused); ruler and lanes share the scale.

## 8. Landscape reflow (both screens)

Responsive reflow via `LayoutBuilder` width checks — no separate screen builds.

- **Song:** in wide/short viewports the header collapses to a slim single row
  (transport inline), track gutter narrows, timeline takes the freed width. No
  overflow at any phone size in either orientation.
- **Writer:** sheet flows section cards in two columns when width allows; header
  chips get ellipsis + flexible widths (fixes known clipping issue); structure
  editor and sheets remain usable in landscape (scrollable, max-height capped).

## 9. Cross-feature

- **Hum into clip:** "Hum melody" option in the add-clip sheet for note tracks →
  existing hum-to-midi flow records and quantizes → resulting notes become the new
  clip's pattern.
- **Writer→Song import:** action in Song header ("Import from Writer"). Mapping:
  flattened Writer sections (repeats expanded) → song measures + a marker per section
  instance (label = section label); harmony lane → one note track with per-bar
  chord-stab patterns (one pattern per distinct block, reused across repeats); drum
  lanes → drum tracks (DrumPatterns carried over); save lanes → note tracks with
  stacked-chord patterns from resolved snapshots. Tempo / time signature / key copied
  from Writer config. Import creates a fresh song (confirmation if current song
  non-empty). Pure rule: `songFromSongwriter(project) → SongProject`.
- **Export WAV v1:** offline render of note + drum tracks to a WAV file via
  `wav_writer.dart` (simple synth voices mixed at sample level; audio clips excluded
  in v1 — noted in the export dialog). Share via platform share sheet.

## 10. Phases

| P | Content | Gate |
|---|---|---|
| 1 | Writer playback engine + sheet playhead (§1–2) | tests + analyze + sim |
| 2 | Song transport upgrades (§3) | tests + analyze + sim |
| 3 | Clip previews + readability (§4) | tests + analyze + sim |
| 4 | Drag/drop + clip ops (§5) | tests + analyze + sim |
| 5 | Split + audio trim (§6) | tests + analyze + sim |
| 6 | Markers + zoom (§7) | tests + analyze + sim |
| 7 | Landscape reflow both screens (§8) | sim portrait+landscape |
| 8 | Hum-into-clip, Writer→Song import, Export WAV (§9) | tests + analyze + sim |

## Testing

- Pure rules unit-tested: `flattenPlaybackEvents`, chord-pitch resolution, snapshot →
  midi mapping, loop-window wrap, split maths, transpose, marker ops,
  `songFromSongwriter`, WAV render buffer.
- Widget tests for new UI controls (loop ruler gesture, action-bar buttons, volume
  slider, marker editing, landscape header collapse).
- `flutter analyze` clean and full `flutter test` green at every phase gate.
- serve-sim visual verification per phase; phase 7 verified in both orientations.

## Out of scope

- Audio-clip inclusion in WAV export (v2).
- Waveform-drag trim handles (numeric stepper v1).
- Velocity/dynamics on note playback; MIDI export; tempo ramps.
