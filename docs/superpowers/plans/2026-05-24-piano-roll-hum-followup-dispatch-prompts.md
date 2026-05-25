# Dispatch Prompts: Piano Roll Hum Follow-up

Use these prompts with the orchestrator's delegated subagents. Run them in order unless the orchestrator explicitly combines or splits work.

## Dispatch 1: Task 1 Regression Lock

```text
Specialist: state-architect
Task: Lock the hum-import regression by tightening `appendImportedNotes()` horizontal-growth behavior and making post-import playback start deterministic when there was no prior selected column.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/piano_roll_store_test.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/hum_to_midi_store_test.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/test/store/piano_roll_store_test.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/hum_to_midi_store_test.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
Upstream constraints:
- Preserve the existing quantization and append semantics; this task is only about deterministic horizontal growth and selection handoff.
- Hum import auto-growth means horizontal timeline expansion only.
- Do not add pitch-range auto-growth.
- Keep `appendImportedNotes()` as the single piano-roll import entry point.
- Preferred result shape if needed:
  `({int createdCount, bool truncated, int? firstStartTick, int? furthestEndTick})`
- `appendImportedNotes()` must:
  - filter invalid durations before mutation
  - expand only when `furthestEndTick > currentTotalTicks`
  - avoid adding an extra measure when `furthestEndTick == currentTotalTicks`
  - leave `selectedColumnTick` untouched
- `HumToMidiNotifier.stopRecording()` should set `selectedColumnTick` to the first imported tick only when there was no prior selection and notes were created.
Expected output:
- Diff implementing the regression fix
- New failing-then-passing tests for:
  - growth across the current end tick
  - exact-boundary no-growth behavior
  - first imported tick selection when no prior column existed
- Commands run and results
- Commit:
  `git commit -m "fix: lock hum import timeline growth behavior"`
```

## Dispatch 2: Task 2 Pure Playback Rules

```text
Specialist: state-architect
Task: Add pure playback transport models and timing helpers for piano-roll playback.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/utils/note_player.dart
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_toolbar.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll_playback.dart
- /Users/francescolacriola/dev/ws/muzician/lib/schema/rules/piano_roll_playback_rules.dart
- /Users/francescolacriola/dev/ws/muzician/test/schema/rules/piano_roll_playback_rules_test.dart
Upstream constraints:
- Build a dedicated playback transport instead of mixing playback state into `pianoRollProvider`.
- Add at minimum:
  - `PianoRollPlaybackStatus`
  - `PianoRollPlaybackEvent`
  - `PianoRollPlaybackState`
- Add pure helpers:
  - `resolvePlaybackStartTick(PianoRollState state)`
  - `resolvePlaybackEndTick(PianoRollState state)`
  - `millisecondsPerTick(int tempo)`
  - `durationForTickDelta(int tickDelta, int tempo)`
  - `groupPlaybackEvents(List<PianoRollNote> notes, int startTick)`
- `resolvePlaybackStartTick()` returns `selectedColumnTick ?? 0`
- `resolvePlaybackEndTick()` returns the full timeline end
- `groupPlaybackEvents()` groups same-tick notes into sorted distinct MIDI-note lists and excludes notes before the playback start tick
- Use the formula:
  `60000 / tempo / ticksPerQuarter`
Expected output:
- Diff adding immutable playback models and pure timing rules
- Failing-then-passing unit tests for grouping, start fallback, end-of-timeline bounds, and tick-duration math
- Commands run and results
- Commit:
  `git commit -m "feat: add piano roll playback timing rules"`
```

## Dispatch 3: Task 3 Playback Transport Store

```text
Specialist: state-architect
Task: Build the dedicated piano-roll playback transport store using the approved pure rules and an injected playback sink.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- /Users/francescolacriola/dev/ws/muzician/lib/models/piano_roll_playback.dart
- /Users/francescolacriola/dev/ws/muzician/lib/schema/rules/piano_roll_playback_rules.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/settings_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/utils/note_player.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_playback_store.dart
- /Users/francescolacriola/dev/ws/muzician/test/store/piano_roll_playback_store_test.dart
- /Users/francescolacriola/dev/ws/muzician/lib/main.dart
Upstream constraints:
- Add:
  `final pianoRollPlaybackProvider = NotifierProvider<...>(...)`
- Add:
  `typedef PianoRollPlaybackSink = Future<void> Function(List<int> midiNotes, double volume);`
- Add:
  `final pianoRollPlaybackSinkProvider = Provider<PianoRollPlaybackSink>(...)`
- The store must read note data from `pianoRollProvider` and volume from `settingsProvider`
- The store must snapshot the piano-roll state at playback start; mid-run edits must not affect the active transport
- Playback starts at the selected column or tick `0` if no selected column exists
- Playback runs through the end of the full piano-roll timeline
- If there are no events at or after the start tick, avoid starting transport and surface a small message like `Nothing to play from the selected column`
- Block playback while hum status is `recording`, `processing`, or `requestingPermission`
- Support only `startPlayback()` and `stopPlayback()` for v1
- Sequence note onsets only; do not attempt duration-accurate note-off scheduling
Expected output:
- Diff adding the playback store and sink injection
- Failing-then-passing tests for:
  - event emission from selected start tick to timeline end
  - stop cancellation
  - clean completion
  - no-op/empty playback
  - blocking during hum recording
  - snapshotting notes at transport start
- Commands run and results
- Commit:
  `git commit -m "feat: add piano roll playback transport"`
```

## Dispatch 4: Task 4 Playback UI Wiring

```text
Specialist: instrument-renderer
Task: Replace the placeholder piano-roll Playback panel with real play/stop transport controls and status messaging wired to the new playback provider.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_toolbar.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_playback_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/main.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_toolbar.dart
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_feature.dart
- /Users/francescolacriola/dev/ws/muzician/test/features/piano_roll/piano_roll_playback_config_test.dart
- /Users/francescolacriola/dev/ws/muzician/lib/ui/core/app_info_panel.dart
Upstream constraints:
- Preserve the existing Playback tab location; do not move playback into the hum card
- `PianoRollPlaybackConfig` should read:
  - `pianoRollProvider`
  - `pianoRollPlaybackProvider`
  - `humToMidiProvider`
- Primary action:
  - `Play` when idle
  - `Stop` while playing
- Disable playback while hum recording or processing is active
- Keep tick labels 1-based in the UI even though state stays 0-based internally
- Required visible states:
  - selected column present:
    `Start: Selected column (tick 17)`
    `Timeline: Plays to end of roll`
  - no selected column:
    `Start: Beginning of roll`
    `Timeline: Plays to end of roll`
  - playing:
    `Status: Playing from tick 17`
    `Current: tick 29`
  - hum disabled:
    `Playback unavailable while humming`
Expected output:
- Diff replacing the placeholder playback card with transport controls
- Failing-then-passing widget tests for idle/playing states, selected-column copy, fallback-start copy, and hum-disabled behavior
- Commands run and results
- Commit:
  `git commit -m "feat: add piano roll playback controls"`
```

## Dispatch 5: Task 4 Accessibility Review

```text
Specialist: accessibility-ux
Task: Review the new piano-roll playback controls for accessibility and UX clarity after the implementation from Task 4 lands.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- /Users/francescolacriola/dev/ws/muzician/lib/features/piano_roll/piano_roll_toolbar.dart
- /Users/francescolacriola/dev/ws/muzician/lib/ui/core/app_info_panel.dart
Files to modify:
- None unless the orchestrator explicitly asks for review comments to be translated into follow-up code changes by another specialist
Upstream constraints:
- Review only
- Focus on:
  - clear text labels for Play and Stop
  - readable disabled state while humming
  - status copy that clearly explains where playback starts
  - tap target comfort in the current card layout
Expected output:
- Review report with findings ordered by severity
- Explicit note if no findings are present
- No code changes
```

## Dispatch 6: Task 5 Hum/Playback Coordination And Docs

```text
Specialist: state-architect
Task: Finalize hum/playback coordination, update piano-roll docs/help text, and make sure transport lifecycle does not disturb existing editor state.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/store/piano_roll_playback_store.dart
- /Users/francescolacriola/dev/ws/muzician/lib/ui/core/app_info_panel.dart
Files to modify:
- /Users/francescolacriola/dev/ws/muzician/lib/store/hum_to_midi_store.dart
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
- /Users/francescolacriola/dev/ws/muzician/lib/ui/core/app_info_panel.dart
Upstream constraints:
- Starting a hum take should stop active playback first
- Playback should refuse to start while hum status is `recording` or `processing`
- Playback completion should not clear `selectedColumnTick`
- Manual Stop should not modify note selection or imported-note selection state
- No save-system schema changes
- Docs must reflect:
  - horizontal timeline expansion only
  - playback starts from the selected column
  - playback runs to the end of the roll
  - no pitch-range auto-growth in this follow-up
Expected output:
- Diff finalizing coordination and doc/help updates
- Commands run and results
- Commit:
  `git commit -m "docs: describe piano roll hum follow-up behavior"`
```

## Dispatch 7: Final Audit

```text
Specialist: code-quality
Task: Audit the completed piano-roll hum follow-up for correctness, regressions, test coverage, and verification discipline.
Files to read first:
- /Users/francescolacriola/dev/ws/muzician/AGENTS.md
- /Users/francescolacriola/dev/ws/muzician/docs/piano_roll.md
- /Users/francescolacriola/dev/ws/muzician/docs/superpowers/plans/2026-05-24-piano-roll-hum-followup.md
- All files changed by Tasks 1-6
Files to modify:
- None unless the orchestrator explicitly asks for a follow-up fix pass
Upstream constraints:
- Review-first mindset
- Findings should focus on bugs, regressions, race conditions, missing tests, or behavior mismatches with the approved plan
- Verification must include:
  - `flutter test test/store/piano_roll_store_test.dart`
  - `flutter test test/store/hum_to_midi_store_test.dart`
  - `flutter test test/schema/rules/piano_roll_playback_rules_test.dart`
  - `flutter test test/store/piano_roll_playback_store_test.dart`
  - `flutter test test/features/piano_roll/piano_roll_playback_config_test.dart`
  - `flutter analyze`
Expected output:
- Review report with findings ordered by severity and file references
- Explicit note if no findings are present
- Verification summary listing commands run and outcomes
```
