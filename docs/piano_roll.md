# Piano Roll

A quantized, timeline-based note editor rendered with `CustomPainter`. Supports five tap-mode tools (Draw / Select / Scissors / Paint / Delete), explicit area selection via Select tool, marquee rectangle, drag-to-move (pitch + position), drag-to-resize, pinch-to-zoom (both axes), beat snapping, named stack buttons, live chord/scale detection per selected column, mobile-only Hum-to-MIDI recording, transport with optional metronome, and adaptive landscape/portrait layout.

---

## Selection Model

### Selected column vs selected notes

- **Selected column** (`selectedColumnTick`) is a timeline anchor used for detection and playback start.
- **Selected notes** (`selectedNoteIds`) are the notes currently targeted for edit actions.
- They often overlap in practice, but they are separate concepts.

### Selection workflows

- **Select tool (primary)**: Switch to `Select`, then drag a marquee rectangle across the grid. All notes the box touches (partial overlap) are selected. Each new marquee replaces the previous selection.
- **Double-tap (refinement)**: In any mode, double-tap a note to add or remove it from the current selection.
- **Tap a note**: solo-select that note (replace current note selection).
- **Select column (secondary shortcut)**: Use the selection action to select all notes active at `selectedColumnTick` — kept as a quick legacy alternative to the Select tool.
- **Move a selected group**: drag a selected note body to move all selected notes together.
- **Resize a selected group**: drag the right edge of a selected note to resize the whole current selection.
- **Split a selected group**: in scissors mode, split on a selected note to split the whole current selection at that tick.
- **Delete selected notes**: use the UI delete-selection action or `Delete` / `Backspace` (desktop/web).

---

## Architecture

`PianoRollScreenV2` is the only piano-roll shell. The previous V1 composition
inline in `lib/main.dart` (with `PianoRollPlaybackConfig` / `PianoRollEditConfig`
/ `PianoRollPitchConfig` panel cards) and the unused `piano_roll_screen_v2_mockup.dart`
have been removed. The Roll tab in the bottom navigation mounts
`PianoRollScreenV2` directly.

```
lib/
  models/
    piano_roll.dart                       ← canonical editor state
    piano_roll_composer.dart              ← quality/duration label maps (constants)
    piano_roll_stack_builder.dart         ← stack builder state model
    piano_roll_playback.dart              ← playback transport state
    hum_to_midi.dart                      ← hum recording types (PitchFrame, etc.)
    harmonic_analysis.dart                ← shared chord/scale detection types
    save_system.dart                      ← PianoRollSnapshot (persistence)
  schema/rules/
    piano_roll_rules.dart                 ← tick math, MIDI helpers, defaults
    piano_roll_import_rules.dart          ← stack building, snapshot-import mapping
    piano_roll_playback_rules.dart        ← playback sequencing
    piano_roll_stack_builder_rules.dart   ← canonical generation, recognition, retargeting
    mono_pitch_rules.dart                 ← hum-to-MIDI pitch estimation
  store/
    piano_roll_store.dart                 ← Riverpod NotifierProvider
    piano_roll_playback_store.dart        ← playback transport provider
    piano_roll_stack_builder_store.dart   ← builder state transitions
    hum_to_midi_store.dart                ← hum recording provider
    settings_store.dart                   ← metronome + app-wide preferences
  features/piano_roll/
    piano_roll_grid.dart                  ← main editor canvas (PianoRollGrid)
    piano_roll_screen_v2.dart             ← adaptive layout shell (Roll tab body)
    piano_roll_stack_builder.dart         ← unified Stack Builder (Canonico/Avanzato)
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
| `pianoRollStackBuilderProvider` | `PianoRollStackBuilderState` | Stack Builder: MIDI notes, duration, view mode, recognition |
| `pianoRollPlaybackProvider` | `PianoRollPlaybackState` | Playback transport: status, current tick, start point |
| `humToMidiProvider` | `HumToMidiState` | Mobile-only recording pipeline |
| `pianoRollPendingScaleProvider` | `({String root, String scaleName})?` | Temp scale preview (detection panel) |
| `pianoRollActiveScaleProvider` | `({String root, String scaleName})?` | Committed scale selection (persists across drawer) |
| `pianoRollScrollToTickProvider` | `int?` | One-shot scroll-to-tick signal |

---

## Data Model (`lib/models/piano_roll.dart`)

| Type | Description |
|---|---|
| `PianoRollNote` | One note: `id`, `midiNote`, `pitchClass`, `noteWithOctave`, `startTick`, `durationTicks` |
| `TimeSignature` | `beatsPerMeasure` + `beatUnit` (4 or 8) |
| `PianoRollConfig` | `tempo` (BPM), `key`, `timeSignature`, `totalMeasures` |
| `PianoRollTool` | Enum: `draw`, `select`, `scissors`, `paint`, `delete`. `draw` = add/move/resize · `select` = marquee area selection · `scissors` = split · `paint` = brush insert · `delete` = brush remove (see [Tool Modes](#tool-modes)) |
| `PianoRollImportedRange` | `startTick`, `endTickExclusive` — tracks latest hum import range |
| `PianoRollState` | Full state: `config`, `notes`, `pitchRangeStart`, `pitchRangeEnd`, `selectedColumnTick`, `selectedNoteIds`, `activeTool`, `snapTicks`, `highlightedNotes`, `latestImportedRange` |

### Stack Builder State (`lib/models/piano_roll_stack_builder.dart`)

| Field | Default | Purpose |
|---|---|---|
| `midiNotes` | `[60, 64, 67]` (C4, E4, G4) | Final stack notes (max 10) |
| `durationTicks` | `4` (quarter) | Note duration for each stack note |
| `activeView` | `canonical` | `canonical` or `advanced` editing mode |
| `recognition` | — | Derived: `recognizedRoot`, `recognizedQuality`, `recognizedInversionIndex`, `isCustomVoicing` |

### Composer State (`lib/models/piano_roll_composer.dart`)

Legacy state type kept for its quality/duration label maps. The store and widget have been replaced by the unified Stack Builder.

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
| `setSelection(ids)` | Replace current selection (used by Select tool marquee commit and double-tap refinement) |
| `clearSelection()` | Clear note selection without touching `selectedColumnTick` |
| `deleteSelectedNotes()` | Remove the whole current note selection |
| `selectNotesAtTick(tick)` | Select all notes active at a given tick and sync `selectedColumnTick` |
| `resizeNotesBatch(updates)` | Apply per-note duration updates to a selected group |
| `splitSelectedNotesAtTick(tick)` | Split every selected note that spans the given absolute tick |
| `setPitchRange(start, end)` | Shift the visible MIDI window |
| `shiftPitchRange(semitones)` | Scroll the pitch window ± semitones |
| `setActiveTool(tool)` | Switch between `draw` / `select` / `scissors` / `paint` / `delete` |
| `setSnapTicks(n)` | Set snap granularity (1, 2, 4, 8, 16, 32) |
| `setHighlightedNotes(pcs)` | Set pitch classes to highlight on the grid |
| `clearHighlightedNotes()` | Remove all highlights |
| `clearNotes()` | Remove all notes |
| `loadSnapshot(snap)` | Restore full session from a `PianoRollSnapshot` |
| `reset()` | Revert to default state |

### Stack builder store (`lib/store/piano_roll_stack_builder_store.dart`)

Provider: `pianoRollStackBuilderProvider` — single source of truth for the unified Stack Builder widget. Replaces the old `pianoRollComposerProvider`.

| Method | Description |
|---|---|
| `switchView(view)` | Toggle between Canonico / Avanzato (preserves notes) |
| `setCanonicalRoot(root)` | Retarget stack to new root via rules layer |
| `setCanonicalQuality(quality)` | Retarget stack to new quality |
| `setCanonicalInversion(index)` | Change inversion (0=Root, 1=1st, 2=2nd, 3=3rd) |
| `setDurationTicks(ticks)` | Update note duration |
| `addAbsoluteNote(midi)` | Add a MIDI note to the stack (advanced view) |
| `duplicateNoteAt(index)` | Duplicate note at index (advanced view) |
| `removeNoteAt(index)` | Remove note at index (advanced view) |
| `reorderNotes(oldIdx, newIdx)` | Reorder notes (advanced view) |
| `replaceNoteAt(index, midi)` | Replace a note (advanced view) |
| `insertDegreeShortcut(degree)` | Insert note by chord degree number (1–9) |
| `addStack()` | Insert current builder notes into the piano roll at `selectedColumnTick` |

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

### Transport bar

| Control | Action |
|---|---|
| **⏮ Rewind** | Stops playback and resets the playhead by calling `selectColumn(0)`. |
| **▶ / ⏸ Play/Pause** | `startPlayback()` / `stopPlayback()` on `pianoRollPlaybackProvider`. |
| **⏹ Stop** | Stops playback and clears the column selection (`selectColumn(null)`). |
| **BPM readout** | Tap opens `_BpmSheet`: numeric `TextField` + ±1/±10 step buttons + slider (40–300). Vertical-drag on the readout still fine-tunes ±1 BPM per 4 px. |
| **BAR readout** | Live tick → bar/beat display (`1.2.0` style). |
| **SIG readout** | Tap opens a picker sheet with `2/4`, `3/4`, `4/4`, `5/4`, `6/8`, `7/8`, `12/8` → `setTimeSignature(...)`. |

### Playback semantics

| Condition | Behavior |
|---|---|
| Idle + column selected | Plays from that tick to the end of the timeline. |
| Idle + no column selected | Plays from tick 0 to the end of the timeline. |
| Playing | `currentTick` advances tick-by-tick at `60000 / tempo / ticksPerQuarter` ms each. |
| Hum is recording / processing | Playback button is hidden; `message = "Playback unavailable while humming"`. |
| No notes anywhere at/after start + metronome off | `message = "Nothing to play from the selected column"`. |
| No notes anywhere at/after start + metronome on | Loop runs anyway — metronome alone is valid playback. |

### Metronome

Configurable via the Roll Settings sheet ([Settings](#roll-settings)). When `AppSettings.metronomeEnabled` is `true` the playback loop emits a click on every beat boundary (`tick % beatTicks == 0`) — accented click on the downbeat (`tick % measureTicks == 0`), softer click on the other beats. Beat length follows the time signature: `beatTicks = 4` for `x/4` signatures, `2` for `x/8`.

| Layer | Code |
|---|---|
| Click synthesis (2000 Hz accent / 1500 Hz weak, ~35 ms sine with anti-pop fade-in) | `NotePlayer.playClick({accent})` |
| Cache keys (negative range so they cannot collide with MIDI note caches) | `-1` (accent) / `-2` (weak) |
| Click sink (injectable for tests) | `pianoRollMetronomeSinkProvider` |
| Wire-in | `PianoRollPlaybackNotifier.startPlayback()` |

### Scope

| In scope | Out of scope |
|---|---|
| Play / Pause / Stop / Rewind | Loop / cycle markers |
| Start from selected column | Pause + resume from the same tick |
| Run to end of timeline | Animated playhead / auto-scroll |
| Tap-to-edit BPM and time signature | Multi-track / velocity editing |
| Metronome (accent on downbeat) | MIDI export |
| Onset-only sequencing (duration-accurate note-offs deferred) | Count-in / pre-roll |
| Metronome-only playback when no notes | Pitch-range auto-growth |

---

## Roll Settings

Per-page settings sheet opened via the gear icon in the `CompactAppBar`. Currently exposes a single toggle:

| Setting | Persistence | Default | Effect |
|---|---|---|---|
| `metronomeEnabled` | `SharedPreferences` (via `AppSettings`) | `true` | Plays a click on every beat during playback (accent on downbeat). |

The sheet lives in `lib/features/piano_roll/piano_roll_screen_v2.dart` (`_SettingsSheet`); the persisted field is `AppSettings.metronomeEnabled`; the mutator is `SettingsNotifier.setMetronomeEnabled(bool)`. Test helpers should override the setting via direct state assignment to bypass `SharedPreferences` — see `test/store/piano_roll_playback_store_test.dart` for the pattern.

---

## Tool Modes

`PianoRollState.activeTool` drives the grid's tap behaviour. All five modes are reachable from the portrait action-bar tool segment (icon-only segmented control) or directly via `pianoRollProvider.setActiveTool(...)`.

| Tool | Icon | Tap on empty cell | Tap on note | Drag |
|---|---|---|---|---|
| `draw` | ✏ `edit_rounded` | Insert 1-tick note (or snap-length on double-tap). | Select / multi-select (double-tap). Long-press (500 ms) deletes. | Move / resize the note. |
| `select` | Ⓢ `select_all_rounded` | Draws a marquee to select notes in area. | Double-tap to add/remove from selection. | Draws marquee; on release, all intersected notes are selected. |
| `scissors` | ✂ `content_cut_rounded` | No-op. | Split the note at the tap position. | No-op (no move/resize in this mode). |
| `paint` | 🖌 `brush_rounded` | Insert a note at `snapTicks` duration. | No-op (cell already occupied). | Continues inserting notes along the drag path, snap-aligned; cells already occupied are skipped. |
| `delete` | 🗑 `delete_outline_rounded` | No-op. | Remove the note. | Removes every note touched along the drag path. |

### Implementation

| Layer | File |
|---|---|
| Enum | `lib/models/piano_roll.dart` |
| Tap/drag wiring | `lib/features/piano_roll/piano_roll_grid.dart` (`_DragMode.paintBrush`, `_DragMode.deleteBrush`, `_paintAt`, `_deleteAt`, brushed-cell/id sets) |
| Tool segmented control (portrait action bar) | `lib/features/piano_roll/piano_roll_screen_v2.dart` (`_ToolModeSegment`, `_ToolSegmentItem`) |

### Continuous-tool guarantees

`paint` and `delete` are **continuous tools** — they act on `onPointerDown` and keep acting on every `onPointerMove`, bypassing the 8 px slop gate, the long-press timer, and the grid-scroll fallback. Each drag tracks already-touched cells (paint) or note ids (delete) so dwelling on the same target never produces duplicate state changes.

### Cursor hover (desktop)

| Tool | Empty cell | Over a note |
|---|---|---|
| `draw` | basic | move / resize-right (last 16 px) |
| `select` | crosshair | basic (double-tap to add/remove) |
| `scissors` | basic | precise (with scissors x-position painted) |
| `paint` | precise | precise |
| `delete` | forbidden | precise |

---

## Layout: Landscape & Portrait

### Landscape (width > 600 px)

- **Grid**: 3× flex on the left — primary editing surface.
- **Inspector rail**: 1× flex on the right — scrollable utility panel containing:
  - Stack Builder (unified Canonico/Avanzato chord stack editor)
  - Selection status
  - Edit & Pitch controls (tool + snap pills, pitch range ± octave)
  - Scale picker
  - Detection panel (when column selected)
  - Hum Recorder (mobile) / unsupported card (web)
  - Save / Load panel
  - Import from Saves
- **Transport strip**: compact row with BPM, bar/beat readout, time signature, play/stop.

### Portrait (width ≤ 600 px)

The portrait shell is minimal-by-design: the grid is `Expanded` and the chrome below it is **fixed-height**, so opening a panel never resizes the grid. Every utility surface opens as a modal bottom sheet on top of the grid via `showWidgetSheet(...)` rather than as an inline expander.

- **`CompactAppBar`**: `× Roll · {chip}`, with a gear icon (`Icons.settings_outlined`) on the right that opens the Roll Settings sheet.
- **`_TransportStrip`**: transport buttons + BPM / BAR / SIG readouts (see [Playback](#playback)).
- **Grid**: full-width `PianoRollGrid` inside `Expanded` — never shrinks.
- **`_PortraitActionBar`** (3 fixed rows under the grid):
  1. `_SelectionStatus(compact)` (left, ellipsis-safe) + `_ToolModeSegment` (right, fixed 4-icon segmented control).
  2. `Stack Builder` · `Scale` · `Detect`.
  3. `Record` · `Save` · `Import`.

#### Bottom sheets

Each chip opens the corresponding panel as a glass `showWidgetSheet`:

| Chip | Sheet body |
|---|---|
| `Stack Builder` | `PianoRollStackBuilder` — unified Canonico/Avanzato chord stack editor |
| `Scale` | `PianoRollScalePicker` |
| `Detect` | `PianoRollDetectionPanel` (chip disabled when no column is selected) |
| `Record` | `PianoRollHumRecorderPanel` |
| `Save` | `PianoRollSavePanel` |
| `Import` | `PianoRollSaveStackLoader` |
| Gear icon | `_SettingsSheet` (see [Roll Settings](#roll-settings)) |

---

## Widgets

### `PianoRollGrid`
The core editor. Three `CustomPainter` layers rendered inside synchronized scroll views:

| Painter | Draws |
|---|---|
| `_PitchSidebarPainter` | MIDI note labels (all white + black keys), black-key row shading |
| `_RulerPainter` | Measure numbers, beat dots, tick marks, selected-column marker |
| `_GridPainter` | Row backgrounds, grid lines, column highlight, note rectangles, resize handles |

The select marquee overlay is rendered as a `Positioned` widget in the grid `Stack` with Key `piano-roll-select-marquee`. It appears as a blue rectangle with translucent fill and a high-contrast border only during an active `Select`-tool drag.

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

The state machine below applies to `draw`, `select`, and `scissors`. `paint` and `delete` are continuous tools and short-circuit the slop/long-press logic — see [Tool Modes](#tool-modes).

| Event | Single finger (`draw` / `select` / `scissors`) | Two fingers |
|---|---|---|
| `onPointerDown` | Record hit, start 500 ms long-press timer (skipped for `select`) | Enter pinch mode, record initial spread |
| `onPointerMove` (< 8 px) | No-op (inside slop threshold); `select` also no-op until slop is exceeded | Scale `_cellW` / `_rowH` |
| `onPointerMove` (≥ 8 px) | `draw`/`scissors`: if on note → move/resize; else → scroll. `select`: draw marquee rectangle, intersect notes | Scale `_cellW` / `_rowH` |
| `onPointerUp` | `draw`/`scissors`: if no movement → tap (add/select/split); if timer fired → already deleted. `select`: commit marquee selection via `setSelection(ids)` | Exit pinch if last finger lifted |

**Note interactions:**

Tap behaviour depends on the active tool — the table below covers `draw`; see [Tool Modes](#tool-modes) for the full per-tool matrix.

| Action | How to trigger |
|---|---|
| **Add note (1 tick)** | `draw` tool: tap on empty cell |
| **Add note (snap length)** | `draw` tool: double-tap on empty cell — inserts note at current snap duration |
| **Solo-select note + audition pitch** | `draw` tool: tap on existing note |
| **Add/remove note in selection** | `draw` tool: double-tap on existing note |
| **Select notes at current column** | Selection action: use **Multi-select** in the Selection area (landscape) or the top-left selection icon in the portrait action bar to select all notes active at `selectedColumnTick` |
| **Move selected group** | `draw` tool: drag body of any selected note (horizontal = beat-snapped tick, vertical = semitone pitch) |
| **Resize selected group** | `draw` tool: drag the right-edge handle of a selected note (rightmost 16 px, snaps to 1/16th minimum) |
| **Split selected group** | `scissors` tool: tap a selected note — splits the current selection at the tapped position |
| **Paint notes along a path** | `paint` tool: drag — inserts snap-length notes on every cell touched (skips occupied cells) |
| **Delete a note by tap** | `delete` tool: tap on the note |
| **Sweep-delete** | `delete` tool: drag — removes every note touched |
| **Long-press delete** | `draw` tool: long-press (500 ms) on note |
| **Delete selected notes** | UI delete-selection action, or `Delete` / `Backspace` key (desktop/web) |
| **Play / Stop** | `Space` key (desktop/web) |

### Explicit selection actions

| Action | How to trigger |
|---|---|
| **Select tool** | Switch to `Select`, then drag a box across the grid. All notes the box touches are selected. |
| **Replace selection** | Every new marquee replaces the previous selection. |
| **Refine selection** | Double-tap a note to add or remove it from the current selection. |
| **Select column** | Secondary shortcut — selects all notes active at the current column tick. |
| **Edit after selection** | Switch back to `Draw` to move/resize, or `Scissors` to split the selected group. |

**Beat snapping (move):**
- Beat ticks = 4 (quarter note) for 4/4; = 2 (eighth) for 4/8 time signatures
- Snaps: `round(rawTick / beatTicks) * beatTicks`

**Ruler interactions:**
- **Tap** anywhere on the ruler row to set `selectedColumnTick` → triggers detection panel
- **Drag** across the ruler to scrub `selectedColumnTick` continuously — updates the column marker and detection panel in real time

---

### `PianoRollStackBuilder`
Unified chord stack editor replacing the old `Stack Selector` and `Stack Composer` flows. Provides two views on the same final note list:

- **Canonico**: Quick path — pick root, quality (17 types), inversion, and duration. Changes transform the current stack.
- **Avanzato**: Lossless editor — add, edit, remove, and reorder individual notes; insert by note + octave picker or chord degree shortcut (1–9). Hard cap at 10 notes. Exact duplicates (e.g. `C4` + `C4`) are rejected; octave doublings (e.g. `C3` + `C4`) are allowed.

The builder recognises custom voicings (e.g. `G2 C3 E3 G3 C4` displays as "C maj • 2nd inv • Custom voicing"). Unrecognised stacks show "Unrecognized custom stack". Canonical and advanced views remain synchronised — switching tabs never resets the stack. In portrait, tapping **Add Stack** inserts the stack at the current column and dismisses the drawer immediately.

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

When a scale is active:
- existing out-of-scale notes are checked before applying the scale and can be removed via the confirmation flow
- new notes, pasted stacks, and pitch moves that would land outside the active scale are blocked
- the active scale pill can be cleared back to `null` with `✕` to return to full chromatic note entry

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
Transport strip / inspector rail → pianoRollProvider.setTempo() / setTimeSignature() / …
                                │
                 PianoRollGrid repaints via ref.watch
                                │
     User taps cell → pianoRollProvider.toggleCellNote(midi, tick)
                                │
     User taps/drags ruler → pianoRollProvider.selectColumn(tick)
                                │
     PianoRollDetectionPanel shows chords/scales at that column
                                │
     User switches to Select → drag marquee → _onPointerUp
                                │       → pianoRollProvider.setSelection(ids)
                                │
     User switches to Draw/Scissors → edits the selected group
                                │
     Stack Builder → pianoRollStackBuilderProvider.setCanonicalRoot/Quality/Inversion
                  → addStack() → addNoteStack(current builder notes)
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

---

## Standalone Roll vs. Song Note Editor

The standalone `Roll` tab (`PianoRollScreenV2`) uses `pianoRollProvider` with the default container.
The Song workspace uses an **isolated `ProviderContainer`** seeded from a `NotePattern` when editing note clips.
Both use `PianoRollGrid` and `PianoRollDetectionPanel`, but the provider scope keeps their states independent.
Closing the Song note editor writes a converted `NotePattern` back through `applyNotePattern` on the Song store.
This ensures that editing a Song pattern does not mutate the standalone Roll session.
