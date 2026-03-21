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
