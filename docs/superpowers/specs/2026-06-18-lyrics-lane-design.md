# Lyrics Lane — Design

**Date:** 2026-06-18
**Branch:** feature/song-writer-complete
**Status:** Approved (brainstorming)

## Problem

Lyrics today live as `List<String>` on each `SongBlock` and are therefore
strictly tied to bars (a chord/silent block's `startBar`/`spanBars`). This
serves writers who want lyrics aligned under chords, but offers nothing to a
writer who just wants to jot lyrics down freely without committing to a bar
grid.

We want a lyrics lane that is **not strictly tied to bars**, usable by both
audiences:

- **Precision** — line lyrics up under chords, lead-sheet style.
- **Jotter** — dump text without caring about bar alignment.

## Approach (chosen: A)

Add a new `SongLaneKind.lyrics`. Its blocks reuse the existing `SongBlock`
structure. Bar position (`startBar`/`spanBars`) is **optional / soft** — used
when the writer wants alignment, ignored (one full-width block) when they just
want to type.

Rejected alternatives:

- **B — Unify (kill per-block lyrics, move all lyrics into the lane).** Cleaner
  single source of truth, but needs migration of existing `block.lyrics`, a
  rewrite of the chord+lyric editor, and a proven alignment UX first. Deferred
  as future cleanup.
- **C — Free-text blob per section.** Dead simple but discards alignment
  entirely, failing the precision half of the requirement.

## Design

### 1. Model — `lib/models/songwriter.dart`

- Extend the enum: `enum SongLaneKind { harmony, save, drum, lyrics }`.
  `_laneKindFromName` already iterates `SongLaneKind.values`, so JSON
  round-trips with no extra code.
- **No new `SongBlock` fields.** Lyric-lane blocks reuse:
  - `startBar` / `spanBars` — optional soft position (clamped to section
    length, never snapped/enforced beyond clamp).
  - `lyrics: List<String>` — the text, one entry per verse (mirrors how silent
    blocks carry per-verse lyrics under lane `repeat`).
  - Chord fields (`chordSymbol`, `chordRootPc`, `chordNotes`, etc.) remain null.
  - `isSilent` stays `false`; the lane *kind* distinguishes lyric blocks, not a
    block flag.

### 2. Rules — `lib/schema/rules/songwriter_rules.dart`

- Add `makeLyricBlock({required int startBar, required int spanBars, String text = '', int verseCount = 1})`
  returning a `SongBlock` with `lyrics` initialized to `verseCount` entries
  (first = `text`). Distinct from `makeSilentBlock` (which is a harmony-lane
  construct).

### 3. Store — `lib/store/songwriter_store.dart`

- Reuse existing lane-generic methods: `addLane(kind: SongLaneKind.lyrics)`,
  `removeLane`, `reorderLanes`, `setLaneRepeat`, `setBlockLyric`.
- Add `addLyricBlock({sectionId, laneId, startBar, spanBars, text})` that
  inserts a `makeLyricBlock` into the lane (clamping position to section
  length). Reuse generic block remove/move if present; otherwise add minimal
  helpers scoped to the lyrics lane.
- No bar-snap enforcement — soft positioning only.

### 4. UI — `lib/features/songwriter/songwriter_screen_sheet.dart`

- Add `_LyricLaneRow` modeled on `_DrumLaneRow`: same gutter + `BarGridPainter`
  background so it aligns column-for-column with the harmony lane above it.
- **Jotter flow:** tapping empty lane space creates one block spanning the full
  section, opening inline multi-line text edit.
- **Precision flow:** tapping a specific bar cell creates a block anchored at
  that bar with a narrow span; positioned directly under the harmony lane it
  lines up beneath the chords = lead-sheet feel.
- Tapping an existing lyric block opens text editing (reuse the existing lyric
  editor code path / `setBlockLyric`).
- Render the lyrics lane wherever lanes are iterated in `_SectionSheet`
  (alongside the existing `harmony` / `drum` / `save` branches).

### 5. Structure editor — `lib/features/songwriter/songwriter_structure_editor.dart`

- Add a "Lyrics" entry to the add-lane menu wherever harmony/drum/save lanes
  are offered, calling `addLane(kind: SongLaneKind.lyrics)`.

### 6. Persistence / save browser

- Free via generic lane JSON (`SongLane.toJson` already serializes `kind.name`
  and `blocks`).
- Lyrics lane is **excluded** from the save-instrument allowlist —
  `songwriter_save_lane_filter.dart` is left untouched (it gates `save` lanes
  only).

## Out of scope (v1)

- Playback / timing sync (no karaoke-style beat timing).
- Drag-to-reposition and drag-resize of lyric blocks (tap-to-place only; polish
  later).
- Rich text / formatting.
- Approach-B consolidation: existing per-harmony-block lyrics stay as-is.

## Testing

- **Unit (model/rules):** `makeLyricBlock` shape; `SongLaneKind.lyrics` JSON
  round-trip (toJson/fromJson) on a section containing a lyrics lane.
- **Store:** `addLane(kind: lyrics)` then `addLyricBlock` inserts a block;
  position clamps to section length; `setBlockLyric` updates per-verse text.
- **Widget:** `_LyricLaneRow` renders; tapping empty lane adds a full-width
  block; tapping a bar cell anchors a block at that bar; tapping a block opens
  the editor.
- **Manual / visual (serve-sim):** add a lyrics lane, jot free text, anchor a
  fragment under a chord and confirm column alignment with the harmony lane,
  then save + reload to confirm persistence.
