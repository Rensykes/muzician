# Orchestrator Prompt: Shared Instrument Foundation

Use this prompt with an external orchestrator that will delegate to subagents.

```text
You are the orchestrator for implementing the Shared Instrument Foundation work in the Muzician Flutter app.

Repository root:
/Users/francescolacriola/dev/ws/muzician

Read these files first:
1. /Users/francescolacriola/dev/ws/muzician/AGENTS.md
2. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-shared-instrument-foundation-design.md
3. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-shared-instrument-foundation.md
4. /Users/francescolacriola/dev/ws/muzician/.agents/orchestrator.md
5. Any specialist docs you assign work to:
   - /Users/francescolacriola/dev/ws/muzician/.agents/music-theory.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/state-architect.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/instrument-renderer.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/code-quality.md

Your job:
- Execute the implementation plan task-by-task using subagents.
- Keep the design spec and the implementation plan as the source of truth.
- Do not redesign the scope unless you hit a real contradiction or blocker.
- Preserve unrelated worktree changes.

Mandatory workflow:
- Follow TDD for each task:
  - write the failing test
  - run it and confirm it fails for the expected reason
  - write the minimal implementation
  - rerun the focused tests
- Commit after each task using the plan's commit message unless a small wording adjustment is necessary.
- Run `flutter analyze` before declaring completion.
- Never use destructive git commands like `git reset --hard`.
- Use `rg` for search.
- Use `apply_patch` for manual file edits.

Product boundaries you must preserve:
- This is shared Fretboard and Piano work only.
- No piano-roll feature work unless needed for compile safety.
- No save-format migration.
- Internal provider payloads stay canonical.
- Shared contextual spelling is required on harmonic tool surfaces.
- Raw fret bubbles and raw piano key labels remain canonical in this initiative.
- The shared detection catalog must come from `scaleIntervals` and `chordIntervals`.

Required implementation order:
1. Task 1: harmonic-analysis value objects and failing theory tests
2. Task 2: exact-note-aware shared detection, parity, ranking, and formatting
3. Task 3: Fretboard detection and picker integration
4. Task 4: Piano detection and picker integration
5. Task 5: regression verification and docs alignment

Suggested delegation map:
- Task 1 and Task 2: `music-theory`
- Task 3: `instrument-renderer`, with `state-architect` review if provider routing changes
- Task 4: `instrument-renderer`, with `state-architect` review if provider routing changes
- Task 5: `code-quality`

Key implementation constraints:
- Keep shared theory logic in `lib/utils/note_utils.dart`.
- Use shared value types from `lib/models/harmonic_analysis.dart`.
- Do not add instrument-local detection catalogs.
- Do not parse formatted display strings back into provider payloads when typed result objects already contain canonical data.
- Preserve compatibility wrappers for existing `detectFirstChord` and `detectChordsAndScales` callers unless the plan explicitly replaces them.

What to report after each task:
- what changed
- which files changed
- which tests were added
- which commands were run
- whether the task-specific tests passed
- any deviation from the design spec or plan

Completion criteria:
- both instruments use the shared typed harmonic result APIs
- scale detection matches the full picker catalog
- harmonic labels use shared contextual spelling helpers
- canonical provider payloads remain intact
- targeted tests pass
- `flutter analyze` passes
- final summary references the design spec and implementation plan above

If you find a contradiction:
- prefer the design spec for product behavior
- prefer the implementation plan for sequencing
- surface the contradiction explicitly before proceeding if it changes user-visible behavior
```
