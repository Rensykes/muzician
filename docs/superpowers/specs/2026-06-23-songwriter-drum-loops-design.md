# Songwriter Drum Loops & Sequencer Tools — Design

**Date:** 2026-06-23
**Status:** Approved (design) — pending implementation plan
**Feature area:** Songwriter drum lanes (`lib/features/songwriter/`, `lib/features/song/drum_machine_editor.dart`, `lib/store/`, `lib/schema/rules/`, `lib/models/`)

---

## Summary

Three additions to the existing Songwriter drum-lane feature:

1. **Backing audition** — the drum pattern editor's Play button can audition the pattern *solo* (today's behavior) or *with the section's harmony looping underneath*, so the beat is heard in musical context.
2. **Sequencer fills** — per-lane utilities to populate a lane quickly: "every N steps" (with offset) and Euclidean (K hits over the pattern length), plus clear-lane.
3. **Drum-loop library** — a curated set of code-defined factory loops *and* fills, plus user-saved loops persisted through the existing save system. Picking any library entry **copies** it into the project as a fresh, editable `DrumPattern`.

Each component is independently shippable and is sequenced into its own implementation plan (see Phasing).

---

## Background (verified against HEAD)

The drum lane shipped via `docs/superpowers/plans/2026-06-09-songwriter-drum-lane.md`. Current state:

- **Model** — `DrumPattern { id, name, lengthTicks, lanes }` and `DrumLaneSequence { laneId, activeTicks }` live in `lib/models/song_project.dart`. Eight voices in `DrumLaneId`: kick, snare, closedHiHat, openHiHat, clap, lowTom, highTom, crash. A 16th-note grid: `ticksPerBeat = 4`, so a default 16-tick pattern is one 4/4 bar.
- **Songwriter storage** — `SongwriterProjectSnapshot.drumPatterns: List<DrumPattern>`; a `SongLaneKind.drum` lane holds `SongBlock`s that reference a pattern via `block.patternId`.
- **Two playback paths:**
  - `DrumPatternPlaybackNotifier` (`lib/store/drum_pattern_playback_store.dart`) — loops a *single* pattern over `lengthTicks`, **drums only**. Drives the editor's Play button. Shared by the Song feature and Songwriter.
  - `SongwriterPlaybackNotifier` (`lib/store/songwriter_playback_store.dart`) → `flattenPlaybackEvents` (`lib/schema/rules/songwriter_playback_rules.dart`) — the full transport already mixes harmony, save voicings, and drum patterns.
- **Editor** — `DrumMachineEditorBody` (`lib/features/song/drum_machine_editor.dart`) is source-agnostic: it takes `pattern`, `tempo`, `onChanged`. The Songwriter sheet (`lib/features/songwriter/drum_pattern_sheet.dart`) wraps it; the Song feature wraps it via `DrumMachineEditor`. Today the body only toggles individual cells; there are no fill tools in the shared body.
- **Save system** — `SaveEntry` holds an `InstrumentSnapshot` subtype; dispatch is a static `type`/`instrument` switch in `InstrumentSnapshot.fromJson` (`lib/models/save_system.dart:66`). `save_system.dart` already imports `song_project.dart`, so a new snapshot wrapping a `DrumPattern` introduces **no import cycle**. `SaveBrowserPanel` is reusable and supports an `onPick(SaveEntry)` callback (distinct from the state-replacing `onLoad`) plus an `allowedInstruments` filter and a virtual `rootFolderId`.
- **Open site** — after the writer unification, the editor sheet is opened from a single place: `songwriter_screen_sheet.dart:1616`, inside a per-section drum strip where `section` is already in scope.
- No preset/library concept exists yet.

---

## Decisions (from brainstorm)

- **Backing source:** the harmony of the **section the editor was opened from**, looped at the section boundary. The pattern tiles across the section bars (mirroring the real transport) while per-bar chords play underneath. Rationale: a 1-bar pattern under per-bar chords must loop at section length, not pattern length, to stay musical.
- **Library storage:** **both** — code-defined factory presets (loops + fills) *and* user loops saved through the save system. **Copy-on-use:** picking any library entry clones it into `SongwriterProjectSnapshot.drumPatterns` with a fresh id, so it is reusable and editable without mutating the source.
- **Factory presets are code-defined** `const` templates (not seeded save entries): no migration, always present, versioned with the app.
- **Fills:** per-lane "every N" *and* Euclidean.
- **Shared-editor safety:** all new editor capabilities are optional parameters so the Song feature's editor is unaffected.

---

## Component 1 — Editor audition with section-harmony backing

### Requirements

- A **Backing** toggle in the editor transport row, shown only when the editor has a section context (Songwriter). Hidden for the Song feature.
- Backing **off** → unchanged: loop the pattern over `lengthTicks`, drums only.
- Backing **on** → loop length = `section.lengthBars × measureTicks`. The pattern tiles across the loop; the section's harmony/save-lane chords fire per bar. Live pattern edits are audible immediately (edits already flow to the store before audition reads them).
- Other drum lanes in the section are **excluded** from the backing (focus stays on the pattern being edited + the harmony bed).

### Data flow

- **Pure helper** in `songwriter_playback_rules.dart`:
  ```dart
  ({int loopTicks, Map<int, List<int>> notesByTick}) sectionHarmonyLoop(
    SongSection section,
    SongwriterConfig config,
    List<SaveEntry> saves,
  );
  ```
  Reuses `chordMidiNotes` (harmony lanes) and `snapshotMidiNotes(resolveBlockSnapshot(...))` (save lanes), emitting per-bar stabs over the section span, exactly like the harmony/save branch of `flattenPlaybackEvents` but scoped to one section and indexed from tick 0. `loopTicks = section.lengthBars × config.ticksPerBeat × config.beatsPerBar`.
- **Audition transport** — extend `DrumPatternPlaybackNotifier.start`:
  ```dart
  Future<void> start({
    required DrumPattern pattern,
    required int tempo,
    Map<int, List<int>>? backingNotes, // tick → midi pitches, within the loop
    int? loopTicks,                     // overrides pattern.lengthTicks when set
  });
  ```
  With backing: the loop runs `loopTicks` ticks; the pattern's hits are emitted at `t` for each tile origin `0, lengthTicks, 2·lengthTicks, …` (clipped to `loopTicks`); backing notes fire via a new **self-contained** `drumPatternBackingSinkProvider` (a note sink defaulting to `NotePlayer.previewNote`). No backing → today's path, byte-for-byte. Keeping the sink inside the drum store avoids coupling it to the songwriter store and keeps the Song feature's usage untouched.
- **Editor body** — `DrumMachineEditorBody` gains an optional `backing` descriptor (`{ Map<int,List<int>> notesByTick, int loopTicks }`). Non-null → render the toggle and pass through to `start`; null → no toggle (Song feature).
- **Sheet** — `showSongwriterDrumPatternSheet({ required context, required patternId, String? sectionId })`. Thread `section.id` from `songwriter_screen_sheet.dart:1616`. The sheet's `_Body` watches `songwriterProvider` + `saveSystemProvider`, finds the section by id, and computes `backing` via `sectionHarmonyLoop`. A null/empty section → no backing (toggle hidden).

### Tests

- `sectionHarmonyLoop`: chord ticks land on bar boundaries; `loopTicks` matches section length; empty/harmony-less section → empty `notesByTick`; save-lane blocks contribute pitches.
- Playback: with an injected backing sink, backing notes fire at the expected ticks across a multi-bar loop; with no backing, behavior is unchanged (regression guard).
- Widget: toggle present with a `sectionId`, absent without one; toggling starts/stops audition.

---

## Component 2 — Per-lane sequencer fills (every-N + Euclidean)

### Requirements

Each lane gets a fill menu (a button in the sticky label column → compact popup):

- **Every-N**, labelled musically (`ticksPerBeat = 4`): *Every step* (1), *Every ½ beat* (2), *Every beat* (4), *Every 2 beats* (8), with a start-offset stepper. Directly satisfies "ogni battuta / ogni due / ogni quattro".
- **Euclidean**: K hits distributed evenly across `lengthTicks`, with a rotation stepper.
- **Clear lane**.

Each action replaces the target lane's `activeTicks` and emits via `onChanged`. Generic → the Song feature's editor inherits the tools.

### Data flow

- **Pure ops** in new `lib/schema/rules/drum_fill_rules.dart` (no Flutter deps):
  ```dart
  List<int> everyN(int lengthTicks, int step, {int offset = 0});
  List<int> euclid(int lengthTicks, int hits, {int rotation = 0}); // Bjorklund
  ```
- Applied inside `DrumMachineEditorBody`, which already owns `_pattern` + `onChanged`. A small `_LaneFillSheet` (or popup menu) hosts the controls; the label column (`_LaneLabelsColumn`) gains a per-lane menu affordance + callback.

### Tests

- `everyN`: offset handling, step > length, step = 1 fills all, sorted output.
- `euclid`: known distributions (e.g. `euclid(16, 4) == [0,4,8,12]`, classic `euclid(8, 3)` shape), rotation wraps, `hits = 0` → empty, `hits >= length` → all ticks.
- Widget: applying a fill marks the expected cells active; clear-lane empties only that lane.

---

## Component 3 — Drum-loop library (factory presets + user loops + copy-on-use)

### Requirements

A **Drum Library** sheet with two tabs:

- **Presets** — code-defined templates grouped by category: Rock, Funk, Pop, Latin, Hip-Hop (loops) + a **Fills** category. ~16 to start. Read-only.
- **My Loops** — user-saved loops, browsed via `SaveBrowserPanel` filtered to a new `'drum_loop'` instrument type. Lives only in this Library sheet (not mixed into the Songwriter project save browser, which stores whole-project snapshots).

Picking from either tab **copies** the pattern into the project (`addDrumPatternFrom`) and assigns the new id to the target block. The editor also gains **Save to library** (capture the current pattern as a `'drum_loop'` save).

### Data / schema

- **Presets** — `lib/schema/rules/drum_presets.dart`: `const List<DrumPreset>` where `DrumPreset { String name; String category; List<DrumLaneSequence> lanes; int lengthTicks; }`. Templates carry no persistent id; ids are generated on copy. A stable preset key (e.g. `category/name`) is used only for list identity in the UI.
- **Snapshot** — `DrumLoopSnapshot extends InstrumentSnapshot` in `lib/models/save_system.dart` (`type/instrument: 'drum_loop'`) wrapping one `DrumPattern`. `selectedNotes` → empty; `pendingChord`/`pendingScale` → null. JSON round-trips via the existing `DrumPattern.toJson/fromJson`. Add a dispatch branch in `InstrumentSnapshot.fromJson` (save_system.dart:66) before the fretboard fallback:
  ```dart
  if (type == 'drum_loop' || instrument == 'drum_loop') {
    return DrumLoopSnapshot.fromJson(json);
  }
  ```
  No import cycle: `save_system.dart` already imports `song_project.dart`.
- **Panel** — `DrumLoopSavePanel` (`lib/features/songwriter/drum_loop_save_panel.dart`): a thin `SaveBrowserPanel` wrapper with `allowedInstruments: ['drum_loop']`, `captureSnapshot` returning a `DrumLoopSnapshot` of the current pattern, and `onPick` → copy-into-project.
- **Store mutator** — `songwriter_store`:
  ```dart
  String addDrumPatternFrom(DrumPattern source); // clone with fresh id + de-duped name; append; return id
  ```
  Used by both preset-pick and library-pick. (`addDrumPattern` for empty patterns already exists.)
- **Entry points:**
  - "Add drum lane / drum block" offers **Empty** or **From library** (opens the picker; on pick, seeds the block with the copied pattern).
  - Editor header gains **Library** (browse → replace the current block's pattern with a copy) and **Save to library**.

### Tests

- `DrumLoopSnapshot` JSON round-trip; `fromJson` dispatch resolves `'drum_loop'`.
- Preset integrity: every preset has valid `lengthTicks > 0` and all `activeTicks` within range.
- `addDrumPatternFrom`: produces a new id, de-dupes the name, leaves the source object unchanged.
- Panel/pick: picking a preset inserts a copy into `drumPatterns` and assigns the block's `patternId`; editing the copy does not mutate the preset/saved original.

---

## Non-goals

- Song feature changes beyond inheriting the generic fill tools and the optional-param editor signature. No Song-side backing audition, no Song↔Songwriter pattern import.
- Sheet-variant visual redesign of drum strips beyond what the entry points require.
- Per-step velocity/accents, swing, or sub-16th resolution.
- Variable pattern length editing UI (length stays as created/imported; presets define their own length).
- Mixing other drum lanes into the editor backing (harmony/save bed only).

---

## Risks & edge cases

- **Shared editor** — backing + fills must be optional so the Song feature is unaffected. Covered by optional params and a null-section guard.
- **Pattern shared by multiple blocks** — existing in-project patterns can already be shared; editing affects all referencing blocks (unchanged behavior). Copy-on-use specifically prevents *library* inserts from creating accidental shared edits. A "make unique" affordance for in-project drum patterns is out of scope (the Song feature already has one for its own model).
- **Loop length vs pattern length** — backing loops at section length; the pattern tiles. Defined above; tested.
- **Euclidean resolution** — distributed over `lengthTicks` positions (not a separate step count), so it scales with pattern length.
- **Backing when a pattern is reused across sections** — the editor uses the section it was opened from; the same pattern opened from a different section yields a different bed. Acceptable and expected.
- **`drum_loop` saves and project scoping** — drum-loop saves follow the normal save-system folder/project rules; the Library sheet uses the standard browser, so project-scoping behavior is inherited, not reinvented.

---

## Phasing (each → its own implementation plan)

1. **Fills** (Component 2) — pure ops + editor UI. No schema change. Smallest, generic win.
2. **Backing audition** (Component 1) — `sectionHarmonyLoop` + transport extension + sheet threading. No persistence change.
3. **Presets + picker** (Component 3, factory half) — `drum_presets.dart`, `addDrumPatternFrom`, Library "Presets" tab, copy-on-use. No save-system change.
4. **User loops** (Component 3, save half) — `DrumLoopSnapshot` + dispatch, `DrumLoopSavePanel`, "My Loops" tab, **Save to library**.

---

## File summary

**Created**
- `lib/schema/rules/drum_fill_rules.dart` — `everyN`, `euclid`.
- `lib/schema/rules/drum_presets.dart` — `DrumPreset` + `const` library.
- `lib/features/songwriter/drum_loop_save_panel.dart` — `DrumLoopSavePanel`.
- `lib/features/songwriter/drum_library_sheet.dart` — Presets + My Loops picker.
- Tests: `test/schema/rules/drum_fill_rules_test.dart`, `test/schema/rules/songwriter_playback_backing_test.dart` (or extend the existing playback-rules test), `test/schema/rules/drum_presets_test.dart`, `test/models/drum_loop_snapshot_test.dart`, `test/store/songwriter_drum_library_test.dart`, plus widget tests for the editor backing toggle / fill menu / library picker.

**Modified**
- `lib/models/save_system.dart` — `DrumLoopSnapshot` + `fromJson` dispatch branch.
- `lib/schema/rules/songwriter_playback_rules.dart` — `sectionHarmonyLoop`.
- `lib/store/drum_pattern_playback_store.dart` — `backingNotes`/`loopTicks` params + `drumPatternBackingSinkProvider`.
- `lib/store/songwriter_store.dart` — `addDrumPatternFrom`.
- `lib/features/song/drum_machine_editor.dart` — optional `backing`, per-lane fill menu in `DrumMachineEditorBody`.
- `lib/features/songwriter/drum_pattern_sheet.dart` — `sectionId` param, compute backing, Library / Save-to-library headers.
- `lib/features/songwriter/songwriter_screen_sheet.dart:1616` — pass `sectionId`; "From library" entry on add-drum-lane/block.
