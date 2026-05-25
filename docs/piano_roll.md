# Piano Roll

A quantized, timeline-based note editor rendered with `CustomPainter`. Supports tap-to-toggle notes, drag-to-move (pitch + position), drag-to-resize, pinch-to-zoom (both axes), beat snapping, named stack buttons, live chord/scale detection per selected column, mobile-only Hum-to-MIDI recording, and adaptive landscape/portrait layout.

---

## V2 Architecture

Piano Roll exists in two shells that share the same domain logic:

| Shell | File | Role |
|---|---|---|
| V1 | `lib/main.dart` (inline composition) | Compatibility shell and regression harness; renders the same providers as V2. |
| V2 | `lib/features/piano_roll/piano_roll_screen_v2.dart` | Target product surface with adaptive landscape/portrait layout, inspector rail, and collapsible panels. |

Both shells read from the same set of Riverpod providers — there is no widget-local fake state in V2. The implementation follows the design spec: shared logic in models, rules, and providers; two renderers.

V2 is the default surface; V1 stays in the codebase until explicitly removed.

---

## Architecture

```
lib/
  models/
    piano_roll.dart                       ← canonical editor state
    piano_roll_composer.dart              ← shared chord-stack composer state
    piano_roll_playback.dart              ← playback transport state
    save_system.dart                      ← PianoRollSnapshot (persistence)
  schema/rules/
    piano_roll_rules.dart                 ← tick math, MIDI helpers, defaults
    piano_roll_import_rules.dart          ← stack building, snapshot-import mapping
    piano_roll_playback_rules.dart        ← playback sequencing
    mono_pitch_rules.dart                 ← hum-to-MIDI pitch estimation
  store/
    piano_roll_store.dart                 ← Riverpod NotifierProvider
    piano_roll_composer_store.dart        ← shared composer provider
    piano_roll_playback_store.dart        ← playback transport provider
    hum_to_midi_store.dart                ← hum recording provider
  features/piano_roll/
    piano_roll_grid.dart                  ← main editor canvas (PianoRollGrid)
    piano_roll_screen_v2.dart             ← V2 adaptive layout shell
    piano_roll_toolbar.dart               ← tempo, measures, time sig, key, pitch window
    piano_roll_stack_selector.dart        ← chord root + quality → add note stack
    piano_roll_scale_picker.dart          ← scale-highlight picker
    piano_roll_save_stack_loader.dart     ← load stacks from saved progressions
    piano_roll_save_panel.dart            ← first-class piano-roll save/load
    piano_roll_detection_panel.dart       ← detect chord/scale at selected column
    piano_roll_hum_recorder.dart          ← mobile-only hum → MIDI
```

### Shared Providers

| Provider | State type | Purpose |
|---|---|---|
| `pianoRollProvider` | `PianoRollState` | Canonical editor: notes, config, range, selection, tool, snap, highlights |
| `pianoRollComposerProvider` | `PianoRollComposerState` | Root, quality, duration for chord-stack building |
| `pianoRollPlaybackProvider` | `PianoRollPlaybackState` | Playback transport: status, current tick, start point |
| `humToMidiProvider` | `HumToMidiState` | Mobile-only recording pipeline |
| `pianoRollPendingScaleProvider` | `({String root, String scaleName})?` | Temp scale preview |
| `pianoRollScrollToTickProvider` | `int?` | One-shot scroll-to-tick signal |

---

## Data Model (`lib/models/piano_roll.dart`)

| Type | Description |
|---|---|
| `PianoRollNote` | One note: `id`, `midiNote`, `pitchClass`, `noteWithOctave`, `startTick`, `durationTicks` |
| `TimeSignature` | `beatsPerMeasure` + `beatUnit` (4 or 8) |
| `PianoRollConfig` | `tempo` (BPM), `key`, `timeSignature`, `totalMeasures` |
| `PianoRollTool` | Enum: `draw`, `scissors` |
| `PianoRollImportedRange` | `startTick`, `endTickExclusive` — tracks latest hum import range |
| `PianoRollState` | Full state: `config`, `notes`, `pitchRangeStart`, `pitchRangeEnd`, `selectedColumnTick`, `selectedNoteIds`, `activeTool`, `snapTicks`, `highlightedNotes`, `latestImportedRange` |

### Composer State (`lib/models/piano_roll_composer.dart`)

| Field | Default | Purpose |
|---|---|---|
| `root` | `"C"` | Root note of the chord to build |
| `quality` | `""` (major) | Chord quality symbol |
| `durationTicks` | `4` (quarter) | Note duration for each stack note |

Quality symbols: `''` (maj), `'m'`, `'7'`, `'maj7'`, `'m7'`, `'dim'`, `'aug'`, `'sus2'`, `'sus4'`, `'m7b5'`, `'add9'`, `'maj9'`, `'6'`, `'m6'`, `'dim7'`, `'7sus4'`

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

### Import Rules (`lib/schema/rules/piano_roll_import_rules.dart`)

| Export | Description |
|---|---|
| `bestMidiInRangeForPitchClass(pc, lo, hi)` | Finds the MIDI note in range closest to range center |
| `buildChordStackMidis(root, quality, anchor, lo, hi)` | Builds a chord stack of MIDI notes from root + quality |
| `extractSnapshotImportMidis(snapshot, ...)` | Extracts MIDI notes from instrument snapshots for import |

Import rules handle `FretboardSnapshot` (tuning + fret → MIDI) and `PianoSnapshot` (direct MIDI). `PianoRollSnapshot` returns empty from this path — full roll load uses the dedicated save panel.

---

## PianoRollSnapshot (`lib/models/save_system.dart`)

First-class piano-roll persistence. Saves the full session for later resume.

### Persisted fields

| Field | Purpose |
|---|---|
| `tempo` | BPM |
| `key` | Key string (e.g. "C major") or `null` |
| `numerator` / `denominator` | Time signature (e.g. 4/4) |
| `totalMeasures` | Timeline length |
| `notes` | List of `{midiNote, startTick, durationTicks}` maps |
| `pitchRangeStart` / `pitchRangeEnd` | Visible MIDI window |
| `selectedColumnTick` | Detection column anchor |
| `snapTicks` | Snap granularity |
| `highlightedNotes` | Pitch-class list for scale highlighting |

### NOT persisted

| Field | Reason |
|---|---|
| `selectedNoteIds` | Transient note selection |
| Playback transport state | Not part of the session |
| `latestImportedRange` | Import navigation is ephemeral |

### Derivable fields

- `selectedNotes`: pitch classes at the saved `selectedColumnTick` (or all unique PCs if none)
- `pendingChord`: first detected chord from `selectedNotes`
- `pendingScale`: first detected scale from `selectedNotes`

### Save/load flow

```
PianoRollSavePanel → SaveBrowserPanel (filter: 'piano_roll')
  ├── Save: captureSnapshot() → PianoRollSnapshot → saveSystemProvider
  └── Load: loadSnapshot(snap) → pianoRollProvider.loadSnapshot()
```

The stack-import loader (`PianoRollSaveStackLoader`) ignores `PianoRollSnapshot` entries — use the dedicated save panel for full-roll persistence.

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
| `splitNote(id, tick)` | Split a note at a tick position into two notes |
| `addNoteStack(midiList, tick, duration)` | Add multiple notes at the same tick (chord) |
| `selectColumn(tick)` | Set `selectedColumnTick` for detection panel |
| `selectNote(id)` | Highlight a specific note |
| `setSelection(ids)` | Replace all selected note IDs at once |
| `setPitchRange(start, end)` | Shift the visible MIDI window |
| `shiftPitchRange(semitones)` | Scroll the pitch window ± semitones |
| `setActiveTool(tool)` | Switch between `draw` and `scissors` |
| `setSnapTicks(n)` | Set snap granularity (1, 2, 4, 8, 16, 32) |
| `setHighlightedNotes(pcs)` | Set pitch classes to highlight on the grid |
| `clearHighlightedNotes()` | Remove all highlights |
| `clearNotes()` | Remove all notes |
| `loadSnapshot(snap)` | Restore full session from a `PianoRollSnapshot` |
| `reset()` | Revert to default state |

### Composer store (`lib/store/piano_roll_composer_store.dart`)

Provider: `pianoRollComposerProvider` — shared composer state used by both V1 stack selector and V2 dock.

| Method | Description |
|---|---|
| `setRoot(root)` | Set root note (e.g. `"C"`, `"F#"`) |
| `setQuality(quality)` | Set chord quality symbol |
| `setDuration(ticks)` | Set note duration in ticks |
| `addStack()` | Build chord stack from current state and place on roll at `selectedColumnTick` |

---

## Hum to MIDI & Web Support

The Hum to MIDI recorder is **mobile-only**. On web the card shows a friendly "not supported" message with no record/stop controls.

### Web capability split

| Supported on web | NOT supported on web |
|---|---|
| Editor grid (all gestures) | Hum to MIDI capture |
| Playback transport | |
| Stack composer | |
| Save/load (PianoRollSnapshot) | |
| Stack import from Fretboard/Piano | |
| Detection panel | |
| Scale/highlight tools | |
| Keyboard shortcuts | |
| Ctrl+wheel / Alt+wheel zoom | |

### Recording on mobile

The full capture pipeline runs on mobile (iOS/Android):

| Stage | Code | Responsibility |
|---|---|---|
| 1. PCM capture & windowing | `lib/utils/mic_pitch_session.dart` | Buffer raw 16 kHz mono PCM, slide a 1024-sample window with 512-sample hop, emit ~31 `PitchFrame`/sec |
| 2. Pitch estimation | `lib/schema/rules/mono_pitch_rules.dart` (`estimateDominantFrequencyFromSamples`) | YIN with CMNDF, local-minimum descent, parabolic interpolation → `(frequencyHz, confidence)` |
| 3. Segmentation | `lib/schema/rules/mono_pitch_rules.dart` (`segmentStableNotes`) | Group consecutive same-MIDI frames into `DetectedMonoNote { startMs, endMs, midiNote, confidence }` with hysteresis |
| 4. Quantization & normalization | `quantizeNotesToTicks` + `normalizeQuantizedHumNotesMonophonically` | Map ms → ticks, snap, drop overlaps |

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

The Hum panel exposes a three-way `SegmentedButton` (Strict / Balanced / Forgiving). Each preset overrides three knobs:

| Preset | `switchFrames` | `deadbandCents` | `minNoteMs` |
|---|---|---|---|
| Strict | 2 | 0 | 80 |
| Balanced (default) | 4 | 35 | 120 |
| Forgiving | 7 | 60 | 180 |

The selector is disabled while recording or processing.

---

## Playback

Onset-sequencer transport that plays notes via the synthesised `NotePlayer` engine.

### Controls

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

## Layout: Landscape & Portrait

### V2 Landscape (width > 600 px)

- **Grid**: 3× flex on the left — primary editing surface.
- **Inspector rail**: 1× flex on the right — scrollable utility panel containing:
  - Composer (root / quality / duration pickers + "Add Stack" button)
  - Selection status
  - Edit & Pitch controls (tool + snap pills, pitch range ± octave)
  - Stack Selector
  - Scale picker
  - Detection panel (when column selected)
  - Hum Recorder (mobile) / unsupported card (web)
  - Save / Load panel
  - Import from Saves
- **Transport strip**: compact row with BPM, bar/beat readout, time signature, play/stop.

### V2 Portrait (width ≤ 600 px)

- **Transport strip**: same compact row.
- **Grid**: full-width primary surface.
- **Bottom dock**: collapsible expanders for each tool surface:
  - Quick action chips (Add Stack, Scale, Import, Record, Save, Compose)
  - Collapsible panels: Scale, Hum, Save, Import, Compose, Detection
- Only one panel expanded at a time (accordion-style).

### V1

- Vertical card layout composed in `lib/main.dart` — same provider-backed widgets.
- Toolbar above the grid, panels below.

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

**Pinch-to-zoom:**
- Tracked via raw `Listener` + `_pointers` map (pointer ID → position)
- When 2 fingers are down, horizontal spread scales `_cellW` (10–80 px), vertical spread scales `_rowH` (10–40 px)

**Wheel zoom (desktop/web):**
- `Ctrl`/`Cmd` + wheel: horizontal zoom (`_cellW` scaled by `delta * 0.5`, clamped 10–80)
- `Alt`/`Option` + wheel: vertical zoom (`_rowH` scaled by `delta * 0.5`, clamped 10–40)

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
| **Add note (1 tick)** | Tap on empty cell |
| **Add note (snap length)** | Double-tap on empty cell — inserts note at current snap duration |
| **Select note** | Tap on existing note (double-tap toggles multi-select) |
| **Move note** | Drag note body (horizontal = beat-snapped tick, vertical = semitone pitch) |
| **Resize note** | Drag right-edge handle (rightmost 16 px, snaps to 1/16th minimum) |
| **Split note** | Tap note with scissors tool active — splits at tapped position |
| **Delete note** | Long-press (500 ms) on note |
| **Delete selected notes** | `Delete` or `Backspace` key (desktop/web) |
| **Play / Stop** | `Space` key (desktop/web) |

**Beat snapping (move):**
- Beat ticks = 4 (quarter note) for 4/4; = 2 (eighth) for 4/8 time signatures
- Snaps: `round(rawTick / beatTicks) * beatTicks`

**Ruler interactions:**
- **Tap** anywhere on the ruler row to set `selectedColumnTick` → triggers detection panel
- **Drag** across the ruler to scrub `selectedColumnTick` continuously — updates the column marker and detection panel in real time

---

### `PianoRollToolbar`
Controls bar at the top of the screen (V1). V2 uses the inspector rail instead.

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
Chord root (12 chromatic) + quality (17 chords) + duration (1–4 beats) picker. Tapping "Add Stack" calls `addStack()` on the composer provider, which builds the chord via shared import rules and places notes at `selectedColumnTick` (or tick 0 if none). Notes are voice-led to the closest MIDI range within the current pitch window.

---

### `PianoRollSaveStackLoader`
Connects the save system to the piano roll. Lets the user browse saved progressions and place their notes into the timeline:

- **Folder browser** with breadcrumb navigation via `saveSystemProvider`
- **Placement mode toggle**: "Exact MIDI" (loads original MIDI values) vs "Pitch Class" (transposes to fit current pitch window using `bestMidiInRangeForPitchClass`)
- **"Add Stack" button**: calls `addNoteStack()` at current column
- **Filtered to Fretboard and Piano snapshots only** — `PianoRollSnapshot` entries are hidden from this loader (use the dedicated save panel for full-roll persistence)

Supports `FretboardSnapshot` (MIDI via tuning + string + fret) and `PianoSnapshot` (MIDI directly from selected keys).

---

### `PianoRollScalePicker`
Scale-highlight picker: choose a root note and scale type (major, minor, pentatonic major/minor, blues, chromatic). Highlights all matching pitch-class rows on the grid in teal. The selection is stored as `highlightedNotes` in `PianoRollState`.

---

### `PianoRollDetectionPanel`
Shows at selected column (`selectedColumnTick`). Uses shared exact-note detection APIs from `lib/utils/note_utils.dart`:

- `detectChordResultsFromExactNotes(...)` — chord matches
- `detectScaleResultsFromExactNotes(...)` — scale matches
- `formatChordSymbol(...)` / `formatScaleLabel(...)` — display labels

Displays:
- **Note chips** — one per active note. Each chip: tap to select, `×` button to delete.
- **Chords** — detected chord names, matching exact pitch-class set
- **Scales** — detected scale names, where all selected PCs are subset of scale
- **Delete Selected Note** — button present when a note is selected

---

### `PianoRollSavePanel`
First-class piano-roll save/load UI. Wraps `SaveBrowserPanel` with `instrumentFilter: 'piano_roll'`:

- **Save**: captures current `PianoRollState` as a `PianoRollSnapshot`
- **Load**: applies a snapshot to restore tempo, signature, notes, range, selection, snap, and highlights
- **Update**: overwrites an existing save with current state

Separate from the stack-import loader — this is for full piano roll sessions.

---

### `PianoRollHumRecorderPanel`
Mobile-only hum-to-MIDI recording panel. On web renders a static unsupported-state card. On mobile:

- Record / Stop buttons (disabled while processing)
- Live pitch readout during recording
- "Jump to latest" button after successful import
- Pitch sensitivity selector (Strict / Balanced / Forgiving)

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
PianoRollToolbar / V2 Inspector → pianoRollProvider.setTempo() / setTimeSignature() / …
                                │
                 PianoRollGrid repaints via ref.watch
                                │
     User taps cell → pianoRollProvider.toggleCellNote(midi, tick)
                                │
     User taps/drags ruler → pianoRollProvider.selectColumn(tick)
                                │
     PianoRollDetectionPanel shows chords/scales at that column
                                │
     Composer dock → pianoRollComposerProvider.setRoot/Quality/Duration
                  → addStack() → import_rules.buildChordStackMidis() → addNoteStack()
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
| `_PianoRollInfoTab` | Gesture + toolbar + panel + layout + shortcut + timeline-math entries |
| `_Section` | Section header (icon + uppercase label) + card container |
| `_Entry` | Icon badge + bold label + description text |
