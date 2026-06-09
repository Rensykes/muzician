# Songwriter Per-Block Lyrics (Silent Placeholders + Multi-Verse) — External Agent Dispatch Prompt

Use this prompt to hand off the implementation to a fresh agent session.

---

## Prompt

You are migrating the Songwriter (Writer) lyrics feature from section-level text blobs to chord-anchored per-block lyrics. The new feature ADDS:
1. **Per-block lyrics aligned with chord cells** — each chord block carries its own lyric line(s), rendered directly under its bar cell.
2. **Silent placeholder blocks** — a new block type with no chord but with lyrics, for instrumental or vocal-only bars.
3. **Multi-verse support** — each block stores a list of lyric lines, one per `section.repeat` pass, stacked vertically under the chord cell.

The current section-level lyric feature (shipped earlier on this branch) is REMOVED — its editor (`section_lyrics_sheet.dart`), its rendering widgets (`_LyricsBlock`, `_LyricsStrip`, `_ClassicLyricsRow`), and its tests are deleted.

**Repository:** Muzician Flutter app (Dart + Flutter + Riverpod).

**Base branch:** `writer-glass-retheme`
**Working branch (create first):** `songwriter-lyrics-per-block`

```bash
git checkout writer-glass-retheme
git pull --ff-only
git checkout -b songwriter-lyrics-per-block
```

**Plan file (authoritative — read end-to-end before any code change):**
`docs/superpowers/plans/2026-06-09-songwriter-lyrics-per-block.md`

The plan has 8 tasks. Each task lists exact files, exact code, exact tests, exact `flutter test` commands, and exact commit messages. Follow the order and the code verbatim.

**Required sub-skill:** Use `superpowers:executing-plans` (inline, batch with checkpoints) OR `superpowers:subagent-driven-development` (fresh subagent per task). Tasks use `- [ ]` checkboxes for tracking.

**Rules:**

1. Read the plan file end-to-end before touching any code. **In particular, internalize the migration policy (legacy `SongSection.lyrics` blobs are discarded silently — no upgrade UI).**
2. Execute tasks 1 → 8 in order. Do not skip ahead.
3. For each task: write the failing test first, verify it fails with the expected message, then write the minimum code to make it pass.
4. Commit after every task using the exact commit message from the plan.
5. After every task, run `flutter analyze` on the touched directories and fix any new warnings or errors before committing.
6. After Task 8 Step 5, run the full suite: `flutter test`. Everything must pass — including the harmony chord sheet tests and the previously landed drum-lane tests.

**Key files you will touch (per the plan File Structure section):**

- Create:
  - `test/models/song_block_lyrics_test.dart`
  - `test/models/song_block_silent_test.dart`
  - `test/store/songwriter_block_lyrics_test.dart`
  - `test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
  - `test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`
- Modify:
  - `lib/models/songwriter.dart`
  - `lib/schema/rules/songwriter_rules.dart`
  - `lib/store/songwriter_store.dart`
  - `lib/features/songwriter/harmony_chord_sheet.dart`
  - `lib/features/songwriter/songwriter_screen_sheet.dart`
  - `lib/features/songwriter/songwriter_block_tile.dart`
  - `lib/features/songwriter/songwriter_section_card.dart`
  - `lib/features/songwriter/songwriter_lane_row.dart` (pass-through only — silent blocks render via existing block-tile path)
- **Delete (with `git rm`):**
  - `lib/features/songwriter/section_lyrics_sheet.dart`
  - `test/features/songwriter/section_lyrics_sheet_test.dart`
  - `test/features/songwriter/songwriter_lyrics_render_test.dart`
  - `test/models/song_section_lyrics_test.dart`

**Verified facts (from the plan addendum — do not re-derive):**

- `MuzicianTheme.textPrimary` (`Color(0xFFF1F5F9)`) for filled chord text.
- `MuzicianTheme.textSecondary` (`Color(0xFF94A3B8)`) for lyric text under chord.
- `MuzicianTheme.textMuted` (`Color(0xFF8B9DC3)`) for empty placeholders + silent dots.
- `MuzicianTheme.glassBg` / `glassBorder` for editor inputs.
- `addLane` returns `void` today (per the drum-lane plan addendum — that plan's signature change has NOT landed yet on this branch unless the drum-lane plan was executed first; assume `void` and use `firstWhere` to find the new lane id after calling `addLane`).
- `_replaceLane(sectionId, laneId, (l) => …)` is the existing helper for lane-scoped mutations.

**What NOT to change (out of scope — do not modify):**

- Any file under `lib/features/song/`, `lib/features/fretboard/`, `lib/features/piano/`, `lib/features/piano_roll/`, `lib/features/instrument_shared/`, `lib/features/save_system/`.
- `songwriter_structure_editor.dart`.
- `songwriter_undo.dart`.
- Drum-lane code added by the companion plan (`SongLaneKind.drum`, `drum_pattern_sheet.dart`, etc.) — those land on the same branch but are not touched here.
- Save-lane code.

**Out-of-scope features (explicitly deferred — do not implement):**

- Bar-quantized syllable markers (intra-cell positioning) or melismatic alignment.
- Karaoke / playback-time scrolling.
- Auto-shrinking the lyric list when `section.repeat` decreases (storage preserves typed verses; UI clamps editor input).
- Lyric translations / multi-language tracks per block.
- Save-lane or drum-lane lyrics (lyrics live on harmony / silent blocks only).

**Risks to watch:**

- The legacy `_LyricsBlock` / `_LyricsStrip` / `_ClassicLyricsRow` widgets — search every layout variant and remove all references before claiming Task 5–7 done. A leftover reference will compile (Dart privacy is per-library) but render dead surfaces.
- The chord sheet's existing harmony tests (`test/features/songwriter/harmony_chord_sheet_test.dart`) must remain green after the API addition. `verseCount` defaults to 1; `existing` defaults to null. The keys `lyricInput_0`, `silentToggle`, `confirmSilent` are new — existing tests should not reference them.
- `setSectionRepeat` now mutates block lyric lists. Verify the existing repeat-test (if any) still passes after the change.
- Silent blocks lay claim to a bar via `startBar` + `spanBars` like chord blocks. The empty-cell tap handler must route through the chord sheet (which can return a silent block via the toggle) — do not introduce a second tap target.

**Verification before reporting "done":**

1. `flutter analyze` → 0 new issues from this branch.
2. `flutter test` → all green (model + store + chord-sheet + alignment suites).
3. Manually exercise all three Writer variants per Task 7 Step 3 and Task 8 Step 5:
   - Add a chord with lyric in each variant.
   - Toggle silent mode in the chord sheet — confirm a dot cell with lyric stacks beneath.
   - Set `section.repeat = 3`, add a chord, type three verse lines — confirm three lines render stacked under the chord cell, aligned with its span.
   - Lower the repeat back to 1 — verses 2 and 3 must remain in storage (UI may hide them while editing).
   - Hot restart — confirm persistence via debounced session save.
4. Confirm legacy stored sessions (with old `SongSection.lyrics` blobs) load without crashing and without surfacing the old text — verify by hand-injecting a session JSON with a `lyrics` string into `SharedPreferences` and reopening the app.

**Final deliverable:**

Open a draft pull request titled `feat(songwriter): chord-anchored per-block lyrics + silent placeholders + multi-verse` from `songwriter-lyrics-per-block` into `writer-glass-retheme`. The PR body must include:

- Bullet list of the 8 commits.
- Migration callout: "Legacy `SongSection.lyrics` blobs are discarded silently on load."
- Screen recording of: add chord + type lyric → toggle silent + type lyric → set `repeat = 3` + type three verses → confirm alignment under chord cells in Sheet variant.
- `flutter test` summary line.
- `flutter analyze` summary line.

**Start by reading `docs/superpowers/plans/2026-06-09-songwriter-lyrics-per-block.md` end-to-end. Then execute Task 1.**
