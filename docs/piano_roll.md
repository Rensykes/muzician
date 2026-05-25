# Piano Roll

A quantized, timeline-based note editor rendered with `CustomPainter`. Supports tap-to-toggle notes, drag-to-move (pitch + position), drag-to-resize, pinch-to-zoom (both axes), beat snapping, named stack buttons, and live chord/scale detection per selected column.

---

## Architecture

```
lib/
  models/piano_roll.dart                  ← data types
  schema/rules/piano_roll_rules.dart      ← tick math, MIDI helpers, defaults
  store/piano_roll_store.dart             ← Riverpod NotifierProvider
  features/piano_roll/
    piano_roll_grid.dart                  ← main editor canvas (PianoRollGrid)
    piano_roll_toolbar.dart               ← tempo, measures, time sig, key, pitch window
    piano_roll_stack_selector.dart        ← chord root + quality → add note stack
    piano_roll_save_stack_loader.dart     ← load stacks from saved progressions
    piano_roll_detection_panel.dart       ← detect chord/scale at selected column
```

---

## Data Model (`lib/models/piano_roll.dart`)

| Type | Description |
|---|---|
| `PianoRollNote` | One note: `id`, `midiNote`, `pitchClass`, `noteWithOctave`, `startTick`, `durationTicks` |
| `TimeSignature` | `beatsPerMeasure` + `beatUnit` (4 or 8) |
| `PianoRollConfig` | `tempo` (BPM), `key`, `timeSignature`, `totalMeasures` |
| `PianoRollState` | Full state: `config`, `notes`, `pitchRangeStart`, `pitchRangeEnd`, `selectedColumnTick`, `selectedNoteId` |

---

## Schema / Rules (`lib/schema/rules/piano_roll_rules.dart`)

| Export | Description |
|---|---|
| `ticksPerQuarter` | `4` — 1 tick = 1/16th note |
| `minTempo` / `maxTempo` | `20` / `300` BPM |
| `minMidi` / `maxMidi` | `21` (A0) / `108` (C8) |
| `ticksPerMeasure(ts)` | Ticks in one measure for a given signature |
| `totalTicks(ts, measures)` | Total ticks in the timeline |
| `getNotesAtTick(notes, tick)` | Notes that are active at a given tick |
| `midiToPitchClass(midi)` | `"C#"`, `"D"`, etc. |
| `midiToNoteWithOctave(midi)` | `"C#4"`, `"D3"`, etc. |
| `validateTimeSignature(ts)` | Returns `({bool valid, List<String> errors})` |
| `getDefaultPianoRollState()` | 120 BPM, 4/4, 4 measures, C3–C6 window |

---

## Live Hum to MIDI

The piano roll now includes a mobile-only `Hum to MIDI` recorder. It captures mono microphone input, estimates one stable pitch at a time, lightly quantizes timing after stop, and appends the finalized notes to the current piano roll instead of replacing existing content.

### Timeline growth

- Hum imports expand the **timeline horizontally** (add measures) when the imported phrase extends beyond the current end tick.
- If the imported phrase ends exactly on the current boundary, no extra measure is added.
- **No pitch-range auto-growth** in this follow-up — imported notes outside the visible pitch window are clamped.

### Selection handoff

- If no column was selected before recording, `selectedColumnTick` is set to the first imported note's start tick after the take completes.
- If a column was already selected, the existing selection is **preserved**.
- Stopping a hum take **stops active playback** first if the transport is already running.

### Latest import navigation

- After a successful hum import that creates notes, the `Hum to MIDI` card shows a `Jump to latest` button.
- `Jump to latest` scrolls horizontally to the start tick of the most recent hum-imported range.
- The action is navigation-only: it does not change playback state, selected notes, or `selectedColumnTick`.
- The button tracks only the latest hum import target. A later successful hum import replaces it, and non-import note-add actions clear it.

### Post-quantization monophonic normalization

- Quantized hum notes are normalized before append so the final import remains monophonic.
- If two neighboring imported notes overlap after quantization, the earlier note is trimmed to end at the later note's start tick.
- If trimming would reduce that earlier note to zero length, that earlier note is dropped.

### Detection pipeline

The hum-to-MIDI capture splits into four stages. Stages 1–2 run while recording; stages 3–4 run on stop.

| Stage | Code | Responsibility |
|---|---|---|
| 1. PCM capture & windowing | `lib/utils/mic_pitch_session.dart` | Buffer raw 16 kHz mono PCM, slide a 1024-sample window with 512-sample hop, emit ~31 `PitchFrame`/sec |
| 2. Pitch estimation | `lib/schema/rules/mono_pitch_rules.dart` (`estimateDominantFrequencyFromSamples`) | YIN with CMNDF, local-minimum descent, parabolic interpolation → `(frequencyHz, confidence)` |
| 3. Segmentation | `lib/schema/rules/mono_pitch_rules.dart` (`segmentStableNotes`) | Group consecutive same-MIDI frames into `DetectedMonoNote { startMs, endMs, midiNote, confidence }` with 1-frame hysteresis |
| 4. Quantization & monophonic normalization | `quantizeNotesToTicks` + `normalizeQuantizedHumNotesMonophonically` | Map ms → ticks against the current tempo, snap to `snapTicks`, drop overlaps |

**Why windowing is internal.** iOS's `record` plugin delivers PCM chunks at the rate the audio session decides (often ~250 ms). One chunk per hummed eighth/quarter note meant the segmenter saw a single frame and computed 0 ms duration, so the note was dropped. Sliding a fixed window over the raw bytes decouples the frame rate from the platform's buffer size.

**Why parabolic interpolation.** Pure integer-lag YIN buckets the frequency by 1-sample steps. Around a semitone boundary the rounded MIDI flips between adjacent notes from frame to frame, fragmenting one sustained note into many sub-notes. Parabolic interpolation on the CMNDF local minimum gives sub-sample lag → stable MIDI.

**Why 1-frame hysteresis.** Even with parabolic refinement, vibrato or a single transient frame can briefly land in the neighbouring semitone. The segmenter requires **two consecutive** off-pitch frames before switching `activeMidi`; a lone deviation is folded back into the active note.

### Tunable parameters

All in `lib/schema/rules/mono_pitch_rules.dart`:

| Constant | Value | Effect of raising it |
|---|---|---|
| `minHumFrequencyHz` / `maxHumFrequencyHz` | 80 / 1000 | Sets the YIN lag search range and rejects out-of-range pitches |
| `minHumAmplitude` | 0.02 | Higher → more aggressive silence gate, fewer breath/noise false positives |
| `_yinThreshold` | 0.15 | Higher → accept weaker pitches (more recall, less precision) |
| `minStableConfidence` | 0.6 | Confidence = `1 − cmndf[bestLag]`. Higher → drop borderline frames |
| `minStableNoteMs` | 80 | Floor on note duration even at the most permissive sensitivity preset |
| `maxMergeGapMs` | 180 | Silence within a note merges if shorter than this |

### User-facing pitch sensitivity

The Hum panel exposes a three-way `SegmentedButton` (Strict / Balanced / Forgiving) that selects how aggressively the segmenter switches notes. The choice persists via `SettingsNotifier.setHumSensitivity` and is read at `stopRecording` time.

Each preset overrides three knobs (in `HumSensitivityTuning`):

| Preset | `switchFrames` | `deadbandCents` | `minNoteMs` |
|---|---|---|---|
| Strict | 2 | 0 | 80 |
| Balanced (default) | 4 | 35 | 120 |
| Forgiving | 7 | 60 | 180 |

- **`switchFrames`** — number of consecutive off-pitch frames required before the segmenter abandons the active MIDI note. Higher absorbs more wobble.
- **`deadbandCents`** — even when a frame's rounded MIDI differs from the active note, if its actual frequency is within this many cents of the active note's reference frequency it is folded back into the active note (so a singer hovering 40 cents sharp of A4 stays as A4 in Forgiving but switches to A#4 in Strict).
- **`minNoteMs`** — minimum emitted note duration for the preset; shorter candidates are dropped.

The selector is disabled while a recording or processing is in flight so the value can't change mid-take.

### Edge cases handled

- **Single-frame notes**: when only one voiced frame falls inside `[startMs, endMs]`, the segmenter assigns the note the **median observed inter-frame delta** as its duration (instead of 0 ms).
- **Absolute vs. relative timestamps**: `PitchFrame.timestampMs` is **ms since recording start**, not epoch ms. Producers (`RecordMicPitchSession`) must subtract the recording's start time before emitting.
- **Silence gate before YIN**: windows below `minHumAmplitude` skip pitch estimation entirely and emit an `isSilence: true` frame. This prevents YIN from latching onto low-amplitude room noise and producing phantom notes.

---

## Playback

The piano roll includes a simple onset-sequencer transport that plays notes via the synthesised `NotePlayer` engine.

### Controls

The **Playback** panel in the toolbar shows:
- **Play / Stop** button — starts or cancels transport.
- **Status text** — shows the start point and current tick while playing.

| Condition | Behavior |
|---|---|
| Idle + column selected | `Start: Selected column (tick N)` — plays from that tick |
| Idle + no column selected | `Start: Beginning of roll` — plays from tick 0 |
| Playing | Shows current tick advancing |
| Hum is recording / processing | Playback button hidden; shows "Playback unavailable while humming" |
| No notes at or after the start tick | Shows "Nothing to play from the selected column" |

### Scope

| In scope | Out of scope |
|---|---|
| Play / Stop | Pause / Resume |
| Start from selected column | Loop mode |
| Run to end of timeline | Metronome / count-in |
| Onset-only sequencing (duration-accurate note-offs deferred) | Animated playhead / auto-scroll |
| | Multi-track / velocity editing |
| | MIDI export |
| | Pitch-range auto-growth |

---

## Store (`lib/store/piano_roll_store.dart`)

Provider: `pianoRollProvider` (Riverpod `NotifierProvider<PianoRollNotifier, PianoRollState>`)

### Key actions

| Method | Description |
|---|---|
| `setTempo(bpm)` | Update BPM, clamped to 20–300 |
| `setKey(key)` | Set key string (e.g. `"C major"`) or `null` |
| `setTimeSignature(ts)` | Update signature, trims out-of-range notes |
| `setTotalMeasures(n)` | Expand / shrink timeline, trims notes |
| `toggleCellNote(midi, tick, duration)` | Add note if absent; remove if present at same position |
| `addNote(midi, tick, duration)` | Add unconditionally |
| `removeNote(id)` | Delete by ID |
| `moveNote(id, newTick, newMidi)` | Reposition (beat-snapped by the grid) |
| `resizeNote(id, durationTicks)` | Change note length (1/16th minimum) |
| `addNoteStack(midiList, tick, duration)` | Add multiple notes at the same tick (chord) |
| `selectColumn(tick)` | Set `selectedColumnTick` for detection panel |
| `selectNote(id)` | Highlight a specific note |
| `setPitchRange(start, end)` | Shift the visible MIDI window |
| `shiftPitchRange(semitones)` | Scroll the pitch window ± semitones |
| `clearNotes()` | Remove all notes |

---

## Widgets

### `PianoRollGrid`
The core editor. Three `CustomPainter` layers rendered inside synchronized scroll views:

| Painter | Draws |
|---|---|
| `_PitchSidebarPainter` | MIDI note labels (all white + black keys), black-key row shading |
| `_RulerPainter` | Measure numbers, beat dots, tick marks, selected-column marker |
| `_GridPainter` | Row backgrounds, grid lines, column highlight, note rectangles, resize handles |

**Scroll architecture:**
- Four `ScrollController`s: `_hScroll` + `_vScroll` (grid), `_rulerHScroll` (ruler synced to `_hScroll`), `_sidebarVScroll` (sidebar synced to `_vScroll`)
- All scroll views use `NeverScrollableScrollPhysics` — scroll is driven programmatically via `_manualScroll(delta)` in pointer move
- A `GestureDetector` wrapping the card (in `main.dart`) claims the gesture arena to block the parent `ListView` from stealing touches

**Pinch-to-zoom:**
- Tracked via raw `Listener` + `_pointers` map (pointer ID → position)
- When 2 fingers are down, horizontal spread scales `_cellW` (10–80 px), vertical spread scales `_rowH` (10–40 px)
- All painters and hit-test math use the live `_cellW`/`_rowH` values

**Gesture state machine (raw `Listener`):**

| Event | Single finger | Two fingers |
|---|---|---|
| `onPointerDown` | Record hit, start 500 ms long-press timer | Enter pinch mode, record initial spread |
| `onPointerMove` (< 8 px) | No-op (inside slop threshold) | Scale `_cellW` / `_rowH` |
| `onPointerMove` (≥ 8 px) | If on note: move/resize; else: scroll | Scale `_cellW` / `_rowH` |
| `onPointerUp` | If no movement: tap (add/select); if timer fired: already deleted | Exit pinch if last finger lifted |

**Note interactions:**

| Action | How to trigger |
|---|---|
| **Add note** | Tap on empty cell |
| **Select note** | Tap on existing note |
| **Move note** | Drag note body (horizontal = beat-snapped tick, vertical = semitone pitch) |
| **Resize note** | Drag right-edge handle (rightmost 16 px, snaps to 1/16th minimum) |
| **Delete note** | Long-press (500 ms) on note |

**Beat snapping (move):**
- Beat ticks = 4 (quarter note) for 4/4; = 2 (eighth) for 4/8 time signatures
- Snaps: `round(rawTick / beatTicks) * beatTicks`
- `_grabOffsetTicks` ensures the note doesn't jump to cursor's left edge

**Ruler tap:**
- Tap anywhere on the ruler row to set `selectedColumnTick` → triggers detection panel

---

### `PianoRollToolbar`
Controls bar at the top of the screen:

| Control | Type | Provider action |
|---|---|---|
| Tempo | `−` / `+` stepper | `setTempo()` |
| Measures | `−` / `+` stepper | `setTotalMeasures()` |
| Time signature | Pill selector (4/4, 3/4, 6/8…) | `setTimeSignature()` |
| Key | Dropdown (major / minor / none) | `setKey()` |
| Pitch window | `▲` / `▼` buttons (±12 semitones) | `shiftPitchRange()` |
| Clear | Button | `clearNotes()` |

---

### `PianoRollStackSelector`
Chord root (12 chromatic) + quality (major, minor, 7, maj7, m7, dim, aug) + duration (1–4 beats) picker. Tapping "Add Stack" calls `addNoteStack()` at `selectedColumnTick` (or tick 0 if none). Notes are voice-led to the closest MIDI range within the current pitch window.

---

### `PianoRollSaveStackLoader`
Connects the save system to the piano roll. Lets the user browse saved progressions and place their notes into the timeline:

- **Folder browser** with breadcrumb navigation via `saveSystemProvider`
- **Placement mode toggle**: "Exact MIDI" (loads original MIDI values) vs "Pitch Class" (transposes to fit current pitch window using `_bestMidiInRange`)
- **"Add Stack" button**: calls `addNoteStack()` at current column

Supports fretboard snapshots (`FretboardSnapshot` → extracts MIDI via note name parsing) and piano snapshots (`PianoSnapshot` → uses `midiNote` directly).

---

### `PianoRollDetectionPanel`
Shows at selected column (`selectedColumnTick`). Displays:

- **Note chips** — one per active note. Each chip: tap to select, `×` button to delete.
- **Chords** — detected chord names (max 8), matching exact pitch-class set
- **Scales** — detected scale names (max 8), where all selected PCs are subset of scale
- **Delete Selected Note** — red button present when a note is selected

Detection is local to the widget (no external library) using hardcoded interval sets for 9 chord qualities and 4 scale types.

---

## Timeline Math

```
ticksPerQuarter = 4
→ 1 tick         = 1/16th note
→ 4 ticks        = 1 quarter note
→ 4×beatsPerMeasure ticks = 1 measure (4/4)
→ totalTicks     = ticksPerMeasure × totalMeasures
```

Column width in pixels: `_cellW` (default 28 px, zoom range 10–80 px)  
Row height in pixels: `_rowH` (default 18 px, zoom range 10–40 px)

---

## State Flow

```
PianoRollToolbar → pianoRollProvider.setTempo() / setTimeSignature() / …
                              │
               PianoRollGrid repaints via ref.watch
                              │
    User taps cell → pianoRollProvider.toggleCellNote(midi, tick)
                              │
    User taps ruler → pianoRollProvider.selectColumn(tick)
                              │
    PianoRollDetectionPanel shows chords/scales at that column
```

---

## Info Panel

File: `lib/ui/core/app_info_panel.dart`

A shared, dismissible help overlay available from every instrument screen. Opened by tapping the **?** button in the top-right corner of each screen header.

### Entry point

```dart
showAppInfoPanel(context, initialTab: 2); // 0 = Fretboard, 1 = Piano, 2 = Piano Roll
```

### Structure

Rendered as a modal bottom sheet at 88 % of screen height with a drag handle.

| Widget | Role |
|---|---|
| `_AppInfoSheet` | `StatefulWidget` owning a `TabController` |
| `_DragHandle` | Visual pull-down indicator |
| `_Header` | Title + close (×) button |
| `_TabBar` | Three tabs: Fretboard / Piano / Piano Roll |
| `_FretboardInfoTab` | Gesture + mode + tool entries for the fretboard |
| `_PianoInfoTab` | Gesture + tool + behaviour entries for the piano |
| `_PianoRollInfoTab` | Gesture + toolbar + panel + timeline-math entries |
| `_Section` | Section header (icon + uppercase label) + card container |
| `_Entry` | Icon badge + bold label + description text |

### Piano Roll tab sections

| Section | Content |
|---|---|
| **Gestures** | Tap to add/select, drag body to move (beat-snapped + semitone), drag edge to resize, long-press to delete, ruler tap to set column, pinch to zoom, single-finger drag to scroll |
| **Toolbar Controls** | Tempo (20–300), Measures, Time signature, Key, Pitch window (▲/▼ ±12 semitones), Clear |
| **Panels** | Stack selector, Save stack loader (Exact MIDI vs Pitch Class), Detection panel (note chips + chords + scales) |
| **Timeline Math** | 1 tick = 1/16th note, beat snapping rules |
