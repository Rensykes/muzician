# Shared Instrument Foundation Design

Date: 2026-05-24
Status: Draft written from the shared-gap audit, ready for repo review
Scope: Shared Fretboard and Piano foundation work only

## Goal

Close the shared product and code gaps between Fretboard and Piano by upgrading the common harmonic-analysis layer, unifying theory coverage, improving contextual note spelling on harmonic tool surfaces, and adding regression coverage around the new behavior.

This initiative is intentionally cross-cutting but narrow. It improves the shared theory and detection foundation without redesigning the core tap, scroll, save-browser, or instrument-layout flows.

## Problem Statement

The current shared foundation has four material shortcomings:

1. Detection collapses selections into pitch classes too early, so exact-note context such as bass note and inversion is lost.
2. Scale detection is narrower than the picker catalog, so the app can highlight more scales than it can detect.
3. Harmonic labels are effectively sharp-only, which produces musically awkward labels such as `A#` where `Bb` is the expected reading.
4. There is no focused automated coverage protecting the shared theory helpers or the two detection panels.

These gaps affect both instruments, so they should be solved in the shared foundation rather than patched independently in Fretboard and Piano.

## Locked Decisions

These decisions are part of this design and should not be re-opened during implementation unless a real blocker appears:

- This work covers Fretboard and Piano only. Piano Roll is out of scope except for incidental compile safety.
- Internal normalized pitch classes stay canonical and compatibility-friendly. The codebase should continue to use one canonical representation internally rather than storing mixed flat and sharp spellings in state.
- Exact-note-aware detection is additive. We are layering richer analysis APIs on top of the current store state instead of rewriting every store to a new internal shape.
- `lib/utils/note_utils.dart` remains the single source of truth for shared chord, scale, detection, and spelling logic.
- Detection parity must use `scaleIntervals` and `chordIntervals` directly rather than keeping a second reduced detection catalog.
- Contextual spelling in this initiative applies to harmonic tool surfaces: detection chips, active picker badges, root chips, and other harmonic labels.
- Raw fret bubbles and raw piano key labels stay on canonical pitch-class rendering in this initiative. Re-spelling every rendered instrument cell is a follow-up project, not part of this scope.
- No save-format migration is required. Saved data remains canonical; user-facing display strings are derived at render time.
- Regression coverage is required before the work is considered complete.

## User Experience

### 1. Better chord detection labels

When the user selects notes that form an inversion, the detection panel should show the musically useful label instead of losing the bass note.

Examples:

- Fretboard and Piano should be able to show `C/E` rather than only `C`
- `Bbmaj7/D` should display that way on the chip even if the internal root remains canonical
- Tapping a detected chord chip should still route into the existing chord picker flow using canonical root and quality values

### 2. Full scale-detection parity

If a scale exists in the picker catalog, the shared detector should be able to return it.

That means the shared detector must consider the full supported catalog:

- major
- minor
- major pentatonic
- minor pentatonic
- blues
- dorian
- phrygian
- lydian
- mixolydian
- locrian
- harmonic minor
- melodic minor
- whole tone
- diminished

The detector should still rank and cap results so the UI remains readable.

### 3. More musical spelling on tool surfaces

Harmonic UI should stop exposing awkward sharp-only output when a flat spelling is the better musical read.

Examples:

- detection chips should prefer `Bb`, `Eb`, `Ab`, and `Db` in common contexts
- picker badges and active titles should use the same shared formatter
- root chips in shared harmonic pickers should use the same display helper so both instruments present the same spelling language

The implementation must preserve canonical internal values so picker interactions and save data stay stable.

### 4. No behavior regression in current interactions

This foundation work should not change:

- tap-to-select behavior
- fretboard scroll guard behavior
- piano scrolling behavior
- current save/load flows
- current chord-loading and scale-highlighting flows

The initiative is successful only if shared theory becomes richer while instrument interactions still feel unchanged.

## Architecture

### 1. Shared harmonic-analysis models

Add a small shared model file for exact-note and harmonic-result types:

- `ExactSelectionNote`
- `ChordDetectionResult`
- `ScaleDetectionResult`
- `NoteDisplayStyle` or an equivalent spelling-policy enum

Responsibilities:

- carry exact MIDI note plus canonical pitch class
- represent bass-note-aware chord results without encoding UI strings into providers
- make formatting an explicit step rather than baking display text into core detection

This file belongs in `lib/models/` because the types are shared value objects used across UI and theory layers.

### 2. Shared exact-note detection API in `note_utils.dart`

Keep the existing public helpers for compatibility, but add richer exact-note-aware entry points.

Required additions:

- exact-note chord detection that can report bass-note-aware results
- exact-note scale detection that still works from pitch-class sets but takes the exact-note model as input
- ranking helpers for ordering detection results
- shared formatting helpers for root labels, chord symbols, and scale labels

Compatibility rules:

- existing callers that still use `detectFirstChord(List<String>)` or `detectChordsAndScales(List<String>)` must keep compiling
- new UI surfaces should move to result-object APIs rather than parsing display strings back into root and quality

### 3. Shared spelling policy

Spelling should be handled as formatting, not storage.

Required behavior:

- internal canonical pitch classes remain normalized
- detected harmonic results expose canonical root, quality, and optional bass
- shared formatter functions produce display labels from those canonical values
- user-selected canonical roots from existing pickers remain stable, but visible labels can prefer a more musical flat form where appropriate

Initial heuristic:

- preserve natural notes as-is
- preserve `F#` as sharp in common contexts
- prefer flat display forms for canonical `A#`, `D#`, `G#`, and `C#` on harmonic labels unless a caller explicitly asks for canonical-sharp output

This is intentionally a conservative first pass. It improves common readability without rewriting the full note-naming system.

### 4. Fretboard integration

The Fretboard detection panel should stop relying only on `selectedNotes`.

Instead it should:

- derive exact selected notes from `selectedCells` plus the active tuning
- call the new exact-note detection API
- display formatted chord and scale chips from shared result objects
- send canonical root and quality data into `pendingChordProvider`
- send canonical root and scale name into `pendingScaleProvider`

Fretboard chord and scale pickers should also adopt the new shared display helpers for root-chip labels and active badges so they stay in sync with detection output.

### 5. Piano integration

The Piano detection panel should:

- derive exact selected notes from `selectedKeys`
- call the same shared exact-note detection API
- format harmonic labels through the same shared helpers as Fretboard
- stop parsing display strings where a typed result object is available

Piano chord and scale pickers should use the same root-label helpers as Fretboard so the two instruments present one harmonic vocabulary.

### 6. Persistence and compatibility

No schema migration is required.

Implementation rules:

- keep persisted roots and qualities canonical
- do not store display spellings as the source of truth
- if a snapshot still captures a `symbol`, treat it as derived convenience data rather than canonical harmonic state

This keeps saved data stable while letting display behavior improve immediately.

## Detection Rules

### Chords

Chord detection should still start from exact pitch-class equality, but exact-note input must improve result usefulness.

Required behavior:

- determine the pitch-class set from exact selected notes
- determine the bass note from the lowest selected MIDI note
- match the pitch-class set against `chordIntervals`
- when the bass note is not the root, return a slash chord display result
- sort chord results so the most readable and least surprising match is first

Initial ranking:

1. exact root-position label
2. inversion or slash-chord variant of the same exact pitch-class match
3. remaining exact pitch-class matches in stable order

### Scales

Scale detection should use the full shared catalog and rank matches to avoid noisy UI.

Required behavior:

- use `scaleIntervals` as the only scale catalog
- treat the selected pitch-class set as a subset check, as the app already does conceptually
- prefer scales with fewer extra notes before broader scales
- break ties with the existing scale-category order:
  - common
  - modes
  - extended
- cap the displayed results to the current UI-friendly limit unless a caller explicitly asks for all matches

## UI Display Rules

### Detection Panels

- show formatted chord and scale labels from shared result objects
- do not parse formatted strings back into canonical provider payloads if the typed result already contains canonical data
- keep current chip interactions and animations unchanged

### Chord And Scale Pickers

- root chips should use the shared root-label formatter
- active badges should use the shared chord and scale formatters
- internal selected values remain canonical

### Selected-note chips

Selected-note chips in detection panels may stay canonical in the first pass unless the implementation can apply the harmonic context formatter cleanly without adding ambiguity.

This is intentionally flexible. Harmonic labels are mandatory; selected-note-chip re-spelling is optional within this initiative.

## Testing Strategy

### Unit tests

Add focused unit coverage for:

- exact-note chord detection
- inversion and slash-chord labeling
- full scale-catalog parity
- shared result ordering
- shared formatting and flat-preference heuristics
- compatibility wrappers that preserve current callers

### Widget tests

Add regression tests for both detection panels:

- exact-note selections show the expected chord chip
- tapping a detected chord chip writes canonical root and quality into the pending provider
- tapping a scale chip writes canonical root and scale name into the pending provider
- formatted labels are displayed consistently across both instruments

### Verification

Implementation should finish with:

- targeted `flutter test` runs for new theory and widget tests
- `dart format` on all touched files
- `flutter analyze`

## Non-goals

This initiative does not include:

- new view modes
- new practice or playback tools
- raw fret bubble re-spelling
- raw piano key re-spelling
- MIDI input
- save-system migrations
- broader instrument-specific UX redesign

## Acceptance Criteria

The work is complete when all of the following are true:

- Fretboard and Piano both use the same typed exact-note-aware detection API
- shared scale detection covers the full picker catalog
- harmonic labels on both instruments use the same shared contextual spelling helpers
- the current provider payloads remain canonical and save-compatible
- new unit and widget tests cover the shared theory and both detection panels
- docs are updated where the new behavior changes the documented user-visible output

## Subagent Notes

Recommended ownership split:

- `music-theory`: shared harmonic-analysis models, detection, ranking, spelling, theory tests
- `state-architect`: typed-result integration, provider payload compatibility, any save-surface review
- `instrument-renderer`: Fretboard and Piano detection-panel and picker integration
- `code-quality`: final regression audit, analyzer run, and doc consistency pass

Implementation should be orchestrated as one sequence, not four independent refactors, because the UI integration depends on the shared theory API being stable first.
