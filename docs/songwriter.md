# Songwriter

The Songwriter is a section-based, multi-lane arrangement map. A song is a list of
**sections** (verse, chorus, … — free, optional labels); each section stacks parallel
**lanes**; each lane holds **blocks** that reference saved progressions. It gives the
app's arrangement mission (double-tracking, harmonies, complementary sounds) a spine:
a harmony lane of chords as foundation, save lanes of voicings/scales/highlights as
enrichment beneath it.

> **Status:** Foundation only (data model, rules, store). The Songwriter tab UI,
> transport playback, and the chord-wheel picker are tracked in later plans
> (`docs/superpowers/specs/2026-06-02-songwriter-v1-design.md`).

---

## Data Model (`lib/models/songwriter.dart`)

| Type | Description |
|---|---|
| `SongwriterProjectSnapshot` | `InstrumentSnapshot` subtype (`type: 'songwriter'`) — `config` + ordered `sections`. |
| `SongwriterConfig` | `tempo`, `beatsPerBar`, `beatUnit`, optional `keyRoot` (pitch class) + `keyScaleName`. |
| `SongSection` | `id`, optional `label`, `lengthBars`, `order`, `repeat`, `lanes`. |
| `SongLane` | `id`, `kind` (`harmony` \| `save`), optional `label`, `order`, `repeat`, `blocks`. |
| `SongBlock` | `id`, `startBar`, `spanBars` (+ `endBar` getter); a `saveId` live reference **or** an `embedded` detached snapshot; harmony extras: `chordSymbol`, `chordQuality`, `chordRootPc`, `chordNotes`, `romanNumeral`. |

All types are immutable (`copyWith` / `toJson` / `fromJson`). A block resolves to a
snapshot as: `embedded` if set (Made Unique), else the live `SaveEntry` for `saveId`,
else broken (the referenced save was deleted).

## Rules (`lib/schema/rules/songwriter_rules.dart`)

| Function | Purpose |
|---|---|
| `romanNumeralFor(chordRootPc, quality, keyRootPc?, keyScaleName?)` | Diatonic Roman numeral for a chord in a key, or `null` (no key / non-diatonic). Cased by quality (`dim` → `vii°`, minor → lowercase). |
| `blocksOverlap(existing, candidate)` | Half-open overlap check within a lane; touching edges and gaps are allowed; self (same id) ignored. |
| `makeSection` / `makeLane` / `makeSaveBlock` / `makeHarmonyBlock` | UUID-stamped factories. |
| `flattenedBarCount(sections)` | Total bars after expanding section repeats (Σ `lengthBars * repeat`). |
| `laneNaturalLength(lane)` | Lane pattern length = max `block.endBar` (0 if empty). |
| `tileLaneBlocks(lane, sectionLengthBars)` | Expands a lane's blocks, tiling the pattern `lane.repeat` times from bar 0, clipped to the section length (a placement starting at/after the section end is dropped; a block spanning past the end is kept). |

### Repeat semantics

Playback flattening expands **section** repeats (whole section loops N×) and **lane**
repeats (the lane's block pattern tiles N× from bar 0, clipped to the section). v1
blocks are silent visual guides — flattening drives the playhead/highlighting; audio is
metronome only.

## Store (`lib/store/songwriter_store.dart`)

Provider: `songwriterProvider` (`NotifierProvider<SongwriterNotifier, SongwriterProjectSnapshot>`).

| Method | Description |
|---|---|
| `hydrate()` | Restore the auto-saved session. |
| `newProject()` | Reset to empty + clear the session slot. |
| `setKey(root, scaleName)` / `setTempo(tempo)` | Config edits; `setKey` recomputes harmony-lane Roman numerals. |
| `addSection` / `addLane` / `addSaveBlock` / `addHarmonyBlock` / `removeBlock` | CRUD; block adds that overlap are ignored. |
| `makeBlockUnique(...)` | Detach a block from its live save by embedding a snapshot. |
| `loadProject(project)` | Replace the whole project (named-save load). |

### Session auto-save

The active project auto-persists to `@muzician/songwriter_session/v1` ~500 ms after
each mutation (debounced; state captured at schedule time) and restores on launch. This
slot is separate from the Song tab's `@muzician/song_session/v1` and is overwritten,
not appended.

## Save / Load

Songwriter projects also save as a `SaveEntry` (`InstrumentSnapshot` filter
`'songwriter'`) through the shared save browser, alongside fretboard / piano /
piano-roll / song saves.
