# Orchestrator Prompt: Piano Roll Latest Import Navigation

Use this prompt with an external orchestrator that will delegate to subagents.

```text
You are the orchestrator for implementing the Piano Roll Latest Import Navigation work in the Muzician Flutter app.

Repository root:
/Users/francescolacriola/dev/ws/muzician

Required model and reasoning settings:
- Use fresh Codex 5.3 subagents for delegated work
- Use reasoning effort: xhigh

Read these files first:
1. /Users/francescolacriola/dev/ws/muzician/AGENTS.md
2. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-piano-roll-latest-import-navigation-design.md
3. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-latest-import-navigation.md
4. /Users/francescolacriola/dev/ws/muzician/.agents/orchestrator.md
5. Any specialist docs you assign work to:
   - /Users/francescolacriola/dev/ws/muzician/.agents/state-architect.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/instrument-renderer.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/code-quality.md

Your job:
- Execute the implementation plan task-by-task using subagents.
- Treat the design spec and implementation plan as the source of truth.
- Do not redesign the feature unless you hit a real contradiction or blocker.
- Preserve unrelated worktree changes.

Mandatory workflow:
- Follow TDD for every task:
  - write the failing test first
  - run it and confirm it fails for the expected reason
  - write the minimal implementation
  - rerun the focused tests and confirm they pass
- Commit after each completed task using the commit messages from the plan unless a small wording adjustment is truly necessary.
- Run `flutter analyze` on the touched code before declaring completion.
- Never use destructive git commands like `git reset --hard`.
- Use `rg` for search.
- Use `apply_patch` for manual file edits.

Product boundaries you must preserve:
- `Jump to latest` is only for the most recent hum/import result.
- The button lives only in the `Hum to MIDI` card for this scope.
- The jump action is navigation only: do not change `selectedColumnTick`, selected notes, or playback state when it is tapped.
- The remembered latest-import target stays available until a later non-import note-add action or a full clear/reset.
- Manual selection changes, scrolling, playback, moving notes, and resizing notes must not clear the remembered import target.
- A later successful hum import replaces the older remembered target.
- A hum import that creates no notes clears the previous remembered target so stale buttons do not linger.
- Hum recording must remain visually monophonic after quantization:
  - if two imported notes overlap, trim the earlier note to the later note's start
  - if trimming would make the earlier note zero-length, drop it
- Keep monophonic normalization in the pure hum rule layer, not in widget code.

Required execution order:
1. Task 1: pure monophonic import normalization
2. Task 2: piano-roll state and remembered-range ownership
3. Task 3: hum-store import handoff and stale-target clearing
4. Task 4: Hum to MIDI card `Jump to latest` UI wiring
5. Task 5: docs and final verification

Suggested delegation map:
- Task 1: `state-architect`
- Task 2: `state-architect`
- Task 3: `state-architect`
- Task 4: `instrument-renderer`
- Task 5: `code-quality`

Important implementation constraints:
- Keep the remembered range model in `lib/models/piano_roll.dart`.
- Keep non-import clearing rules in `lib/store/piano_roll_store.dart`.
- Keep hum import normalization in `lib/schema/rules/mono_pitch_rules.dart`.
- Keep the import-to-range handoff in `lib/store/hum_to_midi_store.dart`.
- Reuse `pianoRollScrollToTickProvider` for the jump action.
- `appendImportedNotes()` must continue to be the piano-roll import entry point.
- `appendImportedNotes()` should report the actual created range after truncation, not only the raw requested range.
- The Hum card button should remain a secondary action relative to `Record`.

What to report after each task:
- what changed
- which files changed
- which tests were added or updated
- which commands were run
- whether the task-specific tests passed
- any spec or plan deviation, if unavoidable

Completion criteria:
- The latest hum import is remembered in piano-roll state and can be jumped to from the Hum card.
- Later non-import note-add actions clear the remembered target and hide the button.
- Empty hum imports clear stale remembered targets.
- Post-quantization hum imports are strictly monophonic.
- Targeted tests pass.
- `flutter analyze` passes on the touched code.
- The final summary references the spec and plan files above.

If you find a contradiction:
- Prefer the spec for product behavior
- Prefer the plan for sequencing and task boundaries
- Surface the contradiction explicitly before proceeding if it changes behavior
```
