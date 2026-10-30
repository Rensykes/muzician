# Melody Block Piano-Roll Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Display each Melody placement's actual note shape inside its wrapped timeline blocks.

**Architecture:** Provide the existing Melody timeline with its current note patterns and measure length. A non-interactive theme-aware CustomPainter maps pattern notes into the visible segment's local tick window, repeating and clipping them according to Writer playback. Pitch scaling is derived once per pattern, not separately per wrapped segment.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test; existing Writer models and StudioPalette.

**Spec:** `docs/superpowers/specs/2026-10-28-melody-block-note-preview-design.md`

## Global Constraints

- Note previews are visual only; block tapping, resize handles, menus, accessibility, playback and persistence are unchanged.
- Loop from occurrence start; clip to pattern loop, block, segment and section edges; wrapped continuations retain their actual musical offset.
- Maintain Studio theme styling, readable names and compact/wide layouts; empty and missing patterns draw no fabricated notes.
- Follow repository AGENTS.md, update relevant Writer guides and README, and verify populated runtime visuals at compact and wide sizes.

## Review Focus

- A segment starts mid-note or mid-loop: draw only the visible slice, never restart the melody (Task 1).
- Pattern lengths not divisible by a bar: loop at exact tick length rather than bar boundaries (Task 1).
- Automatic lane repeats use their own occurrence start, not the source block's original absolute bar (Task 1).
- Empty, malformed, missing or incompatible patterns do not produce ghost notes or throw (Task 1).
- Updating a shared pattern repaints every linked block without affecting edit and resize gestures (Task 1).

## File Map

- `lib/features/songwriter/songwriter_melody_timeline.dart`: integrate non-interactive preview and keep gestures/labels intact.
- `lib/features/songwriter/songwriter_melody_preview.dart`: note-window geometry and theme-aware painter.
- `lib/features/songwriter/songwriter_screen_sheet.dart`: provide resolved pattern data and project timing.
- `test/features/songwriter/songwriter_melody_preview_test.dart`: geometry and painter/widget tests.
- `test/features/songwriter/songwriter_pattern_lane_test.dart`: linked updates and existing interaction regressions.
- `docs/songwriter.md`, `docs/song_writer_guide.md`, `README.md`: shipped behavior.

### Task 1: Draw playback-aligned note previews

**Files:** Create `lib/features/songwriter/songwriter_melody_preview.dart`, `test/features/songwriter/songwriter_melody_preview_test.dart`; modify `lib/features/songwriter/songwriter_melody_timeline.dart`, `lib/features/songwriter/songwriter_screen_sheet.dart`, `test/features/songwriter/songwriter_pattern_lane_test.dart`, `docs/songwriter.md`, `docs/song_writer_guide.md`, `README.md`.

**Interfaces:** Consume `NotePattern`, `NotePatternNote`, `MelodyOccurrence`, `SongwriterConfig.measureTicks` and context-resolved `StudioPalette`. Produce `melodyPreviewNotes({required NotePattern pattern, required int segmentStartTick, required int segmentEndTick})` returning clipped tick intervals and MIDI pitches relative to the occurrence; and `SongwriterMelodyPreview` drawing those intervals with pattern-wide pitch scaling. `SongwriterMelodyTimeline` receives `Map<String, NotePattern>` and measure ticks from the watched project.

- [ ] Add tests with a 24-tick pattern and measure length 16: notes at ticks 0–4, 12–20 and 22–26; window 16–48 shows clipped intervals 16–20, 22–24, 24–28, 36–44 and 46–48, with the final note clipped to each loop boundary. A window starting mid-note draws the visible part and preserves the same vertical pitch coordinate across segments.
- [ ] Add tests for a repeated occurrence starting at bar 4 and a wrapped continuation: compute local offsets from its own start; assert positions match an equivalent first occurrence. Verify a one-bar placement clips longer notes, a zero/negative-length or empty pattern returns no shapes, and missing/incompatible content does not display cached unrelated notes.
- [ ] Add widget tests with linked occurrences: changing the shared pattern changes both previews; Make Unique changes only its occurrence. Ensure block taps and resizing still work and both Studio themes, 320px/1.5 text scale and 1024px width do not overflow.
- [ ] Run `flutter test --no-pub test/features/songwriter/songwriter_melody_preview_test.dart test/features/songwriter/songwriter_pattern_lane_test.dart`; verify expected failures before implementation.
- [ ] Implement bounded geometry matching `flattenPlaybackEvents`: ignore notes with invalid starts, clamp duration to at least one tick, clip each note at its pattern loop and visible placement window, preserve pitch across rows. Pass true local tick windows derived from occurrence start and segment bar range; use the whole segment width, including space behind the resize handle, so wrapping and resizing remain time-aligned.
- [ ] Paint with Studio palette colors and sufficient contrast; use a `Stack` behind the existing name and handle with `IgnorePointer`, clipping to the block. Include theme, note content, time window and scaling in repaint comparisons; do not alter semantics or state.
- [ ] Update Writer documentation and README with the preview; reconcile existing descriptions rather than duplicating. Review `PRODUCT.md`, `DESIGN.md` and `AGENTS.md` for changes needed by the feature.
- [ ] Run `dart format` for changed Dart files, `flutter analyze --no-pub`, and the focused Flutter tests above; expect clean analysis and passing tests. Run the full suite if practical, reporting any failures or timeouts accurately.
- [ ] Capture and inspect populated runtime Writer screenshots at compact and wide viewports in both Studio themes, including a multi-row looping melody. Compare them to the agreed FL Studio-inspired shape; report any build or device blocker rather than claiming visual fidelity from widget tests.
