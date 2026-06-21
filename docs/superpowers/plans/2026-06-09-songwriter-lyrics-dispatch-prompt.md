# Songwriter Lyrics — External Agent Dispatch Prompt

Use this prompt to hand off the implementation to a fresh agent session.

---

## Prompt

You are implementing per-section lyrics for the **Songwriter** (Writer) tab of the Muzician Flutter app. This is a small, self-contained feature: add a free-text `lyrics` field to `SongSection`, expose a store mutator, and render an editable lyrics block in all three Writer layout variants (Sheet, Track, Classic).

**Repository:** Muzician Flutter app (Dart + Flutter + Riverpod).

**Base branch:** `writer-glass-retheme`
**Working branch (create first):** `songwriter-lyrics`

```bash
git checkout writer-glass-retheme
git pull --ff-only
git checkout -b songwriter-lyrics
```

**Plan file (authoritative — read before any code change):**
`docs/superpowers/plans/2026-06-09-songwriter-lyrics.md`

The plan has 6 tasks. Each task lists exact files, exact code, exact tests, exact `flutter test` commands, and exact commit messages. Follow the order and the code verbatim. The "Implementation Addendum (Verified Against HEAD)" section at the bottom contains verified theme tokens and `InputDecoration` styling — apply those where the original task notes a fallback.

**Required sub-skill:** Use `superpowers:executing-plans` (inline execution, batch with checkpoints) OR `superpowers:subagent-driven-development` (fresh subagent per task, two-stage review). The plan tasks use `- [ ]` checkboxes for tracking.

**Rules:**

1. Read the plan file end-to-end before touching any code.
2. Execute tasks 1 → 6 in order. Do not skip ahead.
3. For each task: write the failing test first, verify it fails with the expected message, then write the minimum code to make it pass.
4. Commit after every task using the exact commit message from the plan.
5. After every task, run `flutter analyze lib/features/songwriter/ lib/models/songwriter.dart lib/store/songwriter_store.dart` and fix any new warnings or errors before committing.
6. After Task 6 Step 5, run the full test suite: `flutter test`. Everything must pass.
7. After Task 6 Step 6 (manual smoke check), run `flutter analyze` with no arguments. Resolve any new analyzer issues.

**Key files you will touch (per the plan File Structure section):**

- Create:
  - `lib/features/songwriter/section_lyrics_sheet.dart`
  - `test/models/song_section_lyrics_test.dart`
  - `test/store/songwriter_lyrics_test.dart`
  - `test/features/songwriter/section_lyrics_sheet_test.dart`
  - `test/features/songwriter/songwriter_lyrics_render_test.dart`
- Modify:
  - `lib/models/songwriter.dart`
  - `lib/store/songwriter_store.dart`
  - `lib/features/songwriter/songwriter_screen_sheet.dart`
  - `lib/features/songwriter/songwriter_screen_track.dart`
  - `lib/features/songwriter/songwriter_section_card.dart`

**What NOT to change (out of scope — do not modify):**

- `lib/features/songwriter/songwriter_structure_editor.dart`
- `lib/features/songwriter/songwriter_undo.dart`
- `lib/features/songwriter/harmony_chord_sheet.dart`
- Any other feature directory (`fretboard`, `piano`, `piano_roll`, `song`, `save_system`, `instrument_shared`).
- Any save-system schema or migration code.

**Out-of-scope features (explicitly deferred — do not implement):**

- Bar-quantized syllable markers (`[C]wo[F]rd` style inline alignment).
- Multi-verse stanzas per section.
- Karaoke / playback highlight sync.
- Drum machine integration (separate plan).

**Theme references (verified — use verbatim):**

- `MuzicianTheme.textPrimary` for filled lyrics text.
- `MuzicianTheme.textMuted` for the "+ lyrics" placeholder.
- `MuzicianTheme.glassBg` + `MuzicianTheme.glassBorder` for the editor's `TextField` background and border.
- `MuzicianTheme.sky` for the editor's focused border.

**Verification before reporting "done":**

1. `flutter analyze` → 0 issues introduced by this branch.
2. `flutter test` → all green.
3. Manually exercise all three Writer variants (Sheet / Track / Classic) per Task 6 Step 6.
4. Confirm lyrics persist across a hot restart (debounced session save fires after 500 ms; wait at least 1 s before restarting).
5. Confirm clearing returns the "+ lyrics" affordance.

**Final deliverable:**

Open a draft pull request titled `feat(songwriter): per-section lyrics` from `songwriter-lyrics` into `writer-glass-retheme`. The PR body must include:

- Bullet list of the 6 commits.
- Screenshot or screen recording of the lyrics flow in the Sheet variant (the primary target).
- `flutter test` summary line.
- `flutter analyze` summary line.

**Start by reading `docs/superpowers/plans/2026-06-09-songwriter-lyrics.md` end-to-end. Then execute Task 1.**
