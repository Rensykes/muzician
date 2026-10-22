# Instrument UX V2 implementation plan

## Accepted behavior

Keep the native Fretboard/Piano visible while inspecting tools. Keep voicings
in a horizontal carousel. Add explicit **From notes** and **By chord** search.
Temporarily disable Song without removing its implementation or saved data.
This supersedes the original Studio whole-page compact scrolling and available
Song navigation. The existing native renderers and musical/save contracts stay
authoritative.

## 1. Bounded instrument workspace

- Pin the header and playable surface in compact portrait. Allocate remaining
  height to an inspector with persistent tabs and independently scrollable
  content. Keep Scale and Library reachable outside that content scroll.
- Use a side inspector for wide and short landscape layouts. Adapt header and
  auxiliary controls to the available constraints; preserve native key/fret
  geometry instead of shrinking touch regions.
- Keep each tab mounted and preserve tab, collapse, instrument scroll, and
  per-panel scroll through tab switches and theme changes.
- Verify compact, wide, short landscape and scaled text layouts, including a
  populated instrument. Inspector scrolling must not move the instrument.

## 2. Real voicing search

- From notes captures selected pitch classes. Every captured pitch class must
  occur in each result; additional chord tones are allowed. Octave, bass and
  guitar position are not constraints. Empty selection has explicit guidance.
- By chord selects canonical root and quality independently of the note query
  and exposes available generated realizations for current tuning/capo/range.
  Do not silently truncate chords at the piano range boundaries.
- Use the existing full chord vocabulary and real instrument generators.
  Put reusable search/generation rules in `lib/schema/rules/`, with mirrored
  tests. Enumerate within documented practical instrument bounds, deduplicate
  and order deterministically; never claim every theoretical possible voicing.
- Separate query from applied selection. Manual edits refresh the note query;
  applying a candidate updates the instrument and Applied indicator without
  rewriting query, order or carousel offset. Switching search modes retains
  their criteria. “Use current notes” explicitly refreshes the captured query.
- Keep cards horizontal and controls usable in the narrow side inspector.
  Respect spelling preference, key confirmation and committed/pending chord
  contracts. Preserve search state while switching inspector tabs.
- Test containment, independent modes, range/capo, deterministic generation,
  manual edits, application without feedback, horizontal scroll and empty state.

## 3. Song availability

- Keep a visibly disabled Song destination with an accessible explanation,
  “Temporarily unavailable”. Block entry centrally and audit indirect entry
  points/actions. Do not mount the Song workspace through normal navigation.
- Preserve Song sources, serializers, saved arrangements and compatibility.
- Verify tapping/attempting to enter Song cannot switch or mutate the project.

## 4. Integration and delivery

- Implement the three isolated workstreams using fresh GPT-6 Luna agents at
  xhigh reasoning effort. Parent coordinates APIs, reviews diffs and runs
  integration checks; agents own domain implementation.
- Run format on changed Dart files, focused rules/widget/navigation tests,
  relevant existing regressions, and `flutter analyze`.
- Build and inspect populated iPhone and iPad simulator screens; exercise both
  instruments, search/application, panel scrolling, and disabled Song. Capture
  screenshots and compare to the agreed fixed-canvas/horizontal-carousel
  prototype. Fix issues found before completion.
- Update PRODUCT, DESIGN, README and relevant feature guides to describe the
  shipped behavior and its bounded generation limits. Review AGENTS guidance.

## Scope boundaries

This phase changes the instrument/search workflow and Song availability. It
does not introduce instrument undo history, alter persistence schemas, redesign
Writer/Roll, or replace the existing Save/Library workflows. Those prototype
extras are separate work; they are not required for the requested search and
focus fixes.

## Progress

- [x] Inspect existing workspace, picker generation and app navigation.
- [x] Define acceptance checks and file ownership.
- [x] Implement bounded layout and regression tests.
- [x] Implement voicing search and regression tests.
- [x] Disable Song and verify navigation.
- [x] Integrate, analyze and run targeted regressions.
- [x] Verify populated compact/wide simulator screens.
- [x] Reconcile product/design/feature documentation and record results.

Completed verification and delegation outcomes: [delivery record](PROGRESS.md).
