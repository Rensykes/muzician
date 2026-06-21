# Songwriter Drum Lane — External Agent Dispatch Prompt

Use this prompt to hand off the implementation to a fresh agent session.

---

## Prompt

You are adding a dedicated `SongLaneKind.drum` to the **Songwriter** (Writer) tab of the Muzician Flutter app. Drum patterns will be stored on the Songwriter project itself, drum-lane blocks will reference a pattern by id and loop it across a bar span, and the existing `DrumMachineEditor` (currently scoped to the Song feature) will be generalized so the Writer can reuse it. Songwriter transport drum scheduling is **out of scope** — editor audition (existing `DrumPatternPlaybackNotifier`) is in.

**Repository:** Muzician Flutter app (Dart + Flutter + Riverpod).

**Base branch:** `writer-glass-retheme`
**Working branch (create first):** `songwriter-drum-lane`

```bash
git checkout writer-glass-retheme
git pull --ff-only
git checkout -b songwriter-drum-lane
```

> If the `songwriter-lyrics` branch (companion plan) has already merged into `writer-glass-retheme`, that's fine — base off the merge commit. If both branches are in flight simultaneously, expect minor conflicts in `songwriter_screen_track.dart` and `songwriter_section_card.dart` (lyrics adds a footer row; drum adds a menu item). Resolve by accepting both regions.

**Plan file (authoritative — read before any code change):**
`docs/superpowers/plans/2026-06-09-songwriter-drum-lane.md`

The plan has 6 tasks. Each task lists exact files, exact code, exact tests, exact `flutter test` commands, and exact commit messages. Follow the order and the code verbatim. The "Implementation Addendum (Verified Against HEAD)" section at the bottom contains the verified `addLane` signature, verified theme tokens (`violet` / `teal` / `orange`, not the placeholder `accentHarmony` / `accentSave` names from the original task drafts), and the verified `DrumPatternPlaybackNotifier.start` API.

**Required sub-skill:** Use `superpowers:executing-plans` (inline, batch with checkpoints) OR `superpowers:subagent-driven-development` (fresh subagent per task). Tasks use `- [ ]` checkboxes for tracking.

**Rules:**

1. Read the plan file end-to-end before touching any code.
2. **Task 4 is structural — read `lib/features/song/drum_machine_editor.dart` end-to-end before editing it.** The refactor must preserve the existing Song-feature widget tree shape and public API (only the data source becomes injectable).
3. Execute tasks 1 → 6 in order. Do not skip ahead.
4. For each task: write the failing test first, verify it fails, then write the minimum code to make it pass.
5. Commit after every task using the exact commit message from the plan.
6. After every task, run `flutter analyze` over the touched directories and fix any new warnings or errors before committing.
7. After Task 6 Step 7, run the full test suite: `flutter test`. Everything must pass — including `test/features/song/` and `test/store/drum_pattern_playback_store_test.dart`, which exercise the refactored editor.

**Key files you will touch (per the plan File Structure section):**

- Create:
  - `lib/features/songwriter/drum_pattern_sheet.dart`
  - `test/models/songwriter_drum_lane_test.dart`
  - `test/store/songwriter_drum_ops_test.dart`
  - `test/features/songwriter/songwriter_drum_lane_render_test.dart`
- Modify:
  - `lib/models/songwriter.dart`
  - `lib/schema/rules/songwriter_rules.dart`
  - `lib/store/songwriter_store.dart`
  - `lib/features/song/drum_machine_editor.dart` (structural refactor — extract `DrumMachineEditorBody`)
  - `lib/features/songwriter/songwriter_lane_row.dart`
  - `lib/features/songwriter/songwriter_screen_track.dart`
  - `lib/features/songwriter/songwriter_section_card.dart`

**Verified facts (from the plan addendum — do not re-derive):**

- `MuzicianTheme.violet` is the harmony accent. `MuzicianTheme.teal` is the save accent. `MuzicianTheme.orange` is the drum accent (already used by `lib/features/song/song_track_header.dart:19`).
- `addLane` is currently `void`. Task 3 changes its signature to `String addLane(...)` returning the new lane id. All existing call sites ignore the return value, so the change is additive.
- `DrumPatternPlaybackNotifier.start({required DrumPattern pattern, required int tempo})` is the audition API.
- `DrumPattern`, `DrumLaneSequence`, `DrumLaneId` live in `lib/models/song_project.dart`. **Do not duplicate them in the Songwriter model layer.** Import them into `lib/models/songwriter.dart`.

**What NOT to change (out of scope — do not modify):**

- `lib/models/song_project.dart` model definitions (only import from them).
- The `SongProject` storage layer, `songProjectProvider`, or anything under `lib/features/song/` aside from the `drum_machine_editor.dart` refactor itself.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — Sheet variant intentionally does not surface drum lanes in this plan.
- `lib/features/songwriter/songwriter_structure_editor.dart`.
- Any other feature directory (`fretboard`, `piano`, `piano_roll`, `save_system`, `instrument_shared`).

**Out-of-scope features (explicitly deferred — do not implement):**

- Songwriter transport drum scheduling (drum patterns triggering during section playback).
- Sheet variant drum surface / chip strip.
- Cross-project pattern import from `SongProject`.
- Drum tile mini-grid preview (tile shows pattern name only).
- New audio samples / drum-kit selection.

**Risks to watch:**

- The Task 4 refactor must not regress `test/features/song/drum_machine_editor*` widget tests. If any fail because of widget-tree shape changes, restore the outer `Scaffold` / `AppBar` inside the wrapper, not the body.
- `removeDrumPattern` must cascade — clear `block.patternId` on every drum block referencing the removed pattern. Covered by a dedicated test in Task 3.
- The orange accent is shared with the Song feature's drum track header — be consistent. No new color token needed.

**Verification before reporting "done":**

1. `flutter analyze` → 0 new issues from this branch.
2. `flutter test` → all green (including `test/features/song/` and the playback store test).
3. Manually exercise Track + Classic variants per Task 6 Step 8.
4. Confirm drum-pattern edits persist across hot restart.
5. Confirm Sheet variant still renders correctly when a project has drum lanes (lanes are silently ignored, not surfaced).
6. Confirm removing a pattern leaves its block placed with `patternId == null`.

**Final deliverable:**

Open a draft pull request titled `feat(songwriter): drum lane + project-local drum patterns` from `songwriter-drum-lane` into `writer-glass-retheme`. The PR body must include:

- Bullet list of the 6 commits.
- Short note on the Task 4 refactor (extracting `DrumMachineEditorBody`).
- Screen recording of: add drum lane → tap block → edit steps → close → reopen → steps preserved.
- `flutter test` summary line.
- `flutter analyze` summary line.
- Explicit callout: "Songwriter transport drum scheduling deferred to a follow-up plan."

**Start by reading `docs/superpowers/plans/2026-06-09-songwriter-drum-lane.md` end-to-end. Then execute Task 1.**
