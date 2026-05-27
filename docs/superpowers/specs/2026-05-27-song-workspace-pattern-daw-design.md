# Song Workspace, Pattern Tracks, And Drum Machine Design

Date: 2026-05-27
Status: Draft approved in chat, written for repo review
Scope: First implementation of a separate Song workspace with track-based arrangement, reusable note and drum patterns, a pattern-based note editor that reuses piano-roll infrastructure, and first-class song persistence

## Goal

Add a new `Song` workspace that behaves like a small DAW arranger:

- a dedicated bottom-navigation tab separate from the standalone `Roll`
- multiple note and drum tracks arranged on a shared clip timeline
- reusable patterns referenced by clip instances
- a note-pattern editor built from the existing piano-roll stack without coupling Song state to the standalone Roll session
- a drum-machine editor based on a step sequencer
- first-class persistence for complete songs, plus import from existing `Piano Roll`, `Piano`, and `Fretboard` saves

The first version should be structurally solid before it is feature-rich. Clean domain boundaries, deterministic playback, and predictable save/load behavior matter more than advanced DAW conveniences.

## Problem Statement

The current repo has a strong single-pattern piano-roll editor, but it does not yet have a real arrangement layer:

1. `PianoRollState` models one editable timeline, not multiple tracks or clip instances.
2. `piano_roll_playback_store.dart` schedules onset events from one note list only; it cannot expand clips across multiple tracks or apply track-level mute/solo.
3. The shared save system can already store `PianoRollSnapshot`, but it has no concept of a full Song project.
4. There is no drum-machine model, no track domain, and no clip/pattern distinction.
5. The bottom navigation exposes `Fretboard`, `Piano`, `Roll`, and `Settings`, so there is no workspace-level entry point for arrangement.

Trying to stretch the current Roll into a full arranger would overburden the existing piano-roll store with responsibilities it should not own:

- track management
- pattern reuse and `Make unique`
- clip placement and overlap constraints
- song-level transport
- drum-machine editing and playback
- whole-song persistence

The correct path is a new canonical Song domain above the existing instrument editors.

## Confirmed Product Decisions

These decisions were explicitly confirmed before writing this spec and should stay fixed during implementation unless a blocker appears:

- Add a new bottom-navigation tab `Song`.
- Keep the standalone `Roll` tab available.
- The Song workspace uses an arranger-style clip timeline.
- `tempo`, `time signature`, and `total measures` are global at Song scope in v1.
- The Song supports two track types:
  - `note`
  - `drum`
- Drum tracks are edited with a classic step sequencer, not a piano-roll percussion editor.
- Track controls in v1 are:
  - `mute`
  - `solo`
  - `rename`
  - `duplicate`
  - `delete`
- `volume` and `pan` are out of scope for v1.
- Song clips are instances of reusable patterns, not independent region copies.
- Editing a shared pattern updates every clip instance that references it.
- `Make unique` is the explicit escape hatch that clones a pattern and relinks only the active clip.
- Song import in v1 supports:
  - `PianoRollSnapshot` -> note pattern
  - `PianoSnapshot` -> note pattern
  - `FretboardSnapshot` -> note pattern
- Song save/load is first-class and stores the entire project.
- The first arranger interaction set is intentionally narrow:
  - create clip
  - move clip
  - duplicate clip
  - delete clip
  - open clip editor
- Clip free-resize, time-stretching, overlap-tolerant lanes, cross-track drag-conversion, automation, looping, mixer controls, and pattern folders are out of scope for v1.

## Current Repo Audit

### Strong foundations we should reuse

- `lib/models/piano_roll.dart`
  already defines a clear quantized note/timeline model and `TimeSignature`.
- `lib/store/piano_roll_store.dart`
  already exposes most note-editing mutations needed for a note-pattern editor.
- `lib/store/piano_roll_playback_store.dart`
  already demonstrates the transport timing model and metronome integration.
- `lib/features/piano_roll/piano_roll_grid.dart`
  is already the richest interaction surface in the repo and should stay the canonical note-grid renderer.
- `lib/models/save_system.dart`
  already includes `PianoRollSnapshot` in code, even though some older docs still lag behind.
- `lib/schema/rules/piano_roll_import_rules.dart`
  already solves exact MIDI extraction from `PianoSnapshot` and `FretboardSnapshot`.

### Constraints that matter for the Song design

- `PianoRollState` contains single-editor concerns such as:
  - `selectedColumnTick`
  - `selectedNoteIds`
  - `highlightedNotes`
  - `latestImportedRange`
  These are valuable for editing one pattern, but they do not belong in the Song arrangement model.
- `NotePlayer` currently knows how to play:
  - short pitched notes
  - metronome clicks
  It does not yet have drum voices.
- `main.dart` has no `Song` tab and still treats `Roll` as the top-level arrangement-adjacent surface.

## User Experience

### 1. Song tab

The new `Song` tab is the arranger workspace.

Top-level structure:

- gradient shell consistent with the app
- top transport and global project controls
- scrollable multi-track arranger
- per-track header controls

Core top controls:

- `Rewind`
- `Play/Pause`
- `BPM`
- `Time Signature`
- `Measures`
- `Add Track`
- `Save / Load`

### 2. Track creation

`Add Track` offers two choices:

- `Note Track`
- `Drum Track`

Every track row has:

- name
- type badge
- mute
- solo
- overflow menu with:
  - rename
  - duplicate
  - delete

Track duplication clones the track layout and creates new clip instances that point to the same underlying patterns as the original track. Duplicating a track must not eagerly clone patterns.

### 3. Clip creation

Note tracks can create clips from:

- `New empty pattern`
- `Import from Piano Roll save`
- `Import from Piano save`
- `Import from Fretboard save`

Drum tracks can create clips from:

- `New empty drum pattern`

Default empty-pattern lengths:

- note pattern: 1 measure
- drum pattern: 1 measure

Clip length always equals the current pattern length. Clips do not have independent trim handles in v1.

### 4. Note-pattern editing

Opening a note clip launches a pattern editor that reuses piano-roll infrastructure, but in an isolated Song-specific editing session.

The editor must show:

- pattern name
- `Used in N clips`
- `Make unique`
- note-grid editing controls
- playback transport scoped to that pattern only

Important behavior:

- editing the pattern updates every clip instance that references it
- `Make unique` clones the pattern first, relinks the active clip only, then keeps editing the clone
- this editor must not mutate the standalone Roll session state

### 5. Drum-pattern editing

Opening a drum clip launches a step-sequencer editor.

The editor uses:

- fixed drum lanes
- columns aligned to Song ticks
- one cell per lane/tick

Initial fixed lanes:

- `kick`
- `snare`
- `closedHiHat`
- `openHiHat`
- `clap`
- `lowTom`
- `highTom`
- `crash`

The drum editor must also show:

- pattern name
- `Used in N clips`
- `Make unique`

### 6. Pattern reuse semantics

The Song workspace behaves like a pattern-based DAW, not a region-copy DAW.

Rules:

- a clip instance references a pattern ID
- multiple clips may reference the same pattern
- editing one shared pattern updates every instance
- `Make unique` clones the pattern and reassigns only the active clip

### 7. Save / load

The Song workspace must save and load as a complete project through the shared save browser.

A saved Song project contains:

- global config
- all tracks
- all clip instances
- all note patterns
- all drum patterns

It does not persist transient workspace state such as open panels, selected arranger clip, or current playback progress.

## Domain Model

Canonical Song models should live in `lib/models/song_project.dart`.

### SongProjectConfig

Fields:

- `tempo`
- `timeSignature`
- `totalMeasures`

This config governs:

- arranger grid
- note-pattern editor measure math
- drum-machine editor step count
- Song transport timing

### SongTrackType

Enum values:

- `note`
- `drum`

### SongTrack

Fields:

- `id`
- `name`
- `type`
- `order`
- `isMuted`
- `isSolo`

### SongClipInstance

Fields:

- `id`
- `trackId`
- `patternId`
- `patternType`
- `startTick`

Derived:

- `endTickExclusive` from pattern length

### NotePatternNote

Fields:

- `id`
- `midiNote`
- `startTick`
- `durationTicks`

`pitchClass` and `noteWithOctave` stay derived when bridging into piano-roll editor state.

### NotePattern

Fields:

- `id`
- `name`
- `lengthTicks`
- `notes`
- `pitchRangeStart`
- `pitchRangeEnd`
- `snapTicks`
- `highlightedNotes`

The last four fields deliberately mirror useful piano-roll editing context so reopening the pattern feels stable.

### DrumLaneId

Enum values:

- `kick`
- `snare`
- `closedHiHat`
- `openHiHat`
- `clap`
- `lowTom`
- `highTom`
- `crash`

### DrumLaneSequence

Fields:

- `laneId`
- `activeTicks`

`activeTicks` uses Song tick positions so the drum machine shares the same time grid as the note editor.

### DrumPattern

Fields:

- `id`
- `name`
- `lengthTicks`
- `lanes`

### SongProject

Fields:

- `config`
- `tracks`
- `clips`
- `notePatterns`
- `drumPatterns`

## Architecture

### 1. Keep Song state separate from PianoRollState

`SongProject` is the canonical arrangement model.

`PianoRollState` remains a pattern editor state, not a Song state.

This keeps concerns clean:

- Song owns tracks, clips, patterns, mute/solo, and project persistence
- Piano Roll owns note-grid editing behavior inside a scoped pattern editor

### 2. Use small companion providers for Song UI state

`songProjectProvider` should stay canonical and persistable.

Transient Song UI state should stay outside the canonical project model:

- selected track ID
- selected clip ID
- open editor route
- temporary import dialog state

Recommended supporting providers:

- `songSelectedTrackIdProvider`
- `songSelectedClipIdProvider`
- optional local editor-session state inside specific editor widgets

### 3. Use a pattern-bridge layer for note editing

Create a dedicated bridge rule layer that converts:

- `NotePattern` -> `PianoRollState`
- `PianoRollState` -> `NotePattern`

This bridge lets Song reuse `PianoRollGrid` and related panels without reusing the standalone Roll’s persisted session.

The note-pattern editor should run in an isolated provider container seeded from the active pattern. Saving the editor writes a converted `NotePattern` back through the Song store.

### 4. Validate pattern edits against all linked clip instances

Because clip length equals pattern length, a pattern-length change affects every instance of that pattern.

Rules:

- before saving an edited note or drum pattern, compute the resulting clip spans for every linked instance
- if any updated span would overlap another clip on the same track, reject the save
- keep the editor open and surface a clear blocking message

This is stricter than a DAW with overlap lanes, but it matches the v1 rule that same-track clip overlap is not allowed.

### 5. Centralize arrangement rules in pure helpers

Create `lib/schema/rules/song_rules.dart` for deterministic helpers such as:

- `songTotalTicks(config)`
- `ensureProjectCoversTick(project, endTickExclusive)`
- `canPlaceClipOnTrack(project, candidateClip, patternLengthTicks, {excludingClipId})`
- `firstAvailableDuplicateStartTick(...)`
- `duplicateTrackWithSharedPatterns(...)`
- `clonePatternForClip(...)`
- `linkedClipCount(project, patternId)`
- `validatePatternResizeAcrossInstances(...)`

This logic must stay out of widgets and out of ad hoc store branching.

### 6. Reuse existing snapshot mapping for imports

Song import should use a dedicated `song_import_rules.dart`, but it should reuse the already-shared `piano_roll_import_rules.dart` where appropriate.

Behavior:

- `PianoRollSnapshot`
  - import exact notes
  - derive pattern length from furthest note end, rounded up to at least one Song measure
  - ignore source tempo and source signature for Song config
- `PianoSnapshot`
  - create a chord-like note pattern at tick `0`
  - use exact MIDI keys from the snapshot
  - use an explicit or default initial duration
- `FretboardSnapshot`
  - create a chord-like note pattern at tick `0`
  - use exact tuning/string/fret to derive MIDI
  - use an explicit or default initial duration

### 7. Add first-class Song playback

The Song transport must be separate from the standalone piano-roll transport.

Required responsibilities:

- expand clip instances into absolute-tick note/drum events
- resolve shared patterns by ID
- apply mute/solo before scheduling
- play note events and drum events on the same transport tick
- optionally drive the same metronome pattern used by the piano roll

The transport must snapshot Song state at playback start so mid-run edits do not affect an active playback pass.

### 8. Extend NotePlayer with drum voices

`NotePlayer` should gain simple cross-platform synthesized drum voices rather than introducing an external sample pack in v1.

Recommended mapping:

- `kick`: low decaying sine burst
- `snare`: filtered noise burst
- `closedHiHat`: short bright noise
- `openHiHat`: longer bright noise
- `clap`: multi-burst noise envelope
- `lowTom` / `highTom`: short tuned percussive tones
- `crash`: longer bright noisy burst

This preserves the repo’s current pure-generated audio strategy.

## Rule Details

### Clip placement

- all clip starts are snapped to Song ticks
- same-track clip overlap is invalid
- invalid create/move operations are rejected by the store
- the UI should snap back to the last valid state when a move is rejected

### Auto-expand

- if a create, move, duplicate, or imported clip would extend beyond the current Song length, the Song auto-expands to the minimum number of measures required
- Song expansion is bounded by the same 32-measure ceiling already used by the piano-roll store unless a later approved task revises that limit consistently

### Clip duplication

- duplicate clip keeps the same `patternId`
- duplicate clip is placed at the first same-track non-overlapping slot at or after the source clip’s end tick

### Track duplication

- duplicate track creates a new track ID and cloned clip-instance IDs
- duplicated track clip instances keep the same `patternId`s as the source track

### Pattern cleanup

- deleting a clip removes only the clip instance
- if a pattern becomes unreferenced after a delete, the store may clean it up immediately

### Pattern counts

- `Used in N clips` counts clip instances across the whole Song, not just the current track

## Persistence

Add `SongProjectSnapshot` as a new `InstrumentSnapshot` subtype in `lib/models/save_system.dart`.

Recommended shape:

- `instrument = 'song'`
- `type = 'song'`
- `project = SongProject`

Derived snapshot metadata:

- `selectedNotes`
  - return unique pitch classes across all note patterns
- `pendingChord`
  - return `null`
- `pendingScale`
  - return `null`

`SaveBrowserPanel` should special-case Song preview rows to show counts such as:

- `3 tracks`
- `9 clips`
- `5 patterns`

instead of trying to render Song saves as chord-detection summaries.

## File Structure

### Create

- `lib/models/song_project.dart`
- `lib/models/song_playback.dart`
- `lib/schema/rules/song_rules.dart`
- `lib/schema/rules/song_import_rules.dart`
- `lib/schema/rules/song_playback_rules.dart`
- `lib/schema/rules/song_pattern_bridge_rules.dart`
- `lib/store/song_project_store.dart`
- `lib/store/song_playback_store.dart`
- `lib/features/song/song_feature.dart`
- `lib/features/song/song_screen.dart`
- `lib/features/song/song_arranger_timeline.dart`
- `lib/features/song/song_track_header.dart`
- `lib/features/song/song_save_panel.dart`
- `lib/features/song/song_pattern_editor_launcher.dart`
- `lib/features/song/song_note_pattern_editor.dart`
- `lib/features/song/drum_machine_editor.dart`
- `test/schema/rules/song_rules_test.dart`
- `test/schema/rules/song_import_rules_test.dart`
- `test/schema/rules/song_playback_rules_test.dart`
- `test/schema/rules/song_pattern_bridge_rules_test.dart`
- `test/store/song_project_store_test.dart`
- `test/store/song_playback_store_test.dart`
- `test/features/song/song_screen_test.dart`
- `test/features/song/song_save_panel_test.dart`
- `test/features/song/song_note_pattern_editor_test.dart`
- `test/features/song/drum_machine_editor_test.dart`

### Modify

- `lib/models/save_system.dart`
- `lib/store/save_system_store.dart`
- `lib/ui/save_browser_panel.dart`
- `lib/utils/note_player.dart`
- `lib/main.dart`
- `test/store/save_system_store_test.dart`
- `docs/save_system.md`
- `docs/piano_roll.md`

## Testing Strategy

### Pure rule tests

Add focused coverage for:

- clip overlap validation
- auto-expand rules
- duplicate clip placement
- track duplication preserving shared pattern references
- `Make unique`
- import conversion from all supported snapshot types
- absolute-tick event expansion across note and drum tracks
- note-pattern <-> piano-roll bridge conversion

### Store tests

Add coverage for:

- track creation and deletion
- mute/solo transitions
- clip create/move/duplicate/delete
- pattern update propagation
- overlap rejection
- `Make unique`
- Song playback snapshotting

### Widget tests

Add coverage for:

- `Song` tab shell rendering
- adding note and drum tracks
- opening clip creation actions
- note editor showing `Used in N clips`
- `Make unique` relinking only one clip
- drum step toggling
- save/load panel capture and restore

### Review expectations

During implementation, every component should receive focused review:

- `state-architect`
  - canonical state shape, immutability, provider boundaries
- `save-system`
  - snapshot wiring, JSON completeness, browser integration
- `instrument-renderer`
  - arranger interaction, note editor hosting, drum grid behavior
- `accessibility-ux`
  - touch targets, button labels, sheet flows, compact/wide usability
- `code-quality`
  - analyzer cleanliness, dead code, naming, drift from repo patterns

## Risks And Mitigations

### Risk 1: Song note editor accidentally mutates standalone Roll state

Mitigation:

- isolate Song note editing in a dedicated provider container
- bridge only through pure conversion functions

### Risk 2: Shared pattern length changes cause hidden overlap regressions

Mitigation:

- validate all linked instances before saving pattern edits
- block invalid saves rather than silently shifting clips

### Risk 3: Save browser previews become misleading for Song projects

Mitigation:

- add Song-specific preview summary UI instead of reusing chord-centric summaries

### Risk 4: Drum playback becomes platform-specific or brittle

Mitigation:

- keep drums synthesized inside `NotePlayer`
- test transport sinks with provider overrides before any manual listening

## Out Of Scope

- per-section tempo or time-signature automation
- clip resize handles
- audio tracks
- MIDI import/export
- undo/redo
- loop braces
- volume/pan/mixer
- drag-and-drop between tracks with pattern conversion
- per-track instrument assignment
- custom drum-kit mapping
- pattern folders or browser
- arrangement markers and sections
