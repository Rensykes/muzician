# Orchestrator Prompt: Song Workspace, Pattern Tracks, And Drum Machine

Use this prompt with an external orchestrator that will delegate to subagents.

```text
You are the orchestrator for implementing the Song Workspace, Pattern Tracks, And Drum Machine feature set in the Muzician Flutter app.

Repository root:
/Users/francescolacriola/dev/ws/muzician

Read these files first:
1. /Users/francescolacriola/dev/ws/muzician/AGENTS.md
2. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-27-song-workspace-pattern-daw-design.md
3. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-27-song-workspace-pattern-daw.md
4. /Users/francescolacriola/dev/ws/muzician/.agents/orchestrator.md
5. Any specialist docs needed for the active task:
   - /Users/francescolacriola/dev/ws/muzician/.agents/state-architect.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/save-system.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/instrument-renderer.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/music-theory.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/accessibility-ux.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/code-quality.md

Your job:
- Implement the approved Song workspace spec task-by-task.
- Treat the design spec as the source of truth for user-visible behavior.
- Treat the implementation plan as the source of truth for sequencing, file ownership, tests, and review checkpoints.
- Preserve unrelated worktree changes.
- Do not widen scope unless the spec or plan explicitly allows it.

Mandatory workflow:
- Use `superpowers:subagent-driven-development`.
- Dispatch a fresh implementer subagent for each task in the approved order.
- After every task:
  - run the task’s targeted tests
  - run `code-quality` review
  - run `accessibility-ux` review for UI tasks (`6`, `7`, `8`)
- Do not move to the next task until the current task passes tests and required review.
- Follow TDD for every task:
  - write the failing tests first
  - run them and confirm the expected failure
  - implement the minimal change
  - rerun the targeted tests
- Commit after each completed task using the suggested commit message in the plan unless a minor wording correction is needed.
- Run `dart format` on changed Dart paths before every task completion claim.
- Never use destructive git commands such as `git reset --hard`.
- Use `rg` for text search.
- Use `apply_patch` for manual edits.

Locked product boundaries:
- Add a new `Song` tab without removing the standalone `Roll` tab.
- Keep Song state separate from `PianoRollState`.
- Use clip instances that reference reusable note and drum patterns.
- Editing a shared pattern updates all linked clip instances.
- `Make unique` is explicit and only clones the active clip’s pattern reference.
- Song `tempo`, `time signature`, and `total measures` are global in v1.
- Drum editing is a step sequencer, not a piano-roll percussion editor.
- Import sources are:
  - `PianoRollSnapshot`
  - `PianoSnapshot`
  - `FretboardSnapshot`
- Same-track clip overlap is invalid in v1.
- Pattern-length changes must be validated across all linked instances before saving.
- Song playback must expand note and drum clips into absolute-tick events.
- Drum voices must be synthesized in `NotePlayer`, not introduced through an external sample-pack dependency.

Required execution order:
1. Task 1: Song domain models and pure arrangement rules
2. Task 2: Song project store and UI-scoped selection providers
3. Task 3: Song persistence and save-browser integration
4. Task 4: Snapshot import rules and store import entry points
5. Task 5: Song playback rules, transport store, and drum synthesis
6. Task 6: Song tab shell, arranger timeline, and track controls
7. Task 7: Note-pattern bridge and isolated piano-roll editor host
8. Task 8: Drum-machine editor and clip-edit integration
9. Task 9: Docs, review sweep, and full verification

Suggested specialist ownership:
- Task 1: `state-architect`
- Task 2: `state-architect`
- Task 3: `save-system`
- Task 4: `save-system`
- Task 5: `state-architect`
- Task 6: `instrument-renderer`
- Task 7: `state-architect` with renderer-aware review
- Task 8: `instrument-renderer`
- Task 9: `state-architect` for integration and docs, then `code-quality` and `accessibility-ux` review

Key implementation checks:
- `SongProjectSnapshot` must round-trip track, clip, note-pattern, and drum-pattern data without silent loss.
- `SaveBrowserPanel` must not render Song saves with chord-centric previews.
- Song note-pattern editing must use an isolated provider container or equivalent scope that prevents leakage into the standalone Roll session.
- `piano_roll_import_rules.dart` should remain the exact-MIDI extraction source where it already solves the problem.
- Song transport should snapshot project state at playback start.
- Muting and soloing must affect playback event expansion before scheduling.
- Compact and wide layouts both need verification for the Song tab, note editor, and drum editor.

What to report after each task:
- what changed
- which files changed
- which tests were added or updated
- which commands were run
- whether targeted tests passed
- whether required reviewers approved
- any spec/plan deviation, if unavoidable

Final completion criteria:
- Song tab exists and is navigable.
- Song projects can be saved and loaded.
- Note and drum tracks both work.
- Clip create/move/duplicate/delete flows work.
- Shared pattern editing and `Make unique` both work.
- Import from piano-roll, piano, and fretboard saves works.
- Song transport and drum synthesis work.
- Standalone Roll state is not polluted by Song note-editor sessions.
- Targeted tests pass.
- `flutter analyze` passes.
- `flutter build web --release` passes.

If you find a contradiction:
- prefer the design spec for behavior
- prefer the implementation plan for sequencing
- surface the contradiction explicitly before proceeding if it changes user-visible behavior
```
