# Songwriter

Writer is Muzician's section, chord, and lyric sketch. A song is a list of
**sections** (verse, chorus, … — free, optional labels); each section stacks
parallel **lanes** for harmony, saved or embedded voicings, drums, melody,
guitar strum, and audio.
Use Writer to shape the song's sections, then move to **Song** when you want to
arrange note, drum, or audio clips on a timeline.

Writer is the first workspace on a new install. After startup it restores the
last content workspace (Fretboard, Piano, Roll, Song, or Writer); opening
Settings does not change that preference.

---

## Data Model (`lib/models/songwriter.dart`)

| Type | Description |
|---|---|
| `SongwriterProjectSnapshot` | `InstrumentSnapshot` subtype (`type: 'songwriter'`) — `config` + ordered `sections`. |
| `SongwriterConfig` | `tempo`, `beatsPerBar`, `beatUnit`, optional `keyRoot` (pitch class) + `keyScaleName`. |
| `SongSection` | `id`, optional `label`, `lengthBars`, `order`, `repeat`, `lanes`. |
| `SongLane` | `id`, `kind` (`harmony`, `save`, `drum`, `melody`, `guitarStrum`, or `audio`), optional `label`, `order`, `repeat`, `blocks`; strum lanes may select an `anchorLaneId` harmony lane. |
| `SongBlock` | `id`, `startBar`, `spanBars` (+ `endBar` getter); a `saveId` live reference **or** an `embedded` snapshot; pattern lanes reference their pattern id; harmony extras: `chordSymbol`, `chordQuality`, `chordRootPc`, `chordNotes`, `romanNumeral`. |
| `NotePattern` / `GuitarStrumPattern` | Melody pitches, local ticks, durations, and optional millisecond onset offsets; strum direction events on a 16th-note grid. |

All types are immutable (`copyWith` / `toJson` / `fromJson`). A block resolves to a
snapshot as: `embedded` if set (Made Unique), else the live `SaveEntry` for `saveId`,
else broken (the referenced save was deleted).

## Rules (`lib/schema/rules/songwriter_rules.dart`)

| Function | Purpose |
|---|---|
| `romanNumeralFor(chordRootPc, quality, keyRootPc?, keyScaleName?)` | Diatonic Roman numeral for a chord in a key, or `null` (no key / non-diatonic). Cased by quality (`dim` → `vii°`, minor → lowercase). |
| `resolveSnapshotChord(snapshot)` | The chord a save block resolves to, for degree display: prefers the snapshot's explicit `pendingChord`, else detects one from `selectedNotes` via `detectFirstChord`. Returns a `ResolvedChord(rootPc, quality, symbol)` or `null`. |
| `saveBlockRomanNumeral(snapshot, keyRootPc?, keyScaleName?)` | Convenience: `resolveSnapshotChord` + `romanNumeralFor`. The Roman numeral a save block maps to in the key, or `null`. |
| `blocksOverlap(existing, candidate)` | Half-open overlap check within a lane; touching edges and gaps are allowed; self (same id) ignored. |
| `makeSection` / `makeLane` / `makeSaveBlock` / `makeHarmonyBlock` | UUID-stamped factories. |
| `flattenedBarCount(sections)` | Total bars after expanding section repeats (Σ `lengthBars * repeat`). |
| `laneNaturalLength(lane)` | Lane pattern length = max `block.endBar` (0 if empty). |
| `tileLaneBlocks(lane, sectionLengthBars)` | Expands a lane's blocks, tiling the pattern `lane.repeat` times from bar 0, clipped to the section length (a placement starting at/after the section end is dropped; a block spanning past the end is kept). |

### Repeat semantics

Playback flattening expands **section** repeats (whole section loops N×) and **lane**
repeats (the lane's block pattern tiles N× from bar 0, clipped to the section).

### Melody and guitar-strum lanes

Melody blocks open the existing Piano Roll editor. A pattern starts at local tick
zero at the block's left edge, loops from that origin through the block, and is
clipped at the block and section edges. Moving a block moves its playback
origin; resizing changes the playback window and number of pattern loops while
leaving its notes intact. Guitar-strum blocks use the same placement rules and
open a 16th-note grid with down, up, and off steps. A strum lane uses its
selected harmony lane as the chord source; with no explicit selection it
follows the primary harmony lane. If that lane has no chord at a step, the
strum is silent. Chord tones start 12 ms apart and each voice is gated for half
a beat. When a melody or strum voice reaches a pattern, block, or section edge,
its duration is shortened by its onset delay so its release stays inside the
clipped window.

All Writer and Song ticks share one tempo conversion: four ticks per quarter
note, or `60,000 / (tempo × 4)` milliseconds per tick. The time signature sets
the number of ticks in a bar, not the wall-clock duration of a tick. At 120 BPM
a 4/4 bar lasts 2 seconds and a 6/8 bar (12 ticks) lasts 1.5 seconds. Live
playback, Song audio clip placement/seek/length, and WAV note positions use the
same conversion. Sub-tick onset offsets and boundary duration trims are
preserved when importing or editing Song note patterns.

### Playback audio (`lib/schema/rules/songwriter_playback_rules.dart`)

`flattenPlaybackEvents(project, saves)` turns the whole project into a sorted,
tick-indexed event list the transport walks:

- **Harmony blocks** sound their chord as a per-bar stab (block start + every bar
  boundary inside the block, clipped to the section). Pitches come from
  `chordNotes` stacked ascending from octave 4, falling back to
  `chordRootPc` + `chordQuality` intervals. Silent blocks stay silent.
- **Save blocks** resolve their snapshot (embedded → live save → broken) and sound
  the voicing the same way: piano keys use `PianoCoordinate.midiNote`, fretboard
  cells map string+fret through the tuning. Broken blocks are silent.
- **Drum lane blocks** fire their referenced `DrumPattern` hits at native tick
  resolution, tiled across the block's bar span.
- **Melody lane blocks** play duration-aware notes, looping their pattern from
  local tick zero and clipping voices at the block/section boundary.
- **Guitar-strum blocks** resolve each down/up step against the selected harmony
  anchor (or primary harmony lane by default) and stay silent when that lane has
  no chord.
- The metronome click is unchanged and still gated by `settingsProvider.metronomeEnabled`.

Sinks are injectable providers (`songwriterNoteSinkProvider`,
`drumPatternPlaybackSinkProvider`, `songwriterMetronomeSinkProvider`) so tests can
capture events. The sheet UI highlights the active bar cell via
`songwriterActivePositionProvider` (global bar → section instance + local bar) and
auto-scrolls the active section into view.

### Drum pattern editor (`lib/features/song/drum_machine_editor.dart`)

Drum-lane blocks open the shared `DrumMachineEditorBody` — a step grid plus a
transport row. Beyond tapping individual steps it offers:

- **Clear all** — a transport button (with a confirm dialog) empties every lane.
- **Per-lane fills** — each lane's menu places hits *every N steps* (with a start
  offset) or by a *Euclidean* (Bjorklund) distribution, plus clear-lane. Pure
  generators live in `lib/schema/rules/drum_fill_rules.dart`.
- **Backing audition** (Songwriter only) — a **Backing** toggle loops the section's
  harmony chords under the pattern (loops at section length; the pattern tiles).
  Source: `sectionHarmonyLoop` in `songwriter_playback_rules.dart`.
- **Drum library** (Songwriter only) — a **presets** picker (16 built-in loops/fills
  in `lib/schema/rules/drum_presets.dart`) and **My loops** (custom loops saved as
  `DrumLoopSnapshot` through the save system; see `docs/save_system.md`). Applying a
  preset or a loop overwrites the current pattern in place, keeping its id so the
  referencing block stays linked.

The Songwriter drum sheet opts into the library and backing via `enableLibrary` /
`backing` on `DrumMachineEditorBody`; the Song feature embeds the same body without
them, so neither surface appears there.

## Store (`lib/store/songwriter_store.dart`)

Provider: `songwriterProvider` (`NotifierProvider<SongwriterNotifier, SongwriterProjectSnapshot>`).

| Method | Description |
|---|---|
| `newProject()` | Reset to empty + clear the session slot for the active project. |
| `setKey(root, scaleName)` / `setTempo(tempo)` | Config edits; `setKey` recomputes harmony-lane Roman numerals. |
| `addSection` / `addLane` / `addSaveBlock` / `addHarmonyBlock` / `removeBlock` | CRUD; block adds that overlap are ignored. |
| `addMelodyPattern` / `addGuitarStrumPattern`, their block adders and update methods | Create and edit looped note and strum patterns. |
| `setBlockPlacement(...)` | Move or resize a block while preserving its pattern link and data; rejects same-lane overlaps. |
| `insertInstrumentSelectionAtBar(...)` | Adds a detected chord to a harmony lane or embeds an exact Fretboard/Piano snapshot in a save lane; no library save is required. |
| `makeBlockUnique(...)` | Detach a block from its live save by embedding a snapshot. |
| `loadProject(project)` | Replace the whole project (named-save load). |

The notifier no longer exposes a public `hydrate()`. Instead, `build()` listens
to `saveSystemProvider.selectedProjectId` changes. When the project changes the
outgoing session is immediately persisted via `songwriterSessionsProvider.put`
and the incoming session is loaded via `.get`. If no session exists for the new
project, `_defaultFor(next)` creates one seeded from the folder's
`ProjectConfig`.

### Session auto-save

Sessions live in `@muzician/songwriter_sessions/v1` — a per-project map of
`Map<String, SongwriterProjectSnapshot>` keyed by project ID, debounced ~500 ms
(state captured at schedule time). On project switch the outgoing session is
persisted immediately and the incoming session is loaded from the map (or
seeded via `_defaultFor` when no session exists yet); leaving the project
clears to empty.

## Undo / Redo

Writer's overflow menu contains **Undo** and **Redo**. Both controls have
accessible button labels, can be reached with Tab, and activate with Enter or
Space. The active project keeps up to 50 prior immutable snapshots in memory,
including melody and strum
patterns and audio references. Text dialogs apply once when saved, confirmed
pickers and other dialogs commit once, and canceling discards a text draft;
drag and slider gestures commit once on release. A new edit after Undo clears
Redo. Switching projects, choosing
**New Writer Project**, or loading a named save/snapshot clears both history
branches. Deleted Writer audio blocks leave their source files in the local
repository so undo can restore their references. Delete snackbars call the same
history Undo command and close if a later edit changes the history revision.

## Scale degrees on bar cells

Both bar-cell kinds in the sheet grid (`songwriter_screen_sheet.dart`) show a
Roman numeral under their label when the chord is diatonic to the project key:

- **Harmony cells** render `block.chordSymbol` + `block.romanNumeral` (computed
  at block creation, recomputed by `setKey`).
- **Save cells** resolve their snapshot's chord via `saveBlockRomanNumeral`
  (`pendingChord`, else detected from the saved notes) and render it under the
  save name, keyed `saveRoman_<blockId>_<instance>`.

A non-diatonic chord (or no key) yields `null` and no numeral is shown — only
the symbol/name. Example in C major: a saved F-major voicing shows `IV`.

## Save / Load

Songwriter projects save as a `SaveEntry` (`InstrumentSnapshot` filter
`'songwriter'`) through the shared `SaveBrowserPanel`. The panel is scoped to
the selected project's folder via `rootFolderId: selected.id`, keeping the
save/load view confined to the project subtree. `songwriterCaptureForTest`
exposes the current snapshot for widget tests.

## Project Config

Writer uses `SaveSystemState.selectedProjectId` instead of the old
folder-name convention. When a real project is selected (kind `project`),
tempo and key chips in the header are locked; edit them through the project
config sheet. Instrument handoff asks the user to select a real project if
there is no project selected or Dump is active.

`projectConfigSyncProvider` (`lib/store/project_config_sync.dart`) pushes the
active project's tempo, meter, and key into the songwriter and Song stores
whenever a project is selected or its config changes. Changed master config
clears stale local undo history; an equal sync keeps current history. When
loading a project that has no session yet,
`_defaultFor` seeds a new `SongwriterProjectSnapshot` from the project folder's
`ProjectConfig` (name, tempo, beatsPerBar, beatUnit, keyRoot, keyScaleName).

Library-match scope is `getSavesInSubtree(folders, saves, selectedProjectId)`.

## Fretboard and Piano handoff

In either instrument's detection panel, choose **Add to Writer** and then
select a detected chord or the exact selected voicing. A chord is added to a
harmony lane with its symbol, root, quality, and selected pitch names. An exact
selection is stored as an embedded `InstrumentSnapshot` in a save lane, so the
transfer does not need a named library save. Choose a section and bar; if the
active project changes while the picker is open, Writer cancels the transfer
and explains why. Occupied bars are labeled for assistive technology and offer
replace-with-confirmation, choose-another-bar, or cancel.
Occupied bars include expanded lane repeats. Replacing one of those copies
updates the source block in place, preserving its ID, start, span, and repeat
offsets so every copy receives the new chord or snapshot together.

If no project is selected, the existing project picker opens before placement;
dismissing it leaves the instrument selection and Writer unchanged. If the
project has no Writer section, Writer offers to create its default eight-bar
section. The blank Writer state also has a visible **Start an 8-bar section**
action.
