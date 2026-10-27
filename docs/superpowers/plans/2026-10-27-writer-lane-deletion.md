# Writer Lane Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Drums, Sample, Guitar Strum and Melody lanes removable from Writer without losing reusable ideas.

**Architecture:** Reuse `SongwriterNotifier.removeLane` and Writer's existing history and Save reconciliation. Add one shared lane delete control with a confirmation dialog, then place it in the existing lane headers including the separate audio row.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-27-writer-lane-deletion-design.md`

## Global Constraints

- Lyrics and Harmony deletion behavior remain unchanged.
- Remove the selected lane and its section placements in one undoable action; preserve reusable saved ideas and audio needed by saves or retained history.
- Keep controls accessible and usable at compact and wide sizes; update the Writer guide and README.
- Preserve existing uncommitted user changes; do not overwrite or revert them.

## Review Focus

- Empty lanes must be deletable without affecting other lanes.
- Repeated sections must delete the underlying lane once across every repeat, with unique control keys.
- Cancel and dialog dismissal must leave Writer state unchanged.
- Saved or shared ideas and audio must survive deletion and undo.
- Long labels, strum source selection and scaled text must remain usable without overflow at compact and wide widths.

---

### Task 1: Lane deletion controls and regression coverage

**Files:**
- Create: `lib/features/songwriter/songwriter_lane_delete_control.dart`
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`, `lib/features/songwriter/songwriter_audio_lane_row.dart`, `docs/songwriter.md`, `README.md`
- Test: `test/features/songwriter/songwriter_harmony_lanes_test.dart`, `test/store/songwriter_lane_ops_test.dart` (and existing audio tests as needed)

**Interfaces:**
- Consumes: `SongwriterNotifier.removeLane({required String sectionId, required String laneId})`, `SongwriterNotifier.undo()`, `SongSection`, `SongLane`, and `showStudioDialog`.
- Produces: `SongwriterLaneDeleteControl({required SongSection section, required SongLane lane, required int instanceIndex})`, a `ConsumerWidget` with control key `deleteWriterLane_<laneId>_<instanceIndex>` and confirmation key `confirmDeleteWriterLane`.

- [ ] **Step 1: Write failing regression tests.** Add widget tests using the existing `pumpSheet` fixture for Drums, audio/Sample, Guitar Strum, and Melody: assert a labeled control appears for each; cancel and dismiss preserve state; confirm removes only the selected lane and its blocks; undo restores it. Include an empty lane, a repeated section with unique control keys and a confirmation from a later repeat, plus compact and wide viewport checks with long lane labels and the strum source selector. Add store coverage asserting reusable saved ideas and audio references/files needed by saved ideas and undo survive deletion; include shared use where practical. Existing primary Harmony and lyrics behavior must remain unchanged.

- [ ] **Step 2: Run the focused tests and verify the new control assertions fail.** Run `flutter test test/features/songwriter/songwriter_harmony_lanes_test.dart test/store/songwriter_lane_ops_test.dart`. Expected: failures identify missing `deleteWriterLane_...` controls before implementation; distinguish any pre-existing failures.

- [ ] **Step 3: Implement the shared control.** In `songwriter_lane_delete_control.dart`, implement the constructor above, an accessible delete tooltip, a Studio confirmation with Cancel and destructive Delete, and impact copy stating that the lane and its contents are removed while saved ideas remain. Confirm calls `removeLane` exactly once, after dismissing the dialog; cancellation and dismissal do nothing.

- [ ] **Step 4: Integrate the control.** Place it in `_DrumLaneRow` and `_PatternLaneRow` in `songwriter_screen_sheet.dart` and `SongwriterAudioLaneRow` in `songwriter_audio_lane_row.dart`, passing `section`, `lane`, and `instanceIndex`. Preserve each label, strum source selector, playback and existing Harmony controls. Use wrapping or flexible layout so controls remain reachable at compact widths.

- [ ] **Step 5: Verify and document.** Run `dart format` on changed Dart paths, the focused tests from step 2, relevant existing audio and Studio Writer tests, and `flutter analyze`. Verify visible layouts at compact and wide viewports, including populated lanes. Update `docs/songwriter.md` and the Writer overview in `README.md` to describe the shipped deletion behavior. Review `AGENTS.md` for any required persistent guidance change.

- [ ] **Step 6: Review the resulting diff.** Confirm no unrelated user changes were overwritten, the spec is covered, and the verification output is recorded. Do not commit unrelated user changes.
