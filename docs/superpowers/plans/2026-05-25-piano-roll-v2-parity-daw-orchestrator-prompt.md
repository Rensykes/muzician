# Orchestrator Prompt: Piano Roll V2 Parity And DAW Foundation

Use this prompt with an external orchestrator that will delegate to subagents.

```text
You are the orchestrator for implementing the Piano Roll V2 Parity And DAW Foundation work in the Muzician Flutter app.

Repository root:
/Users/francescolacriola/.codex/worktrees/15ad/muzician

Required model and reasoning settings:
- Use fresh subagents per task
- Use high reasoning effort for architecture and review tasks
- Use cheaper/faster models only for tightly scoped mechanical edits after the task context is fully set

Read these files first:
1. /Users/francescolacriola/.codex/worktrees/15ad/muzician/AGENTS.md
2. /Users/francescolacriola/.codex/worktrees/15ad/muzician/docs/superpowers/specs/2026-05-25-piano-roll-v2-parity-daw-design.md
3. /Users/francescolacriola/.codex/worktrees/15ad/muzician/docs/superpowers/plans/2026-05-25-piano-roll-v2-parity-daw.md
4. /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/orchestrator.md
5. Any specialist docs you assign work to:
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/music-theory.md
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/state-architect.md
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/save-system.md
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/instrument-renderer.md
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/accessibility-ux.md
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/code-quality.md
6. If manual mobile verification is reached and an iOS simulator is available:
   - /Users/francescolacriola/.codex/worktrees/15ad/muzician/.agents/skills/serve-sim/SKILL.md

Your job:
- Execute the approved plan task-by-task using subagents.
- Treat the design spec as the source of truth for product behavior.
- Treat the implementation plan as the source of truth for sequencing, task ownership, and completion criteria.
- Preserve unrelated worktree changes.
- Do not redesign scope unless you hit a real blocker or contradiction.

Mandatory workflow:
- Use `superpowers:subagent-driven-development`.
- Dispatch a fresh implementer subagent per task.
- After every task:
  - run spec-compliance review
  - run code-quality review
  - run accessibility review for Tasks 4, 5, and 6
- Do not move to the next task until the current task is approved by the required reviewers.
- Follow TDD for every implementation task:
  - write the failing test first
  - run it and confirm the expected failure
  - implement the minimal code
  - rerun the targeted tests
- Commit after each completed task using the plan’s suggested commit message unless a small wording tweak is necessary.
- Run `flutter analyze` and the required test/build commands before claiming completion.
- Never use destructive git commands like `git reset --hard`.
- Use `rg` for search.
- Use `apply_patch` for manual file edits.

Locked product boundaries you must preserve:
- V2 is the target product surface, but V1 stays available as a compatibility shell until explicit sign-off.
- Piano Roll note data remains canonical in `pianoRollProvider`.
- Shared logic must move out of V1-only and V2-only widget-local state.
- `PianoRollSnapshot` is required.
- `PianoRollSaveStackLoader` stays the cross-instrument importer for Fretboard and Piano saves.
- Hum to MIDI remains mobile-only in this initiative.
- Web must not expose a broken hum-recording path.
- Landscape mode is required.
- No loop mode, velocity lanes, undo/redo, multi-track sequencing, or MIDI export in this initiative.

Required execution order:
1. Task 1: shared theory and import foundations
2. Task 2: shared composer and editor-state de-localization
3. Task 3: piano-roll snapshot persistence
4. Task 4: grid interaction, web support, and landscape foundation
5. Task 5: real V2 shell parity wiring
6. Task 6: documentation, help surface, and full verification

Suggested delegation map:
- Task 1: `music-theory`
- Task 2: `state-architect`
- Task 3: `save-system`
- Task 4: `instrument-renderer`
- Task 5: `instrument-renderer`
- Task 6 implementation/docs integration: `state-architect`
- Task 4–6 review: `accessibility-ux`
- Every task review: `code-quality`

Key implementation constraints:
- Keep `lib/utils/note_utils.dart` as the single source of truth for chord and scale catalogs.
- Keep import mapping and stack-building helpers pure and UI-free.
- Keep `PianoRollState` focused on canonical editor state.
- Do not move arbitrary panel-open or shell-only layout state into the canonical piano-roll store.
- `PianoRollSnapshot` must persist full-session editor data but must not persist playback transport state, `selectedNoteIds`, or `latestImportedRange`.
- The stack-import loader must continue to ignore full Piano Roll snapshots and focus on Fretboard/Piano imports.
- V2 transport must read the real playback provider.
- V2 composer controls must read shared composer state rather than local widget state.
- Preserve the grid’s existing raw `Listener`, pinch, resize, long-press delete, and playback auto-scroll invariants.
- If `piano_roll_grid.dart` or `piano_roll_save_stack_loader.dart` become too large to review safely, split them by responsibility during the task rather than waiting for a later refactor.
- Web support must include editor, playback, save/import, detection, and persistence. Hum capture is the only excluded path.
- If an iOS simulator is available at the final verification step, use `serve-sim` to verify portrait, landscape, and gesture behavior.

What to report after each task:
- what changed
- which files changed
- which tests were added or updated
- which commands were run
- whether the targeted tests passed
- whether required reviewers approved
- any plan or spec deviation, if unavoidable

Completion criteria:
- V2 exposes every currently shipped V1 Piano Roll capability.
- V1 and V2 share provider-backed composer/editor logic.
- Piano Roll has first-class save/load through `PianoRollSnapshot`.
- Cross-instrument stack import still works for Fretboard and Piano saves.
- Theory/import duplication is removed from Piano Roll widgets.
- Web builds cleanly with Hum to MIDI safely gated out.
- Landscape mode works and is documented.
- Docs and help text are updated.
- Targeted tests pass.
- `flutter analyze` passes.
- `flutter build web --release` passes.
- Manual simulator verification is attempted and reported when environment allows.

If you find a contradiction:
- prefer the design spec for behavior
- prefer the implementation plan for sequencing
- surface the contradiction explicitly before proceeding if it changes user-visible behavior
```
