# Piano Roll Scale State And Stack Builder Design

Date: 2026-05-26
Status: Draft written from code audit and approved brainstorming decisions
Scope: Piano Roll scale drawer persistence fix and unified stack builder redesign

## Goal

Solve two related Piano Roll product issues:

1. the Scale drawer loses its selected-scale pill after the drawer is closed
   and reopened
2. the current stack-creation surface is duplicated across `Stack Composer`
   and `Stack Selector`, while also lacking support for advanced custom voicings

The result should:

- keep the selected scale visible and reconstructable across drawer reopen
- replace duplicated stack-creation UI with one coherent `Stack Builder`
- support both quick canonical stacks and advanced custom voicings
- allow users to move between canonical and advanced editing without losing
  work
- cap a stack at 10 notes

## Non-Goals

- no changes to the Piano Roll raw-pointer grid architecture
- no change to note multi-selection semantics introduced earlier
- no new persistence requirement for stack-builder draft state across app relaunch
- no arbitrary per-note durations inside a single stack; stack duration remains
  shared at add time
- no attempt to support every possible chord-analysis edge case beyond the
  quality set already supported by the composer/import rules

## Current State Audit

### Scale drawer

`PianoRollScalePicker` keeps committed selection mostly in widget-local state:

- `_selectedRoot`
- `_selectedScale`
- `_activeCategory`

The widget also consumes `pianoRollPendingScaleProvider` and immediately clears
it after syncing from detection. This means the picker does not have a stable,
shared committed source of truth equivalent to:

- `pianoActiveScaleProvider`
- `activeScaleProvider` on fretboard

Result: after the drawer closes and rebuilds, the pill may disappear even though
the scale highlight is still active on the grid.

### Stack creation

The current stack flow is split across overlapping surfaces:

- `_ComposerSheet` in `piano_roll_screen_v2.dart`
- `PianoRollStackSelector`
- landscape inspector composer fields + add-stack button

All of them revolve around the same limited state:

- `root`
- `quality`
- `durationTicks`

and all eventually call `PianoRollComposerNotifier.addStack()`, which generates
one canonical chord stack from shared rules and inserts it at the selected
column.

This duplicates UX without supporting more advanced voicing needs such as:

- inversions as an explicit choice
- repeated chord tones
- free octave placement
- custom voicings such as `G2 C3 E3 G3 C4` that still represent `C major`

## Locked Product Decisions

- There will be one unified `Stack Builder`.
- The builder exposes two views:
  - `Canonico`
  - `Avanzato`
- Those views do not own separate note lists. They edit the same final stack.
- Canonical stack creation remains available, including inversion control.
- Advanced stack creation supports:
  - note duplicates
  - free octave choice
  - up to 10 notes total
  - editing by both absolute notes and chord-degree shortcuts
- The views must remain interscambiable:
  - switching tabs never resets the stack
  - advanced edits remain readable from canonical view when possible
- When the stack is still musically recognizable but no longer a standard
  canonical voicing, canonical view shows a `custom voicing` state rather than
  resetting or failing.

## Recommended Approach

Use one new shared builder state model and one new shared builder UI.

### Why this approach

- fixes the duplication instead of layering a third stack surface on top
- preserves the quick path for common triads/sevenths
- adds room for advanced voicing work without forcing everyone into an advanced
  editor
- keeps one source of truth for the final inserted notes

## Design

## 1. Scale State Model

Add a committed scale provider for Piano Roll, mirroring piano and fretboard:

- `pianoRollPendingScaleProvider`
- `pianoRollActiveScaleProvider`

### Semantics

- `pending`
  - temporary prefill from detection panel interactions
  - consumed by the drawer when present
  - cleared after transfer
- `active`
  - current committed scale selection shown by the drawer pill
  - cleared only when the user explicitly clears the scale picker

### Result

When the Scale drawer reopens:

- if `active` exists, the drawer reconstructs the selected root, scale, and
  category from `active`
- the pill remains visible
- the highlight state and the drawer state stay aligned

## 2. Unified Stack Builder

Replace the duplicated stack-entry surfaces with a single builder component.

### New product surface

`Stack Builder` becomes:

- one portrait drawer entry
- one landscape inspector section

and replaces:

- `Stack Composer`
- `Stack Selector`
- the separate composer block in landscape

### High-level structure

The builder contains:

1. a header with recognized chord summary
2. a `Canonico` / `Avanzato` view switch
3. shared final stack preview
4. one footer action: `Add Stack`

## 3. Builder Source Of Truth

The builder owns one canonical state model.

State shape:

- `notes`
  - ordered list of absolute notes with octave
  - max 10 notes
- `durationTicks`
- `activeView`
  - `canonical`
  - `advanced`
- derived recognition fields
  - `recognizedRoot`
  - `recognizedQuality`
  - `recognizedInversion`
  - `isRecognized`
  - `isCustomVoicing`

### Core rule

`notes` is the only real stack content.

- `Avanzato` edits `notes` directly
- `Canonico` reads `notes` and may transform `notes`
- `Add Stack` always inserts the current `notes`

No second chord list, no second voicing cache, no duplicate draft model.

## 4. Canonical View

Canonical view is the quick path.

### Controls

- root
- quality
- inversion
- duration

### Minimum inversion support

At least:

- root position
- first inversion
- second inversion

Canonical view exposes one inversion option per unique chord tone in the
recognized canonical chord. For example, triads expose three positions and
seventh chords expose four.

### Behavior

Changing canonical controls transforms the same final `notes` list rather than
throwing it away blindly.

Canonical view also reads the current final stack and shows:

- recognized chord identity, if available
- `custom voicing` badge when the final notes no longer match the normalized
  canonical voicing shape
- `unrecognized custom stack` when recognition fails

## 5. Advanced View

Advanced view is the lossless editor for the final stack.

### Capabilities

- add note
- remove note
- reorder note
- duplicate note
- choose absolute note with octave
- insert via chord-degree shortcuts
- hard cap at 10 notes

### Supported input modes

Both are allowed:

- absolute note entry, e.g. `G2`, `C3`, `E3`
- chord-degree shortcuts, e.g. `1`, `3`, `5`, `7`, `9`

Degree shortcuts resolve into absolute notes relative to the currently
recognized or selected chord context, then write into the same `notes` list.

## 6. Interchangeability Rules

This is the most important behavior contract.

### Tab switching

Changing between `Canonico` and `Avanzato`:

- never clears the stack
- never regenerates automatically
- never changes note count on its own

### Reading advanced stacks from canonical view

Given a final stack such as `G2 C3 E3 G3 C4`, canonical view should still be
able to present:

- root: `C`
- quality: `maj`
- inversion: `2nd`
- status: `custom voicing`

### Editing from canonical after advanced customization

If the user changes root, quality, or inversion from canonical view after
customizing in advanced view, the builder transforms the existing stack
continuously rather than resetting to a minimal close-position triad.

Transformation rules:

- preserve shared duration
- preserve ascending note order
- preserve current note count, up to 10
- regenerate target chord tones according to the new canonical settings
- distribute tones across octaves near the current register so the voicing does
  not jump unnecessarily

This keeps canonical editing useful even after advanced customization.

## 7. Recognition Rules

Recognition is rule-based and deterministic.

### Recognition inputs

From final `notes`:

- derive unique pitch classes
- ignore duplicates for chord identity
- keep the lowest absolute note for inversion detection

### Recognition outputs

- recognized root
- recognized quality, if the pitch-class set matches a supported quality
- inversion from the lowest pitch class
- `isCustomVoicing = true` when:
  - duplicates exist, or
  - note distribution differs from normalized canonical generation, or
  - octave layout is non-standard while identity remains recognized

### Failure mode

If the final note set cannot be reliably mapped back to a supported canonical
quality:

- canonical view remains available
- header shows `Unrecognized custom stack`
- user may still use canonical controls to re-anchor the stack to a recognized
  chord

## 8. Add Stack Behavior

`Add Stack` stops depending on a separate limited composer model.

It always:

- read the builder's final `notes`
- place those notes at `selectedColumnTick` or tick `0` if none is selected
- use the builder's shared `durationTicks`
- keep the existing pitch-range safety and insertion semantics already expected
  by Piano Roll

## 9. Architecture

Responsibility split:

- `models/`
  - builder state and builder-facing note-entry types
- `schema/rules/`
  - canonical stack generation
  - inversion handling
  - recognition from final note list
  - continuous canonical-to-advanced transformation helpers
- `store/`
  - builder state transitions
  - scale active/pending state
  - add-stack dispatch into `pianoRollProvider`
- `features/piano_roll/`
  - unified builder UI
  - scale picker updates to consume committed scale state

This keeps musical logic out of widgets and avoids repeating chord inference in
multiple UI components.

## 10. Testing

### Scale drawer regression coverage

- selecting a scale commits `pianoRollActiveScaleProvider`
- closing and reopening the drawer reconstructs the selected pill
- clearing the scale clears both highlight and active committed state
- pending detection scale pre-fills once, then yields to active state

### Stack builder rules coverage

- canonical generation supports inversion output
- advanced voicing with duplicates remains valid up to 10 notes
- `G2 C3 E3 G3 C4` recognizes as `C maj`, second inversion, custom voicing
- duplicate notes do not break root/quality recognition
- note-count hard cap prevents the 11th note
- canonical edits after advanced customization preserve count and keep a
  continuous register-near result
- unrecognized stacks degrade to `Unrecognized custom stack`

### Widget coverage

- portrait exposes one `Stack Builder` entry instead of separate composer and
  selector flows
- landscape shows one unified builder section
- canonical and advanced tabs display the same final stack preview
- active scale pill persists on drawer reopen

## 11. Risks And Guardrails

### Risk: canonical transformation feels destructive

Mitigation:

- preserve count and register continuity
- make `custom voicing` explicit

### Risk: recognition becomes flaky

Mitigation:

- limit recognition to already supported chord qualities
- degrade clearly to `unrecognized` instead of guessing

### Risk: UI complexity in portrait drawer

Mitigation:

- one builder, two tabs, one footer action
- no duplicated secondary panels

## Success Criteria

The feature is successful when:

- the selected scale pill remains visible after drawer close/reopen
- there is exactly one stack-creation flow in Piano Roll
- users can create both canonical and advanced stacks in the same builder
- canonical and advanced editing remain interscambiable on the same stack
- custom voicings such as `G2 C3 E3 G3 C4` remain recognized as their parent
  chord where possible
- all stack operations respect the 10-note limit
