# Dispatch Prompts: Piano Roll Latest Import Navigation

Use these prompts with the orchestrator's delegated subagents. Run them in order unless the orchestrator explicitly combines or splits work.

## Dispatch 1: Task 1 Pure Monophonic Import Normalization

```text
Specialist: state-architect
Model: Codex 5.3
Reasoning effort: xhigh
Task: Add a pure normalization helper that guarantees quantized hum imports remain one-note-at-a-time.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-piano-roll-latest-import-navigation-design.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-latest-import-navigation.md
- /Users/francescolacriola/dev/ws/muzician/lib/schema/rules/mono_pitch_rules.dart
- /Users/francescolacriola/dev/ws/muzician/test/schema/rules/mono_pitch_rules_test.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/schema/rules/mono_pitch_rules.dart
- /Users/francescolacriola/dev/ws/muzician/test/schema/rules/mono_pitch_rules_test.dart
Upstream constraints:
- Keep the new behavior pure and isolated in the hum rule layer.
- Preserve input order for same-tick ties when deciding which note is “earlier”.
- If a later note starts before the earlier note ends, trim the earlier one to the later note's start.
- If that trim would make the earlier note zero-length, drop the earlier note.
- Do not change store or UI code in this task.
Expected output:
- Failing-then-passing tests for overlap trimming and same-tick earlier-note drop
- Minimal rule helper implementation
- Commands run and results
- Commit:
  `git commit -m "fix: normalize hum imports into a mono sequence"`
```

## Dispatch 2: Task 2 Piano-Roll Remembered Range State

```text
Specialist: state-architect
Model: Codex 5.3
Reasoning effort: xhigh
Task: Add remembered latest-import range state to the piano roll and clear it only on later non-import note-add actions.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-piano-roll-latest-import-navigation-design.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-latest-import-navigation.md
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/piano_roll_store_test.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/piano_roll_store_test.dart
Upstream constraints:
- Add an immutable `PianoRollImportedRange` model in `piano_roll.dart`.
- Store it as nullable `latestImportedRange` in `PianoRollState`.
- `appendImportedNotes()` must not create the remembered range itself.
- `appendImportedNotes()` should report the actual created range after truncation.
- Clear `latestImportedRange` on non-import note creation paths:
  - `toggleCellNote()` add path
  - `addNote()`
  - `addNoteStack()`
  - `splitNote()`
- Do not clear it on selection changes, playback, move, resize, or note deletion.
- `clearNotes()` and `reset()` must clear it.
Expected output:
- Failing-then-passing tests for remembered-range ownership, non-import clearing, and created-range reporting
- Minimal immutable model and store helper changes
- Commands run and results
- Commit:
  `git commit -m "feat: remember latest hum import range"`
```

## Dispatch 3: Task 3 Hum Import Handoff

```text
Specialist: state-architect
Model: Codex 5.3
Reasoning effort: xhigh
Task: Normalize hum imports before append, remember the final imported range on success, and clear stale remembered targets when import creates no notes.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-piano-roll-latest-import-navigation-design.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-latest-import-navigation.md
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/schema/rules/mono_pitch_rules.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/hum_to_midi_store_test.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/hum_to_midi_store_test.dart
Upstream constraints:
- Call the new monophonic normalization helper after quantization and before `appendImportedNotes()`.
- On successful import, remember the actual created range using the piano-roll store helper.
- If `createdCount == 0`, clear any previous `latestImportedRange`.
- Preserve the existing selection handoff behavior:
  - if no pre-import selected column, set it to the first imported tick
  - otherwise preserve the existing selection
- Preserve the existing immediate scroll-to-import behavior via `pianoRollScrollToTickProvider`.
- Do not change playback behavior outside the already-approved “stop playback before recording” rule.
Expected output:
- Failing-then-passing tests for latest-range creation, replacement, and stale-target clearing
- Minimal `stopRecording()` handoff changes
- Commands run and results
- Commit:
  `git commit -m "fix: track latest hum import navigation target"`
```

## Dispatch 4: Task 4 Hum Card Jump Action

```text
Specialist: instrument-renderer
Model: Codex 5.3
Reasoning effort: xhigh
Task: Show a secondary `Jump to latest` action in the Hum to MIDI card and wire it to the existing piano-roll scroll signal.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-piano-roll-latest-import-navigation-design.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-latest-import-navigation.md
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_hum_recorder.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/test/features/piano_roll/piano_roll_hum_recorder_test.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_hum_recorder.dart
- /Users/francescolacriola/dev/ws/muzician/test/features/piano_roll/piano_roll_hum_recorder_test.dart
Upstream constraints:
- Keep `Jump to latest` inside the Hum to MIDI card only.
- Make it a secondary action relative to `Record`.
- Read `latestImportedRange` from `pianoRollProvider`.
- Tapping the button must set `pianoRollScrollToTickProvider` to the remembered `startTick`.
- Tapping the button must not change `selectedColumnTick`, selected notes, or playback state.
- The button must disappear automatically after later manual note-add actions clear the remembered range.
Expected output:
- Failing-then-passing widget tests for visibility, jump signaling, and post-manual-add hiding
- Minimal panel/card wiring changes
- Commands run and results
- Commit:
  `git commit -m "feat: add jump to latest hum import action"`
```

## Dispatch 5: Task 5 Docs And Final Verification

```text
Specialist: code-quality
Model: Codex 5.3
Reasoning effort: xhigh
Task: Update piano-roll docs and run the final focused verification for the latest-import navigation work.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/specs/2026-05-24-piano-roll-latest-import-navigation-design.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-latest-import-navigation.md
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
Files to verify:
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll.dart
- /Users/francescolacriola/dev/ws/muzician/lib/schema/rules/mono_pitch_rules.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_hum_recorder.dart
- /Users/francescolacriola/dev/ws/muzician/test/schema/rules/mono_pitch_rules_test.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/piano_roll_store_test.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/hum_to_midi_store_test.dart
- /Users/francescolacriola/dev/ws/muzician/test/features/piano_roll/piano_roll_hum_recorder_test.dart
Upstream constraints:
- Document both new behaviors:
  - `Jump to latest` in the Hum card
  - the post-quantization monophonic guarantee for hum imports
- Run the focused regression suite from the plan.
- Run `flutter analyze` on the touched code and tests.
- Do not broaden scope into unrelated piano-roll docs cleanup.
Expected output:
- Updated docs
- Verification commands and results
- Confirmation of pass/fail status for targeted tests and analyzer
- Commit:
  `git commit -m "docs: document latest hum import navigation"`
```
