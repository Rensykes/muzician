# Melody Pattern Length and Naming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Let melodies span multiple named bars and make Writer placements bar-aligned windows that never loop past the melody's last note.

**Architecture:** Derive melody length from its last note rounded up to whole bars, expose editing length and naming in the existing Piano Roll host, and reuse that length as the placement maximum. Playback and previews play the melody once from the placement start, clipping at the placement and melody end. Existing over-long placements keep their occupied span with silence after the melody.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test; existing Piano Roll, Writer store, Save System and Studio theme.

**Spec:** `docs/superpowers/specs/2026-10-28-melody-pattern-length-and-name-design.md`

## Global Constraints

- Pattern length is `max(1, ceil(last note end / measure ticks))` bars; empty patterns are one bar; notes are never deleted by resizing the canvas or a placement.
- Placements may shrink to any whole bar but never grow beyond the melody's last-note bar; play once, clip at the placement edge, and never loop past the melody.
- Existing longer placements keep their occupied span and show a silent tail; move-only edits may retain the span, while any resize must end within the melody limit.
- Shared names and content update every linked placement; Make Unique remains independent.
- Keep Studio styling, both themes, 44px targets, compact/wide layouts, large-text behavior, accessibility, Save System canonical content, undo/redo and unrelated lane behavior unchanged.
- Follow AGENTS.md; update Writer guides and README; verify with focused tests, analysis, and populated runtime inspection.

## Review Focus

- A note ends exactly on a barline: length stays that bar, not an extra one (Task 1).
- Deleting the last notes shortens the melody while existing placements keep their spans and become silent tails (Task 1/2).
- An over-long placement dragged shorter must be able to jump directly to a valid span (Task 2).
- A block starts mid-melody: it plays from that bar offset, not from melody tick zero (Task 2).
- A pattern ending mid-bar still occupies the full bar with silence (Task 1).

## File Map

- `lib/schema/rules/songwriter_rules.dart`: melody bar count, placement limits, bar-aligned length helper.
- `lib/schema/rules/songwriter_playback_rules.dart`: single-pass, placement-aligned melody playback.
- `lib/features/songwriter/songwriter_melody_pattern_editor.dart`: Bars stepper, rename UI, quantized save.
- `lib/features/songwriter/songwriter_melody_preview.dart`: single-pass preview with silent tail.
- `lib/features/songwriter/songwriter_melody_timeline.dart`: resize limit, silent-tail display, pattern data.
- `lib/features/songwriter/songwriter_screen_sheet.dart`: creation/reuse/edit naming paths, placement dialog, lane add.
- `lib/store/songwriter_store.dart`: save expansion, placement validation with melody limit, repeat/reuse, add-lane defaults.
- Tests mirror these rules, store and feature files.
- Docs: `docs/songwriter.md`, `docs/song_writer_guide.md`, `README.md`.

### Task 1: Bar-aligned melody length and naming in the editor

**Files:** Modify `lib/schema/rules/songwriter_rules.dart`, `lib/features/songwriter/songwriter_melody_pattern_editor.dart`, `lib/store/songwriter_store.dart`; test `test/schema/rules/songwriter_rules_test.dart`, `test/features/songwriter/songwriter_pattern_lane_test.dart`.

**Interfaces:**
- Consume `NotePattern`, `SongwriterConfig.measureTicks`, isolated `pianoRollProvider`.
- Produce `int melodyBarCount(NotePattern pattern, int measureTicks)` (minimum 1); `NotePattern quantizeMelodyPatternLength(NotePattern pattern, int measureTicks)` setting `lengthTicks` to `melodyBarCount * measureTicks`; editor-local Bars state from 1–32 and a rename dialog.

- [ ] Add rule tests: empty pattern → 1 bar/one measure; notes ending exactly on a barline → that bar; notes ending one tick into a bar → next bar; 32-bar cap behavior; quantizing preserves notes, name, mapping fields and only adjusts length.
- [ ] Add widget tests: opening the melody editor shows the current name and bar count; the Bars stepper increases the grid, cannot drop below the last-note bar, and its 44px targets work compactly; renaming and Save updates the shared pattern name and every linked block label; Back leaves the name unchanged; large text does not clip.
- [ ] Run `flutter test --no-pub test/schema/rules/songwriter_rules_test.dart test/features/songwriter/songwriter_pattern_lane_test.dart`; confirm the new tests fail for missing controls/helpers.
- [ ] Implement the bar-count helpers and quantized length; wire the editor Bars stepper to the isolated `setTotalMeasures`, restricting decreases to the last-note bar, and rename the pattern through the existing save path. Empty patterns keep one bar. Do not alter Piano Roll tool behavior or Song's bridge.
- [ ] Ensure a newly created melody's first save still expands its initial placement to the quantized bar count when the full span fits; keep later saves from resizing existing placements.
- [ ] Repeat the focused test command; expect all tests to pass.

### Task 2: Placement limits, single-pass playback and silent tails

**Files:** Modify `lib/schema/rules/songwriter_rules.dart`, `lib/schema/rules/songwriter_playback_rules.dart`, `lib/features/songwriter/songwriter_melody_preview.dart`, `lib/features/songwriter/songwriter_melody_timeline.dart`, `lib/features/songwriter/songwriter_screen_sheet.dart`, `lib/store/songwriter_store.dart`; test `test/schema/rules/songwriter_flatten_test.dart`, `test/schema/rules/songwriter_playback_rules_test.dart`, `test/store/songwriter_block_placement_test.dart`, `test/store/songwriter_writer_save_sync_test.dart`, `test/features/songwriter/songwriter_pattern_lane_test.dart`, `test/features/songwriter/songwriter_melody_preview_test.dart`.

**Interfaces:**
- Consume `melodyBarCount` and the placement/occurrence helpers.
- Produce melody-aware placement validation accepting the current pattern limit; single-pass playback/preview windows; silent-tail metadata for summaries and semantics.

- [ ] Add tests: a 3-bar melody rejects a 4-bar placement and accepts 1–3 bars; an existing 4-bar legacy placement can move with its span but any resize must end within 3 bars and can jump 4→2; new blocks and Repeat / reuse default to the melody bars or available space; adding a Melody lane creates a one-bar block; first-save expansion still works.
- [ ] Add playback/preview tests: a block starting at bar 2 with a 3-bar melody plays melody ticks offset into the block; a shorter block clips; a longer block plays once then silence; no note repeats after the melody end; the preview and duration summary identify the silent tail.
- [ ] Add timeline tests: resize stops at the melody limit; an over-long block can shrink directly; the silent tail remains occupied and cannot host another block; Adjust placement allows move-only but requires a valid span on apply.
- [ ] Run the focused store/rules/feature commands; confirm expected failures first.
- [ ] Implement the melody limit in placement validation with an explicit unchanged-overlong move allowance. Apply it in `setBlockPlacement`, pattern-block creation, Repeat / reuse, the timeline drag preview and the Adjust placement dialog. Keep automatic lane-repeat safeguards.
- [ ] Change `flattenPlaybackEvents` melody blocks to one pass: notes are placed relative to block start, clip at the pattern and placement end, and never loop. Apply the same window to the note preview. Add a clear silent-tail cue in the tile/detail semantics without disturbing names, tap or resize.
- [ ] Change adding a Melody lane to create a one-bar block; leave first-save expansion for newly authored patterns.
- [ ] Repeat the focused commands; expect all tests to pass.

### Task 3: Documentation and end-to-end verification

**Files:** Modify `docs/songwriter.md`, `docs/song_writer_guide.md`, `README.md`; review `PRODUCT.md`, `DESIGN.md`, `AGENTS.md`.

**Interfaces:** Consume Tasks 1–2; no new production interfaces.

- [ ] Reconcile documentation: named multi-bar melodies, bar-quantized length, Bars editor control, placement maximum, no looping, silent tails, one-bar new lane, and unchanged linked reuse.
- [ ] Run `dart format` on changed Dart files, `flutter analyze --no-pub`, and every focused test target from Tasks 1–2; expect zero analyzer issues and all tests passing. Run the full suite if practical and report failures/timeouts honestly.
- [ ] Inspect a populated runtime melody with notes across at least three bars and its placement at compact and wide sizes in both Studio themes. Verify the name, Bars control, preview, silent tail, resize limit and large text. Report native/web limitations.
- [ ] Review `AGENTS.md` after the phase and update only persistent contracts; check `git diff` for unrelated changes.
