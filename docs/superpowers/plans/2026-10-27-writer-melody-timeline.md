# Writer Melody Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Give Writer a wrapped, resizable, reusable Melody block timeline with independent lane sounds.

**Architecture:** Keep existing Writer placements, pattern identity, Save System linkage, persistence and playback timing. Replace the Melody lane presentation only; centralize repeat-aware placement validation so gestures, dialogs and store operations agree. Store an optional sound on the lane and carry explicit tone through sequenced playback while retaining the legacy unset behavior.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test, existing Studio theme and Save System.

**Spec:** `docs/superpowers/specs/2026-10-27-writer-melody-timeline-design.md`

## Global Constraints

- Retain wrapped bar rows, Writer styling, both Studio themes, compact/wide layouts and accessible non-gesture actions.
- Melody placements snap to whole bars, remain within section boundaries, and cannot overlap authored or automatic repeated occurrences or silently displace existing repeats.
- Reuse shares pattern and canonical Save; Make Unique detaches only the chosen occurrence. Placement edits do not modify shared melody content.
- Explicit Piano/Clean guitar/Distorted guitar is per lane and independent of performance mapping; unset legacy sound preserves current behavior.
- Do not redesign other lanes, change global guitar preference, or alter note timing, mix, clipping, save recovery or history contracts.
- Follow `AGENTS.md`: tests, formatting, analysis, documentation, real populated compact and wide screenshots; do not discard existing work.

## Review Focus

1. A new placement changes a repeating lane's natural period: reject it if existing automatic occurrences shift (Task 2).
2. A repeated block is clipped at the section edge: display and validate only its visible occupancy, without losing the underlying source (Tasks 2 and 4).
3. Old saves contain a mix of piano and Fretboard patterns: preserve per-pattern sound and current global guitar tone until explicitly changed (Tasks 1 and 3).
4. A stale or missing canonical Save must not silently make an unlinked repeat or erase a block (Tasks 2 and 5).
5. A touch drag crosses a wrapped row or is cancelled during scrolling: commit a single valid placement or no change, never an overlap (Task 4).

## File Map

- `lib/models/songwriter.dart`: optional lane sound enum/serialization/copy.
- `lib/store/songwriter_store.dart`: new-lane defaults, lane sound setter, repeat-aware placement and linked reuse.
- `lib/schema/rules/songwriter_rules.dart`: expanded occurrence representation and Melody placement validation.
- `lib/schema/rules/songwriter_playback_rules.dart`, `lib/store/songwriter_playback_store.dart`: per-sequenced-event instrument/tone and sink dispatch.
- `lib/features/songwriter/songwriter_melody_timeline.dart`: new wrapped timeline and resize interaction.
- `lib/features/songwriter/songwriter_screen_sheet.dart`: integrate timeline, placement dialog and pattern actions while leaving Strum presentation intact.
- Tests mirror changed models, rules, store and feature files; update `docs/songwriter.md`, `docs/song_writer_guide.md`, `README.md`, `PRODUCT.md` and `DESIGN.md` with shipped behavior.

---

### Task 1: Persist per-lane Melody sound

**Files:** Modify `lib/models/songwriter.dart`, `lib/store/songwriter_store.dart`; test `test/models/songwriter_lane_mix_test.dart`, `test/store/songwriter_lane_ops_test.dart`.

**Interfaces:** Produce `enum MelodyLaneSound { piano, cleanGuitar, distortedGuitar }`, `SongLane.melodySound` (`MelodyLaneSound?`), and `SongwriterNotifier.setMelodyLaneSound({required String sectionId, required String laneId, required MelodyLaneSound sound})`.

- [ ] Write tests asserting absent/unknown JSON sound decodes to null, each enum value round-trips, `copyWith` retains it, newly created Melody lanes default to `piano`, existing deserialized lanes stay null, and setting a sound only changes the selected Melody lane with undo/redo and snapshot round-trip.
- [ ] Run `flutter test test/models/songwriter_lane_mix_test.dart test/store/songwriter_lane_ops_test.dart`; confirm the new tests fail because the API is absent.
- [ ] Implement the enum, nullable serialized field, immutable copy and setter. Set Piano only in the new-Melody-lane creation path, not the deserializer; ignore non-Melody lane setter calls.
- [ ] Repeat the focused test command; expect all tests to pass.

### Task 2: Repeat-aware placement and linked reuse

**Files:** Modify `lib/schema/rules/songwriter_rules.dart`, `lib/store/songwriter_store.dart`; test `test/schema/rules/songwriter_overlap_test.dart`, `test/store/songwriter_block_placement_test.dart`, `test/store/songwriter_writer_save_sync_test.dart`.

**Interfaces:** Produce `MelodyOccurrence` with source `SongBlock`, zero-based `startBar`, clipped `endBar`, and `repeatIndex`; `List<MelodyOccurrence> melodyOccurrences({required SongLane lane, required int sectionLengthBars})`; `bool isValidMelodyPlacement({required SongSection section, required SongLane lane, required SongBlock candidate})`; `bool repeatMelodyBlock({required String sectionId, required String laneId, required String blockId, required int startBar})`.

- [ ] Add tests for a 6-bar section with a source in bars 1–2 and repeat 3: occurrences at 1–2, 3–4, 5–6; the generated occurrences are occupied; a candidate extending the source or creating a new placement that shifts the existing repeat origins is rejected. Test an end-clipped repeated occurrence and normal legal adjacent placement with repeat 1.
- [ ] Add store tests asserting repeat creates a new block ID with the same pattern and canonical Save IDs, uses the original span shortened to contiguous available bars, fails without mutation on occupied/invalid/missing content, and one undo removes the new placement. Assert Make Unique detaches only that block and preserves performance mapping.
- [ ] Run `flutter test test/schema/rules/songwriter_overlap_test.dart test/store/songwriter_block_placement_test.dart test/store/songwriter_writer_save_sync_test.dart`; confirm new tests fail.
- [ ] Implement occurrence expansion with `tileLaneBlocks` semantics and clipped display intervals. For a proposed authored-lane change, validate bounds and overlaps against the original expanded occupancy, then compare original versus proposed generated occurrences by source ID and repeat index: existing generated start positions must not shift or disappear; reject any new overlap. Do not reject an unchanged candidate. Route Melody add/move/resize/repeat paths through the same rule without changing other lane kinds.
- [ ] Implement linked reuse via a fresh placement retaining original canonical Save, pattern and recovery content; compute the largest valid length no greater than the original, or return false. Revalidate against current state at commit.
- [ ] Repeat the focused test command; expect all tests to pass.

### Task 3: Route independent lane sounds in Writer playback

**Files:** Modify `lib/schema/rules/songwriter_playback_rules.dart`, `lib/store/songwriter_playback_store.dart`; test `test/schema/rules/songwriter_playback_rules_test.dart`, `test/store/songwriter_playback_test.dart`.

**Interfaces:** Consume `SongLane.melodySound`; produce sequenced-note groups that retain nullable explicit `GuitarTone` in addition to the existing piano/guitar distinction. A null explicit tone for a guitar group means the current shared guitar setting; explicit clean/distorted must reach the guitar sink independently.

- [ ] Add playback tests for three simultaneous Melody lanes playing the same pattern with Piano, Clean and Distorted: assert three correctly routed voice groups and unchanged pitch, duration, onset, volume and pan. Assert an unset legacy lane follows each pattern's performance target and reads the shared tone, while explicit sounds override mapping without modifying it. Assert Harmony and Guitar Strum retain their previous sound.
- [ ] Run `flutter test test/schema/rules/songwriter_playback_rules_test.dart test/store/songwriter_playback_test.dart`; confirm failures for missing explicit sound routing.
- [ ] Extend the sequenced grouping key and injectable guitar sink interface to carry `GuitarTone?`; adapt existing sink overrides and callers. Resolve explicit lane choice at flattening and use global tone only for legacy/null; preserve transport-start snapshot behavior, timing and stop behavior.
- [ ] Repeat the focused test command; expect all tests to pass.

### Task 4: Wrapped Melody timeline and resizing

**Files:** Create `lib/features/songwriter/songwriter_melody_timeline.dart`; modify `lib/features/songwriter/songwriter_screen_sheet.dart`; test `test/features/songwriter/songwriter_pattern_lane_test.dart`, `test/features/songwriter/songwriter_sheet_playhead_test.dart`.

**Interfaces:** Consume `melodyOccurrences`, `isValidMelodyPlacement` and `setBlockPlacement`; produce `SongwriterMelodyTimeline`, receiving section, lane, instance index and the existing edit/action callbacks. Display automatic occurrences distinctly and retain source identity.

- [ ] Write widget tests showing an authored six-bar block as related segments across rows, with one final-edge handle, bar labels and playback highlighting. Test dragging to a valid snapped length, stopping at a neighbor/section end/automatic repeat, crossing a row boundary, cancelling a gesture and one-step undo. Verify Adjust placement can move and resize and shows a meaningful message for repeat conflicts.
- [ ] Add compact 320px/text scale 1.5, 390px and wide 1024px widget tests for both themes: no overflow; visible or accessible edit, action and non-gesture resize controls; broken pattern retains a visible recoverable block.
- [ ] Run `flutter test test/features/songwriter/songwriter_pattern_lane_test.dart test/features/songwriter/songwriter_sheet_playhead_test.dart`; confirm the new tests fail.
- [ ] Implement the new Melody-only timeline with row-wrapped segments, pointer-to-bar hit testing, local preview and one commit on drag end; pointer cancellation does not mutate state. Clamp to the nearest allowed extent and revalidate at commit. Use existing Studio colors, 44px accessible action targets and live-theme routes; keep Guitar Strum's existing rendering unchanged.
- [ ] Update the placement dialog to use the same Melody rule and explain conflicts without disabling its existing move capability. Wire current edit/performance/rename/unique/lane-delete flows into the new timeline.
- [ ] Repeat the focused test command; expect all tests to pass.

### Task 5: Repeat picker and lane sound control

**Files:** Modify `lib/features/songwriter/songwriter_melody_timeline.dart`, `lib/features/songwriter/songwriter_screen_sheet.dart`; test `test/features/songwriter/songwriter_pattern_lane_test.dart`, `test/features/songwriter/songwriter_lane_block_actions_test.dart`.

**Interfaces:** Consume `repeatMelodyBlock` and `setMelodyLaneSound`; provide block action `Repeat / reuse` and lane selector displaying Piano, Clean guitar, Distorted guitar or legacy `Pattern sounds`.

- [ ] Add widget tests selecting Repeat / reuse, selecting a free start, seeing a linked block of the expected shortened span, editing the shared pattern, and making the occurrence unique. Assert occupied automatic repeats cannot be selected, cancellation changes nothing and missing canonical content cannot create a broken copy. Preserve Use existing pattern in another lane/section.
- [ ] Add widget tests for the Sound selector on two lanes: changing one leaves the other lane, performance mapping and global guitar preference untouched; legacy unset shows `Pattern sounds`; selecting each explicit value persists after rebuild.
- [ ] Run `flutter test test/features/songwriter/songwriter_pattern_lane_test.dart test/features/songwriter/songwriter_lane_block_actions_test.dart`; confirm new tests fail.
- [ ] Add a theme-aware destination picker showing free/occupied bars and call the store only for valid selections. Add the lane-level sound disclosure and retain all existing block actions.
- [ ] Repeat the focused test command; expect all tests to pass.

### Task 6: Documentation and end-to-end verification

**Files:** Modify `docs/songwriter.md`, `docs/song_writer_guide.md`, `README.md`, `PRODUCT.md`, `DESIGN.md`; review `AGENTS.md` for persistent rule changes.

**Interfaces:** Consume all preceding tasks; no new production interfaces.

- [ ] Update feature documentation and product/design references to describe actual timeline, repeat restrictions, linked reuse, legacy sound and new lane defaults; reconcile the outdated statement that performance target always determines Writer sound.
- [ ] Run `dart format` on every changed Dart file, `flutter analyze`, and `flutter test` on all test targets named in Tasks 1–5; expect zero analyzer issues and all tests passing. Run broader related Writer history, persistence and playback tests if the changed interfaces affect them.
- [ ] Run populated Writer on compact 390×844 and wide 1024×768 devices/viewports, capture real screenshots in both themes, and inspect wrapped blocks, sound, drag handle, menus and repeat conflicts against the approved mockup and `DESIGN.md`; report any environment limitation honestly.
- [ ] Review `AGENTS.md` after the phase and update it only if persistent architecture or guidance changed; check `git diff` for unrelated changes and ensure no temporary mockup artifacts are included.
