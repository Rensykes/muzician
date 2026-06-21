# Songwriter Sheet-Only + Chord-Anchored Lyrics + Drum-In-Sheet — External Agent Dispatch Prompt

Use this prompt to hand off the implementation to a fresh agent session. This dispatch **supersedes** the per-block-lyrics dispatch prompt — do not run that one in parallel.

---

## Prompt

You are converting the Muzician Songwriter (Writer) tab to a **single Sheet layout** and landing chord-anchored lyrics + silent placeholders + multi-verse + drum-in-sheet, all in one cohesive change.

The work has three pillars:

1. **Demolish the other Writer modes.** Delete the Track and Classic layouts entirely. Drop the `WriterLayout` enum, the `AppSettings.writerLayout` field, the `setWriterLayout` setter, and the layout picker in the Writer header. Sheet becomes the only Writer view.
2. **Per-block lyrics with silent placeholders + visual instance duplication for `section.repeat`.** Replace `SongSection.lyrics: String?` with `SongBlock.lyrics: List<String>` (one entry per visible instance) + `SongBlock.isSilent: bool`. **`section.repeat = N` renders N stacked `_SectionInstance` widgets**, each with its own harmony bar row and its own lyric bar row. Chord blocks are SHARED across instances (one source of truth); lyric text is PER-INSTANCE (`block.lyrics[instanceIndex]`). The chord sheet (`harmony_chord_sheet.dart`) edits exactly ONE lyric at a time — the caller passes `instanceIndex` + `currentLyric`, the sheet returns a single-entry lyrics list, the store slots it via `setBlockLyric(blockId, instanceIndex, text)`.
3. **Surface drum lanes inside each instance.** Each `_SectionInstance` renders one drum strip per drum lane below its harmony+lyrics row, mirroring `_BarRow`'s `Expanded(flex: spanBars)` + wrap-to-4-bars cell math. Drum pattern data is shared across instances. Tile shows the pattern name and opens `drum_pattern_sheet.dart` on tap. Add a section-heading menu entry for "Add drum lane".

The legacy save-lane chip strip beneath the section stays as-is for this plan (deferred polish). Save chips render ONCE per section, NOT per instance.

**Repository:** Muzician Flutter app (Dart + Flutter + Riverpod).

**Base branch:** `writer-glass-retheme`
**Working branch (create first):** `songwriter-sheet-only`

```bash
git checkout writer-glass-retheme
git pull --ff-only
git checkout -b songwriter-sheet-only
```

**Plan file (authoritative — read end-to-end before any code change):**
`docs/superpowers/plans/2026-06-09-songwriter-sheet-only.md`

The plan has 10 tasks. Each task lists exact files, exact code, exact tests, exact `flutter test` commands, and exact commit messages. Follow the order and the code verbatim. Tasks 4–7 and 10 reuse code from the (now-superseded) per-block plan — that plan stays in the repo as a reference and its body is the source of truth for the verbatim snippets.

**Required sub-skill:** `superpowers:executing-plans` (inline, batch with checkpoints) or `superpowers:subagent-driven-development` (fresh subagent per task). Tasks use `- [ ]` checkboxes for tracking.

**Rules:**

1. Read the plan file end-to-end before touching code. Then skim the superseded per-block plan for the verbatim Task 4–7 / 10 snippets that the new plan reuses by reference.
2. Execute tasks 1 → 10 in order. Do not skip ahead. **Task 1 (deletion) must land before Task 2 (enum removal)** — `songwriter_screen.dart` references the enum until Task 1 is done.
3. For each test-driven task: write the failing test first, verify it fails with the expected message, then write the minimum code to make it pass.
4. Commit after every task using the exact commit message from the plan.
5. After every task, run `flutter analyze` over the touched directories and fix any new warnings or errors before committing.
6. After Task 10 Step 5, run `flutter test` (full suite) and `flutter analyze` (whole project). Both must come back clean.

**Key files (per the plan File Structure):**

- **Delete (with `git rm`):**
  - `lib/features/songwriter/songwriter_screen_track.dart`
  - `lib/features/songwriter/songwriter_section_card.dart`
  - `lib/features/songwriter/songwriter_block_tile.dart` *(only if no out-of-feature importers — Task 1 Step 1 confirms via grep)*
  - `lib/features/songwriter/section_lyrics_sheet.dart`
  - `test/features/songwriter/section_lyrics_sheet_test.dart`
  - `test/features/songwriter/songwriter_lyrics_render_test.dart`
  - `test/features/songwriter/songwriter_drum_lane_render_test.dart`
  - `test/features/songwriter/songwriter_section_card_test.dart`
  - `test/features/songwriter/songwriter_section_pills_test.dart`
  - `test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart`
  - `test/models/song_section_lyrics_test.dart`
- **Create:**
  - `test/models/song_block_lyrics_test.dart`
  - `test/models/song_block_silent_test.dart`
  - `test/store/songwriter_block_lyrics_test.dart`
  - `test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
  - `test/features/songwriter/songwriter_sheet_instance_test.dart`
  - `test/features/songwriter/songwriter_sheet_drum_lane_test.dart`
- **Modify:**
  - `lib/models/songwriter.dart`
  - `lib/models/save_system.dart` *(drop enum + AppSettings field)*
  - `lib/schema/rules/songwriter_rules.dart`
  - `lib/store/songwriter_store.dart`
  - `lib/store/settings_store.dart` *(drop setter)*
  - `lib/features/songwriter/songwriter_screen.dart` *(collapse to direct sheet render)*
  - `lib/features/songwriter/songwriter_header.dart` *(remove layout picker)*
  - `lib/features/songwriter/harmony_chord_sheet.dart`
  - `lib/features/songwriter/songwriter_screen_sheet.dart`

**Verified facts (do not re-derive):**

- `MuzicianTheme.textPrimary` (`Color(0xFFF1F5F9)`) for filled chord glyph + drum tile text.
- `MuzicianTheme.textSecondary` (`Color(0xFF94A3B8)`) for lyric text under chord.
- `MuzicianTheme.textMuted` (`Color(0xFF8B9DC3)`) for empty / silent placeholders + drum lane label.
- `MuzicianTheme.orange` (`Color(0xFFFB923C)`) for drum tile background / border (consistent with the Song feature's drum track header).
- `MuzicianTheme.glassBg` / `glassBorder` for editor inputs and empty drum-cell outlines.
- `_replaceLane(sectionId, laneId, (l) => …)` is the existing lane-scoped mutation helper in `songwriter_store.dart`.
- `WriterLayout` enum lives in `lib/models/save_system.dart` and currently includes `classic`, `track`, `sheet`. The `_writerLayoutFromName` helper and the `AppSettings.writerLayout` field both go away.

**What NOT to change (out of scope — do not touch):**

- Any file under `lib/features/song/`, `lib/features/fretboard/`, `lib/features/piano/`, `lib/features/piano_roll/`, `lib/features/instrument_shared/`, `lib/features/save_system/`.
- `songwriter_structure_editor.dart`.
- `songwriter_undo.dart`.
- `drum_pattern_sheet.dart` (use it as-is from the prior drum-lane plan).
- `harmony_chord_sheet.dart` chord-picker UI structure — only ADD lyric inputs + silent toggle; do not restyle the existing picker.
- Save-lane chip render (existing `_SaveLaneChip` wrap row stays).

**Out-of-scope features (explicitly deferred — do not implement):**

- Bar-quantized syllable / melismatic alignment inside a chord cell.
- Karaoke playback scroll.
- Sheet-variant drum-pattern inline mini-grid previews (tile shows pattern name only).
- Auto-shrinking the verse list when `section.repeat` decreases (storage keeps user input; UI clamps editor).
- Re-introducing Track / Classic layouts as a toggle.
- Promoting the save-lane chip strip to a full-width bar-aligned row.

**Risks to watch:**

- **Task 1 / 2 ordering:** `songwriter_screen.dart` and `songwriter_header.dart` reference both the variants AND the enum. Land Task 1 (variant deletion + screen collapse) before Task 2 (enum + setting + picker removal) — otherwise the project will not compile between tasks.
- **`songwriter_block_tile.dart` deletion guard:** run the grep in Task 1 Step 1 first. If any non-songwriter file imports it, skip the delete and report.
- **Existing harmony chord sheet tests** must remain green. `instanceIndex` defaults to 0, `currentLyric` defaults to `''`, `existing` defaults to null — additive API. The new keys (`lyricInput`, `silentToggle`, `confirmSilent`) are not referenced by existing tests.
- **Single-lyric-input contract:** the chord sheet returns a `SongBlock` whose `lyrics` is a SINGLE-ENTRY list (or empty). The caller knows the `instanceIndex` and slots that one entry via `setBlockLyric(blockId, instanceIndex, text)`. Do NOT have the chord sheet emit a full N-entry list — that would clobber the other instances' lyrics.
- **`_SectionInstance` keys** follow the pattern `sectionInstance_<sectionId>_<instanceIndex>`; drum lane rows inside an instance follow `sheetDrumLane_<laneId>_<instanceIndex>`; silent cells follow `silentCell_<blockId>_<instanceIndex>`. Tests rely on these exact patterns.
- **Settings round-trip test:** if `test/models/app_settings_test.dart` (or similar) asserts on `writerLayout`, update or remove that assertion as part of Task 2.
- **Drum-lane bar math** must mirror the harmony `_BarRow`: `perRow = 4`, `Expanded(flex: spanBars.clamp(1, end - i))`, wrap-and-truncate at row boundaries. Drum tiles in instance N must be the same widths as the harmony cells in the SAME instance — both render off the same `section.lengthBars` + same `LayoutBuilder` constraints.
- **Drum / save lanes are NOT per-instance.** Drum patterns and save references are shared. Edits to a drum pattern from one instance's tile mutate the shared pattern — every instance shows the new steps. Only lyrics differ per instance.
- **Empty-drum-bar rendering** is a thin glass-bordered placeholder, not a tap target. Drum blocks are created from the section-heading menu, not by tapping empty drum bars (different from harmony empty-cell taps).
- **Vertical density:** large `section.repeat` values inflate the section height. Acceptable for this plan; collapsible "show first instance only" is a deferred non-goal.

**Verification before reporting "done":**

1. `flutter analyze` → 0 new issues from this branch.
2. `flutter test` → all green (models, store, chord-sheet, alignment, drum-in-sheet, settings, existing harmony / drum-pattern tests).
3. Manual smoke (Task 10 Step 6):
   - Writer opens directly in Sheet layout — no picker, no Track / Classic option anywhere.
   - Add a chord — one instance visible, one lyric row beneath the chord row. Tap a chord cell → chord sheet with one "Verse 1" input.
   - Bump `section.repeat = 3` from the heading pill → three stacked instances of the same harmony row, each labeled `— N of 3 —`, each with its own lyric row.
   - Tap a chord cell in instance 2 → chord sheet labels the input "Verse 2" with the current value of `block.lyrics[1]`. Edit, save → only instance-2 lyric row updates.
   - Toggle silent in the chord sheet → placeholder dot replaces the chord glyph across ALL instances (chord state shared). Lyric edit still slots only to the tapped instance.
   - Lower `section.repeat = 1` → only one instance visible. Bump back to 3 → previously-typed verse-2/3 lyrics reappear in correct rows.
   - Section menu → "Add drum lane" → drum strip appears under each instance, identical tiles. Tap any tile → drum-pattern sheet → toggle steps → close → reopen from a DIFFERENT instance → same steps visible (pattern shared).
   - Legacy session JSON with `writerLayout` and/or `lyrics` keys loads cleanly (no crash, those keys silently dropped).
4. Hot restart — all of the above survives the debounced session save.

**Final deliverable:**

Draft pull request titled `feat(songwriter): sheet-only writer with instance-duplicated repeats, chord-anchored lyrics, silent placeholders, drum-in-sheet` from `songwriter-sheet-only` into `writer-glass-retheme`. PR body must include:

- Bullet list of the 10 commits.
- Migration callout: "Legacy `WriterLayout` and `SongSection.lyrics` keys silently dropped on load."
- Screen recording covering: layout collapse (only Sheet visible), single instance with one lyric row, repeat → 3 visual instances with independent lyric rows, silent placeholder propagating across instances, drum lane add + per-instance render + shared pattern edits.
- `flutter test` summary line.
- `flutter analyze` summary line.

**Start by reading `docs/superpowers/plans/2026-06-09-songwriter-sheet-only.md` end-to-end. Then execute Task 1.**
