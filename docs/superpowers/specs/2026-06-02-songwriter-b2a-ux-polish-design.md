# Songwriter — B2a UX Polish Design

**Date:** 2026-06-02
**Status:** Design approved, ready for implementation plan
**Part of:** Songwriter initiative. A focused feel/clarity pass over the merged B2a tab, done **before** B2b (playback/drag). No new feature surface — read-clarity, safety, and entry friction only.

## Why
A serve-sim walkthrough of the merged B2a tab showed it functions but "feels like a dev tool." Six concrete issues (severity in parentheses) and their approved fixes:

| # | Issue | Fix (approved) |
|---|-------|----------------|
| 1 | Destructive ✕ delete, no confirm, easy mis-tap (High) | **Undo SnackBar** — delete stays instant; a "Deleted — Undo" snackbar restores the section/lane/block at its original index. |
| 2 | No bar ruler / gridlines; blocks float (High) | **Per-section bar ruler** (`1 2 … N`) above the lanes + faint vertical **gridlines** at bar boundaries inside each lane body. |
| 3 | Section control row cramped + cryptic (High) | **Tappable value pills** — `Verse` name · `8 bars ▾` · `2× ▾`; tapping a pill opens a small −/+ stepper popover. |
| 4 | Header truncates ("Songwr…", "120 B…") (Med) | **Drop the bold "Songwriter" title** (nav already says "Writer"); key + tempo chips show full text + the +/⋯ actions. |
| 6 | Roman-numeral value hidden until key set (Med) | **Default new projects to C major** (key chip shows "C major", blocks show I/ii/V immediately). User can change/clear. |
| 7 | Empty state blank (Low) | Short helper line explaining section → lane → block. |

(Finding #5 fast chord entry and #8 drag placement are **out of scope** — chord-wheel is a later pass, drag is B2b.)

## Changes by area

### Store (`lib/store/songwriter_store.dart`)
- `_emptyProject()` config → `keyRoot: 0, keyScaleName: 'major'` (default C major). `newProject()` resets to this.
- Undo support — UI captures the removed object + its index before deletion, then restores via new inserters:
  - `insertSection(SongSection section, int index)`
  - `insertLane({required String sectionId, required SongLane lane, required int index})`
  - `insertBlock({required String sectionId, required String laneId, required SongBlock block})`
  - Each clamps the index and renumbers `order` where relevant. Existing `removeSection/removeLane/removeBlock` stay.

### Section card (`lib/features/songwriter/songwriter_section_card.dart`)
- Replace the inline `_Stepper` cluster with **value pills**: name (editable), `N bars ▾`, `M× ▾`, and a ⋮ overflow (or trailing) action. Tapping a pill opens a stepper popover (`showMenu`/small dialog) bound to `setSectionLength` / `setSectionRepeat`.
- Delete now routes through an undo flow (capture section + index → `removeSection` → SnackBar "Section deleted · Undo" → `insertSection`).
- Add a **bar ruler** row at the top of the card's lane area, sized to `lengthBars`, aligned to the lane body (offset by the lane gutter width).

### Lane row (`lib/features/songwriter/songwriter_lane_row.dart`)
- Lane body `Stack` gets a background **gridline painter** drawing vertical lines at each bar boundary (`barWidth` increments) so block positions read against bars.
- Lane delete + block delete route through the same undo SnackBar flow.

### Header (`lib/features/songwriter/songwriter_header.dart`)
- Remove the `Flexible` "Songwriter" `Text`. Lead with the key chip (or a small left spacer), then tempo chip, then the new-project + ⋮ actions. Chips show full text. Re-verify no overflow at 360 px (the existing overflow regression test updates accordingly).

### Screen (`lib/features/songwriter/songwriter_screen.dart`)
- When `sections.isEmpty`, render a short helper above "Add section": e.g. "Build a song: add a section, add lanes (harmony + saves), drop chord/voicing blocks."

## Out of scope
- Drag move/resize (B2b), playhead/transport (B2b), chord-wheel entry, per-lane instrument selection, audio.

## Success criteria
- Bar numbers + gridlines visible per section; blocks read against them.
- Section row shows labeled pills; bars/repeat editable via popover; meaning unambiguous.
- Deleting a section/lane/block shows an Undo snackbar that fully restores it (incl. position).
- New project starts in C major; harmony blocks show Roman numerals out of the box.
- Header no longer truncates; no RenderFlex overflow at 360 px.
- Empty Writer tab shows guidance.
- `flutter analyze` clean; widget/store tests for inserts + undo + ruler; verified on simulator.
