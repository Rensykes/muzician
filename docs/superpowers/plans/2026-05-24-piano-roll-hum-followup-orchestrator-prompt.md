# Orchestrator Prompt: Piano Roll Hum Follow-up

Use this prompt with an external orchestrator that will delegate to subagents.

```text
You are the orchestrator for implementing the Piano Roll Hum Import And Playback Follow-up work in the Muzician Flutter app.

Repository root:
/Users/francescolacriola/dev/ws/muzician

Read these files first:
1. /Users/francescolacriola/dev/ws/muzician/AGENTS.md
2. /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
3. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
4. /Users/francescolacriola/dev/ws/muzician/.agents/orchestrator.md
5. The key implementation files currently involved:
   - /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
   - /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
   - /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_toolbar.dart
   - /Users/francescolacriola/dev/ws/muzician/lib/utils/note_player.dart
6. Any specialist docs you assign work to:
   - /Users/francescolacriola/dev/ws/muzician/.agents/state-architect.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/instrument-renderer.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/accessibility-ux.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/code-quality.md

Your job:
- Execute the approved implementation plan task-by-task using subagents.
- Keep the plan as the source of truth for sequencing, constraints, and acceptance criteria.
- Do not redesign the feature unless you hit a real blocker or contradiction.
- Preserve unrelated worktree changes.

Mandatory workflow:
- Follow TDD for every feature or bugfix step in the plan:
  - write the failing test first
  - run it and confirm it fails for the expected reason
  - write the minimal implementation
  - rerun the focused tests and confirm they pass
- Commit after each completed task using the plan's commit message unless a small wording adjustment is required.
- Run `flutter analyze` before declaring the work complete.
- Never use destructive git commands like `git reset --hard` or revert unrelated changes.
- Use `rg` for search.
- Use `apply_patch` for manual file edits.

Product boundaries you must preserve:
- This is a follow-up to the existing hum-to-MIDI piano-roll flow, not a redesign.
- Hum import auto-growth means horizontal timeline expansion only.
- Do not add pitch-range auto-growth.
- Playback starts at `selectedColumnTick` when present.
- If no column is selected, playback falls back to tick `0`.
- Playback runs through the end of the full piano-roll timeline.
- v1 playback scope is transport-only: play and stop only.
- Do not add pause, loop, metronome, scrub, playhead auto-scroll, MIDI export, or duration-accurate note-off scheduling.
- Reuse the current `NotePlayer` as an onset sequencer for v1 playback.
- Keep `appendImportedNotes()` as the single piano-roll import entry point for hum commits.
- Keep the piano roll as the source of truth for editable note data.
- No save-system schema changes.

Required implementation order:
1. Task 1: lock the hum-import regression with store tests and deterministic selection handoff
2. Task 2: add pure playback timing rules and transport models
3. Task 3: build the dedicated playback transport store
4. Task 4: wire playback controls into the piano-roll UI and run accessibility review
5. Task 5: finalize hum/playback coordination, docs, and verification

Suggested delegation map:
- Task 1: `state-architect`
- Task 2: `state-architect`
- Task 3: `state-architect`
- Task 4 implementation: `instrument-renderer`
- Task 4 review: `accessibility-ux`
- Task 5 integration/docs: `state-architect`
- Final audit: `code-quality`

Execution constraints:
- Run tasks in the exact order above.
- Do not start Task 4 until Task 3 exposes a stable playback provider contract.
- Do not start Task 5 until Task 4's focused widget tests pass.
- Keep Task 2 and Task 3 serial; they are tightly coupled.

Key implementation constraints from the approved plan:
- Preferred `appendImportedNotes()` result shape:
  `({int createdCount, bool truncated, int? firstStartTick, int? furthestEndTick})`
- `appendImportedNotes()` must:
  - filter invalid durations before mutation
  - expand only when `furthestEndTick > currentTotalTicks`
  - avoid adding an extra measure when `furthestEndTick == currentTotalTicks`
  - leave `selectedColumnTick` untouched
- `HumToMidiNotifier.stopRecording()` must:
  - snapshot pre-import `selectedColumnTick`
  - call `appendImportedNotes(imported)`
  - set `selectedColumnTick` to `firstStartTick` only when there was no prior selection and notes were created
  - set `pianoRollScrollToTickProvider` to `firstStartTick` when notes were created
- `HumToMidiNotifier.startRecording()` should stop active playback before starting a new take.
- Add a dedicated transport provider:
  `pianoRollPlaybackProvider`
- Add an injected playback sink provider:
  `pianoRollPlaybackSinkProvider`
- Keep pure timing helpers in:
  `lib/schema/rules/piano_roll_playback_rules.dart`
- The playback store must snapshot piano-roll note data at playback start; mid-run edits should not affect the active transport.
- The playback store should schedule note onsets only and use `NotePlayer` through the injected sink.
- UI must preserve the existing Playback tab location in the Piano Roll screen.
- UI tick labels should stay 1-based even though store state remains 0-based.

What to report after each task:
- what changed
- which files changed
- which tests were added
- which commands were run
- whether the task-specific tests passed
- any plan deviation, if unavoidable

Completion criteria:
- Hum import grows measures horizontally only when needed.
- Exact-boundary imports do not add an extra measure.
- Hum import establishes a deterministic playback start point when there was no prior selected column.
- Dedicated playback timing rules, transport state, and transport store exist and are covered by tests.
- Playback starts from the selected column and runs to the end of the piano-roll timeline.
- Playback is disabled while humming is recording or processing.
- Docs and help text reflect the shipped behavior.
- All targeted tests pass.
- `flutter analyze` passes.
- Manual piano-roll smoke test is attempted and reported.

If you find a contradiction:
- prefer the approved plan for behavior and sequencing
- preserve the locked product decisions above
- surface the contradiction explicitly before proceeding if it changes user-visible behavior
```
