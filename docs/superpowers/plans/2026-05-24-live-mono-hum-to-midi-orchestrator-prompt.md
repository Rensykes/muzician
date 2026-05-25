# Orchestrator Prompt: Live Mono Hum-to-MIDI

Use this prompt with an external orchestrator that will delegate to subagents.

```text
You are the orchestrator for implementing the Live Mono Hum-to-MIDI feature in the Muzician Flutter app.

Repository root:
/Users/francescolacriola/dev/ws/muzician

Read these files first:
1. /Users/francescolacriola/dev/ws/muzician/AGENTS.md
2. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-live-mono-hum-to-midi-design.md
3. /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-live-mono-hum-to-midi.md
4. /Users/francescolacriola/dev/ws/muzician/.agents/orchestrator.md
5. Any specialist agent docs you assign work to:
   - /Users/francescolacriola/dev/ws/muzician/.agents/music-theory.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/state-architect.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/instrument-renderer.md
   - /Users/francescolacriola/dev/ws/muzician/.agents/code-quality.md

Your job:
- Execute the implementation plan task-by-task using subagents.
- Keep the spec and the implementation plan as the source of truth.
- Do not redesign the feature unless you hit a real blocker or contradiction.
- Preserve existing unrelated changes in the worktree.

Mandatory workflow:
- Follow TDD for every feature or bugfix step in the plan:
  - write the failing test first
  - run it and confirm it fails for the expected reason
  - write the minimal implementation
  - rerun tests and confirm they pass
- Commit after each completed task using the commit messages in the plan unless a small wording adjustment is required.
- Run `flutter analyze` before declaring the work complete.
- Never use destructive git commands like `git reset --hard` or revert unrelated changes.
- Use `rg` for search.
- Use `apply_patch` for manual file edits.

Feature boundaries you must preserve:
- Mobile only for v1: Android and iOS.
- Mono only. No polyphonic detection.
- Stable-note behavior. Do not split aggressively on small pitch wobble.
- Live recording UX with light quantization after stop.
- Shared detector/session architecture, with piano roll as the first consumer.
- Imported notes append to the piano roll; they do not replace existing notes.
- Keep the piano roll as the source of truth for final editable notes.
- No save-system format changes in v1.
- The detector path must follow the approved plan’s YIN-style monophonic approach. Do not silently swap in zero-crossing as the final algorithm.

Suggested delegation map:
- Task 1: `music-theory` for pitch/note mapping semantics and detector rule correctness, plus `state-architect` if the orchestrator wants a separate pass on the new immutable models.
- Task 2: `state-architect` for `piano_roll_store.dart` importer, measure expansion, and anchor logic.
- Task 3: `state-architect` for `hum_to_midi_store.dart` and session state flow.
- Task 4: a platform-focused implementation subagent for the `record` adapter and mobile permission wiring. If no platform specialist exists, handle directly but keep the public interface from the plan.
- Task 5: `instrument-renderer` for the piano roll recorder panel and screen wiring, with `state-architect` review if needed.
- Task 6: `code-quality` for final analyzer/test audit plus a human-readable verification summary.

Execution order:
- Run tasks in the exact sequence defined in the plan:
  1. Pure models and mono pitch rules
  2. Piano roll batch import and timeline expansion
  3. Hum session store and fakeable mic session interface
  4. Mobile `record` adapter and platform permissions
  5. Piano roll recorder panel and UI wiring
  6. Docs, full verification, and device smoke test
- Do not start a later task until the prior task’s tests pass.

Important implementation constraints:
- Keep pure musical and segmentation logic in `lib/schema/rules/mono_pitch_rules.dart`.
- Keep recording lifecycle state in `lib/store/hum_to_midi_store.dart`.
- Keep microphone adapter code behind `lib/utils/mic_pitch_session.dart`.
- Add batch import behavior to `lib/store/piano_roll_store.dart`; do not bypass the piano roll store.
- Preserve the insertion anchor behavior from the spec:
  - use `selectedColumnTick` when present
  - otherwise use the first measure boundary after the latest existing note end tick
  - otherwise fall back to tick `0`
- Preserve the user-facing edge cases from the plan:
  - if no stable notes are detected, do not import junk notes
  - if imported notes must be clipped to fit the roll, surface that as feedback

What to report after each task:
- What changed
- Which files changed
- Which tests were added
- Which commands were run
- Whether the task-specific tests passed
- Any spec/plan deviation, if one was unavoidable

Completion criteria:
- All plan tasks implemented
- All targeted tests pass
- `flutter analyze` passes
- The mobile smoke test is attempted and its result is reported
- Final summary references the spec and plan files above

If you encounter a contradiction between the spec and the plan:
- Prefer the spec for product behavior
- Prefer the plan for task breakdown and sequencing
- Surface the contradiction explicitly before proceeding if it changes behavior
```
