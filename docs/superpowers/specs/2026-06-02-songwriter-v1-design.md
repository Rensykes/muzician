# Songwriter — Spec 2: Songwriter v1 (Subproject B)

**Date:** 2026-06-02
**Status:** Design approved, ready for implementation plan
**Depends on:** Spec 1 (Save Grid View) — its palette mode is how blocks are added.
**Part of:** Songwriter initiative (A → B → C). This is **B**, the headline feature. **C** (enrichment) is sketched in the appendix and is a separate future spec.

---

## 1. Vision

A new **Songwriter** tab: a section-based, multi-lane arrangement map. The user organizes a song into **sections** (verse, pre-chorus, chorus, outro — free, optional labels), and inside each section stacks **lanes** that run in parallel. Lanes hold **blocks**, and each block is a reference to an existing **save** (a guitar voicing, a piano chord, a scale, a highlight set).

The app's mission is arrangement help — double-tracking, harmonies, complementary sounds. Songwriter gives that a spine: a **harmony lane** of chords (the foundation) with **save lanes** beneath it (the enrichment). Because the app cannot yet save true arpeggios, a block can span an entire section to mean "these fingerings / valid positions hold for the whole verse."

v1 is a **performance map**: real-time, bar-based, with a transport and metronome the musician plays along to. The save-blocks are **silent visual guides** that light up under the playhead. Synthesizing the blocks is deliberately deferred.

## 2. Locked Decisions

| ID | Decision |
|----|----------|
| B-1 | New **6th nav tab "Songwriter"**, beside the existing Song tab. Song (clip DAW) is untouched. |
| B-2 | Model: ordered **Sections** → per-section parallel **Lanes** → **Blocks**. Lanes are scoped to their section (not global). |
| B-3 | Block = **live reference** to a `SaveEntry` (by `saveId`) with **Make Unique** to detach into an embedded snapshot copy. Mirrors Song clip behavior. |
| B-4 | **Real-time, bar-based.** Sections have a bar length; blocks have bar position + span. Playback reuses the existing Song **transport + audio engine**; no new engine. |
| B-5 | v1 blocks are **silent visual guidance**. Playback audio = **metronome only** (plus audio-track lanes if/when added). |
| B-6 | Project carries an optional **key**. A dedicated **Harmony lane** renders chord blocks as **Roman numerals** derived from the key, added via the **existing chord picker**. Generic **save lanes** below = enrichment. |
| B-7 | **Chord wheel deferred** to its own later pass — it does not change the data model. |
| B-8 | **Bars-only** time granularity; **gaps allowed** within a lane; **no overlap** of blocks within one lane. |
| B-9 | **Repeat** at **section** and **lane** level (the "Nx" badge). No block-level repeat. |

## 3. Data Model

New file `lib/models/songwriter.dart` (kept out of the already-large `save_system.dart`, which imports it for the snapshot subtype). All types immutable with `copyWith`, `toJson`/`fromJson`, matching existing model conventions.

### 3.1 Snapshot subtype

```text
class SongwriterProjectSnapshot extends InstrumentSnapshot   // type: 'songwriter'
  instrument    => 'songwriter'
  config        : SongwriterConfig
  sections      : List<SongSection>

  // InstrumentSnapshot contract:
  selectedNotes => aggregated unique pitch classes across all harmony-block chords
                   (so the save card in Spec 1 shows chips)
  pendingChord  => null     // like SongProjectSnapshot — no single summary
  pendingScale  => null
```

Register in `InstrumentSnapshot.fromJson` (`lib/models/save_system.dart:62`): add a branch `if (type == 'songwriter' || instrument == 'songwriter') return SongwriterProjectSnapshot.fromJson(json);`. Purely additive — existing saves are untouched.

### 3.2 Config

```text
class SongwriterConfig
  tempo          : int                 // BPM, drives transport
  timeSignature  : TimeSignature       // reuse existing type (piano_roll / song)
  keyRoot        : int?                // pitch class 0–11, nullable
  keyScaleName   : String?             // e.g. 'major'; diatonic set for Roman mapping
```

### 3.3 Section

```text
class SongSection
  id          : String                 // generateId()
  label       : String?                // optional free text, may be null/blank
  lengthBars  : int                    // section duration in bars (>= 1)
  order       : int                    // position in song
  repeat      : int                    // default 1; loops whole section N× in timeline
  lanes       : List<SongLane>
```

### 3.4 Lane

```text
enum SongLaneKind { harmony, save }

class SongLane
  id      : String
  kind    : SongLaneKind
  label   : String?                    // 'Guitar', 'Piano voicings'…
  order   : int                        // vertical stacking within the section
  repeat  : int                        // default 1; tiles the lane's block pattern N×
  blocks  : List<SongBlock>
```

- `harmony` lane → blocks are chords, rendered as Roman numeral + symbol.
- `save` lane → blocks reference arbitrary saves.

### 3.5 Block

```text
class SongBlock
  id        : String
  startBar  : int                      // 0-based offset within its section
  spanBars  : int                      // width; spanBars == section.lengthBars => whole-section block
  saveId    : String?                  // live reference into SaveSystemState.saves
  embedded  : InstrumentSnapshot?      // non-null => Made-Unique / detached copy

  // harmony-lane extras (derived + cached so the block renders without re-detecting):
  chordSymbol  : String?
  romanNumeral : String?
  chordRoot    : int?                  // pitch class
```

### 3.6 Snapshot resolution

```text
resolveSnapshot(block, saveSystemState):
  if block.embedded != null            -> block.embedded           // detached / unique
  else if saves contains block.saveId  -> that SaveEntry.snapshot   // live link
  else                                 -> null                      // BROKEN
```

## 4. Behaviors

### 4.1 Roman-numeral derivation
A new rule in `lib/schema/rules/` — `romanNumeralFor(chordRoot, quality, keyRoot, keyScaleName) -> String?` — reusing existing `note_utils` chord/scale logic. Result cached onto the harmony block at create/edit time. Recomputed for every harmony block when the project key changes. If no key is set, harmony blocks show the bare chord symbol and no numeral.

### 4.2 Broken references
A live `saveId` whose `SaveEntry` was deleted resolves to `null` → the block renders **broken** (red diagonal stripe, the same visual language as missing audio clips in the Song tab). It stays in place, is silent, and is non-fatal. Available actions on a broken block: **Re-link** (pick another save) or **Delete**. Saves do not track their referrers in v1, so deleting a save does **not** cascade to blocks.

### 4.3 Make Unique
Mirrors Song clips: copies the currently resolved snapshot into `block.embedded` and clears the dependence on the live save (the block keeps `saveId` for provenance display but resolution prefers `embedded`). Edits to the original save no longer affect a unique block.

### 4.4 Repeat semantics (the one subtle bit — review carefully)
Playback flattens the project to a linear bar timeline:

1. For each `SongSection` in `order`, emit it `section.repeat` times back-to-back.
2. Within a section instance, each `SongLane` plays its block pattern. The lane's **natural pattern length** = the max `startBar + spanBars` across its blocks. With `lane.repeat = N`, that pattern is **tiled N times consecutively starting at bar 0**.
3. If the tiled lane content is shorter than `section.lengthBars`, the remainder of the lane is silent/empty. If it is longer, it is clipped to `section.lengthBars` (a lane never plays past its section).

Because v1 emits no block audio, "plays" here means "the block highlights under the playhead at the right bar." The flattening logic is still written now so it is correct when audio arrives.

### 4.5 Session auto-save
Mirror the Song tab's single-slot pattern: auto-persist the active Songwriter project to `@muzician/songwriter_session/v1` ~500 ms after each mutation, restore on launch. This slot is **separate** from `@muzician/song_session/v1` and is overwritten, not appended (last-session snapshot, not history). A **New Project** action in the header wipes the session behind a confirmation dialog.

### 4.6 Named save / load
Songwriter projects also save as a `SaveEntry` containing a `SongwriterProjectSnapshot`, through the shared `SaveBrowserPanel` with a new `instrumentFilter` value `'songwriter'`.

## 5. UI / Interaction

Vertical list of section cards; each card stacks lanes; each lane is a horizontal bar grid (matches the reference screenshots).

```text
Header:    project name · key chip · tempo · ☰ menu (New Project, Save/Load, Structure editor)
Transport: ◀ ▶ play · metronome · playhead
Bar ruler: 1  2  3  4  5  6  7  8

╭─ Verse ───────────────────── 8 bars · 1× · ✏ ⋮ ─╮
│ Harmony │ I    │ vi   │ ii   │ V              │ ││   roman-numeral chord blocks
│ Guitar  │ [ save block spanning whole verse ] │ ││   one long save = fingerings/positions
│ Piano   │ [blk] │   gap   │ [ save block ]    │ ││
│ + lane                                          ││
╰─────────────────────────────────────────────────╯
╭─ Chorus ──────────────────── 8 bars · 2× · ✏ ⋮ ─╮ …
+ section
```

**Sections:** editable label (blank allowed), bar-length stepper, repeat stepper (`Nx`), reorder handle, ⋮ menu (duplicate, delete).

**Lanes:** left gutter = label + kind icon + repeat stepper. Body = bar grid. `+ lane` chooses harmony or save kind.

**Blocks:**
- **Add to a save lane:** tap an empty bar cell → open the **Spec 1 grid palette** in pick mode, filtered to the lane's instrument → choose a card → drops a block at that bar.
- **Add to the harmony lane:** tap → existing chord picker → places a chord block; Roman numeral auto-derives from the project key.
- **Move:** drag horizontally, snap to bar. **Resize span:** drag the right edge. `spanBars == section.lengthBars` ⇒ whole-section block.
- **Tap a block:** open the referenced save in its instrument view (read fingering/positions; edits hit the live save unless the block is unique).
- **Long-press / ⋮:** Make Unique · Re-link · Delete. A broken block offers only Re-link / Delete.

**Structure editor** ("Modifica struttura della canzone", screenshot 2): a modal listing sections with their lanes/blocks, offering ✕ remove, ✎ rename, ↕ reorder for sections, lanes, and blocks. It calls the same model mutations as the inline UI — a bulk-edit convenience, not a separate data path. Annulla / Fatto.

**Transport:** reuse the existing Song transport widget. The playhead scrolls left→right across concatenated (and repeat-expanded) sections at `tempo`. v1 audio = metronome only; blocks highlight under the playhead as a performance guide.

## 6. Architecture & Files

| Layer | File | Change |
|-------|------|--------|
| Model | `lib/models/songwriter.dart` (new) | `SongwriterProjectSnapshot`, `SongwriterConfig`, `SongSection`, `SongLane`, `SongBlock`, enums. |
| Model | `lib/models/save_system.dart` | Branch in `InstrumentSnapshot.fromJson` for `'songwriter'`. |
| Rules | `lib/schema/rules/songwriter_rules.dart` (new) | `romanNumeralFor`, block-overlap validation, flatten-to-timeline, factories (`makeSection`, `makeLane`, `makeBlock`). |
| Store | `lib/store/songwriter_store.dart` (new) | Riverpod `NotifierProvider` — sections/lanes/blocks CRUD, key/tempo, Make Unique, session auto-save/restore. |
| UI | `lib/features/songwriter/` (new) | Tab screen, section card, lane row, block widget, structure-editor modal, save panel (`instrumentFilter: 'songwriter'`). |
| UI | `lib/ui/save_browser_panel.dart` | Consume Spec 1 palette mode (`onPick`) for block adding. |
| Nav | `lib/main.dart` | Add the 6th `Songwriter` tab + screen. |
| Tests | `test/...` | Roman-numeral rule, overlap validation, flatten/repeat semantics, snapshot round-trip, store transitions, session restore. |

Reused as-is: transport/clock + metronome from the Song engine, chord picker, `note_utils`, `SaveBrowserPanel`, `generateId`.

## 7. Success Criteria

- A new **Songwriter** tab exists; the Song tab is unchanged.
- User can create sections with optional labels, set bar length and repeat, and reorder them.
- User can add per-section lanes (harmony + save), set lane repeat, and reorder them.
- Save-lane blocks are added from the Spec 1 grid palette filtered by instrument; harmony blocks from the chord picker, showing correct Roman numerals for the project key.
- Blocks move, resize (incl. whole-section span), Make Unique, Re-link, and show a broken state when their save is deleted.
- Transport plays metronome across the flattened (repeat-expanded) timeline; blocks highlight under the playhead at correct bars.
- Project saves/loads via the shared browser as `'songwriter'`, and the active session auto-restores on relaunch.
- `flutter analyze` clean; targeted tests pass; verified on one compact and one wide viewport.

## 8. Risks / Open Items

- **Repeat semantics (§4.4)** are the highest-ambiguity area — confirm during spec review.
- **Reusing the Song transport** without its clip-audio path: verify the transport/metronome can run standalone over a bar count that we supply, without a `SongProject`.
- **Tap-into-save editing** crossing instrument contexts: opening a fretboard save from Songwriter must not leak state into the standalone Fretboard tab (use an isolated container, as the Song note-clip editor already does).
- **Performance** with many sections/lanes/blocks: lazy-build section cards; `RepaintBoundary` per lane.

---

## Appendix C — Enrichment Layer (future spec, NOT built here)

C turns the harmony spine into arrangement help. Sketch only:

- From a harmony block's chord + the project key, **suggest** complementary save-blocks:
  - **Double-tracking** voicings — same chord, different fret position / octave.
  - **Harmony** lines — diatonic 3rd / 6th above the melody or chord tones.
  - **Complementary** scale / arpeggio highlights for soloing over the section.
- Suggestions surface as "suggested blocks" the user accepts into save lanes. Reuses `note_utils` + the save library.
- **Prerequisite gap:** a real arpeggio / note-sequence save type. Today none exists — which is exactly why v1 leans on whole-section guide blocks. C must add that save type plus a suggestion rule module.
- C gets its own brainstorm → spec → plan cycle. The chord wheel (B-7) is a sibling future pass that can land before or alongside C.
