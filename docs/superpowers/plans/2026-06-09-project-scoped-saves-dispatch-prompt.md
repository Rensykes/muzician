# Project-Scoped Save System — External Agent Dispatch Prompt

Use this prompt to hand off the implementation to a fresh agent session.

---

## Prompt

You are introducing first-class **projects** to the **Muzician** Flutter app's save system. Today the save tree is a flat forest of folders + saves; Song / Songwriter pick from the entire forest; key / tempo / time-signature drift freely. After this change:

- Every project is a top-level folder with a `kind` flag and a `ProjectConfig` (key root pitch class, key scale name, tempo, time signature).
- A single global **Dump** folder holds spare saves on Fretboard / Piano / Roll when no project is selected.
- A persistent `selectedProjectId` is part of `SaveSystemState`.
- Song and Songwriter strictly require `kind == project` (Dump is rejected) and gate the tab behind a non-dismissible picker modal when not satisfied.
- Save browsers in every tab are scoped to the selected project's subtree.
- Song + Songwriter session auto-save is per-project (Map<projectId, snapshot>) instead of a single global slot.
- Editing project config retroactively retunes / retimes every save in the project's subtree (with a confirmation prompt) and refreshes in-memory Song + Songwriter workspaces.
- Old `v2` save blob + both old session blobs + `appDocs/song_audio/` are wiped on first launch of the new code (clean slate confirmed by user).

**Repository:** Muzician Flutter app (Dart + Flutter + Riverpod, `shared_preferences`, `package:uuid`).

**Base branch:** `main`
**Working branch (create first):** `project-scoped-saves`

```bash
git checkout main
git pull --ff-only
git checkout -b project-scoped-saves
```

**Spec file (authoritative — read before any code change):**
`docs/superpowers/specs/2026-06-09-project-scoped-saves-design.md`

**Plan file (authoritative — read end-to-end before Task 1):**
`docs/superpowers/plans/2026-06-09-project-scoped-saves.md`

The plan has **21 tasks**. Each task lists exact files, exact code, exact tests, exact `flutter test` commands, exact commit messages. Follow the order and the code verbatim except where the plan explicitly says "Engineer:" — in those spots you may complete obvious blanks (e.g. mirror Task 7 → Task 8) while keeping the behavior identical.

**Required sub-skill:** Use `superpowers:executing-plans` (inline, batch with checkpoints) OR `superpowers:subagent-driven-development` (fresh subagent per task). Tasks use `- [ ]` checkboxes for tracking.

---

## Rules

1. Read the spec file (12 sections) end-to-end first, then the plan end-to-end. Do not start Task 1 until both are read.
2. Execute tasks 1 → 21 in order. Do not skip ahead.
3. For each task: write the failing test first, run it, see it fail, write the minimum code to make it pass, run it again, see it pass, then commit.
4. One commit per task. Use the exact commit messages from the plan.
5. After every task: run `flutter analyze` over touched directories; fix new warnings before committing.
6. After Task 21 Step 21.1: run the full test suite (`flutter test`); everything must pass.
7. Storage keys are pinned: `@muzician/save-system/v3`, `@muzician/song_sessions/v1`, `@muzician/songwriter_sessions/v1`. The plan's Key Naming Note at the top documents the deviation from the spec (`v2 → v3` because the live key is already `@muzician/save-system/v2` with a hyphen).
8. Pitch class type: `ProjectConfig.keyRootPc` is `int?` (0..11) to match `SongwriterConfig.keyRoot`. Convert to `String?` for `SongProjectConfig.scaleRoot` via `chromaticNotes[pc]` from `lib/utils/note_utils.dart`.

---

## Key facts (do not re-derive)

- `SaveFolder` currently has no `kind`. Today's `SaveSystemState` has `folders`, `saves`, `activeSession`, `hydrated`. Task 2 adds `kind`, `projectConfig`, `selectedProjectId`.
- `lib/store/songwriter_store.dart` currently squats on a folder convention (`_findOrCreateProjectFolderId` matches `state.name` against a top-level folder). Task 10 replaces this with `selectedProjectId`. `acceptVoicingSuggestion` + `acceptThirdAboveSuggestion` change to bail when selection is null or Dump.
- `lib/ui/save_browser_panel.dart` currently shows the full tree. Task 12 adds a `rootFolderId` prop with virtual-root semantics; Tasks 13–14 wire it everywhere.
- `lib/ui/save_tree_browser.dart` is used only by `SongSavePanel`. Task 14 migrates `SongSavePanel` to `SaveBrowserPanel`; `save_tree_browser.dart` is deleted once Step 14.3 confirms zero remaining callers.
- `lib/store/song_session_store.dart` is fully replaced by `lib/store/song_sessions_store.dart` (Task 7) + Song store rewire (Task 9). Delete the old file in Task 9 after the rewire passes tests.
- Existing tests that reference the legacy session keys (`@muzician/song_session/v1`, `@muzician/songwriter_session/v1`) must be updated to v3 / sessions/v1. Failing-test signal is acceptable mid-task; full suite must be green after Task 21.

---

## What NOT to change (out of scope — do not modify)

- `lib/models/song_project.dart` data shape (only `SongProjectConfig` is mutated through the retrofit helper; do not rename fields).
- `lib/models/songwriter.dart` types — extend `SongwriterProjectSnapshot` behavior via the existing `copyWith` only.
- Snapshot subtypes' on-disk shape beyond what `applyProjectConfig` rebuilds (Task 18).
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart` — the stack loader continues to navigate the full tree (it is a separate, orthogonal importer).
- Audio engine, hum-to-midi, drum playback, songwriter playback (drum-lane work is its own plan).

---

## Out-of-scope features (explicitly deferred — do not implement)

- Copying a save from Dump → project (follow-up plan).
- Project export / import / share.
- Per-project namespacing of `appDocs/song_audio/`.
- Project-level palette / library-match scope expansion beyond the existing subtree behavior.
- Multiple Song or Songwriter arrangements per project (a project hosts exactly one of each, via its per-project session blob).

---

## Risks to watch

- **Storage wipe is destructive.** Task 4 unconditionally removes `@muzician/save-system/v2`, the legacy session keys, and the `song_audio` directory on first v3 launch. Verify in tests (Task 4.1) and in the simulator smoke (Task 21.2). Do not soft-fall-back on legacy v2 data.
- **Session swap timing.** Tasks 9 + 10 add `ref.listen` on `selectedProjectId` inside `SongProjectNotifier` and `SongwriterNotifier`. Persist outgoing IMMEDIATELY (bypass debounce) before loading incoming, so a rapid switch does not lose state. Tests `song_project_store_session_swap_test.dart` + `songwriter_store_session_swap_test.dart` cover this — make sure they assert the outgoing snapshot is committed to disk (via the sessions provider) before the incoming load.
- **Retrofit must be atomic.** `applyProjectConfig(retrofit: true)` in Task 18 mutates state once at the end and persists once. Do not re-enter the notifier mid-rewrite.
- **Gate modal must not be dismissible** for Song / Songwriter when no project is selected (`allowCancel: false`). `isDismissible: false`, `enableDrag: false`, `PopScope.canPop: false`. Test verifies the close button is absent (Task 17.1).
- **Lock toast must not stack.** When the user mashes a disabled chip, suppress redundant snackbars (use `glassSnack` w/ dedup or a short cooldown).
- **`SaveBrowserPanel.rootFolderId`** must trap Back navigation at the virtual root. The widget test in Task 12.1 asserts this — do not let Back walk past `rootFolderId.parentId`.
- **Migration test ordering.** `SharedPreferences.setMockInitialValues` must be set BEFORE constructing the `ProviderContainer` in every test; the existing tests in `test/store/save_system_store_test.dart` follow this pattern — mirror it.

---

## Verification before reporting "done"

1. `flutter analyze` → 0 new issues from this branch.
2. `flutter test` → all green.
3. Manual sim smoke per Task 21.2 (6 steps): fresh launch, new project, locked controls, gate modal, Dump fallback, persistence across relaunch.
4. Visual confirm: `ProjectChip` visible in all five tab headers (Fretboard / Piano / Roll / Song / Songwriter).
5. Verify deleted files (`song_session_store.dart`, optionally `save_tree_browser.dart`) are gone from `lib/`.
6. Verify storage keys: open the simulator app data; the only save-system keys present should be `@muzician/save-system/v3`, `@muzician/song_sessions/v1`, `@muzician/songwriter_sessions/v1`, `@muzician/settings/v1`. No `v2` / `_session/v1` keys.

---

## Final deliverable

Open a draft pull request titled `feat(save-system): project-scoped saves with locked config` from `project-scoped-saves` into `main`. The PR body must include:

- Bullet list of the 21 commits (one per task).
- A short note that v1 / v2 save data + `song_audio/` are wiped on first launch (clean-slate migration per spec §9).
- A screen recording of: launch → create project → save on Piano → switch to Songwriter (no gate; locked tempo chip) → edit project config → confirm retrofit dialog → relaunch → state preserved.
- `flutter test` summary line.
- `flutter analyze` summary line.
- Explicit callout: "Copy Dump → project deferred to a follow-up plan."

**Start by reading `docs/superpowers/specs/2026-06-09-project-scoped-saves-design.md` end-to-end, then `docs/superpowers/plans/2026-06-09-project-scoped-saves.md` end-to-end. Then execute Task 1.**
