# Piano Roll V2 Parity And DAW Foundation Design

Date: 2026-05-25
Status: Draft written from repo audit, ready for repo review
Scope: Piano Roll V1 to V2 parity, shared logic extraction, piano-roll persistence,
web readiness, and landscape mode

## Goal

Turn Piano Roll V2 from a mostly visual shell into the real product surface,
while preserving every shipped V1 behavior, extracting shared logic out of
widgets, and adding the missing DAW-management foundations:

- first-class piano-roll save/load
- cross-instrument stack import from Fretboard and Piano
- mobile-only Hum to MIDI with safe web fallback
- adaptive landscape layout
- shared UI-agnostic logic that both V1 and V2 can render

## Current State Audit

The audit shows a split product:

1. V1 is the real editor surface. It lives in `lib/main.dart` and composes the
   working playback, edit, pitch, scale, hum, import, detection, and grid
   widgets.
2. V2 exists as `lib/features/piano_roll/piano_roll_screen_v2_mockup.dart`,
   but it still owns local fake state for transport and chord-composer fields.
3. The grid is real and already advanced, but it is monolithic:
   `lib/features/piano_roll/piano_roll_grid.dart` is 1013 lines.
4. The save-import UI is also monolithic:
   `lib/features/piano_roll/piano_roll_save_stack_loader.dart` is 701 lines.
5. Shared theory and import helpers are still duplicated across widgets:
   - `piano_roll_stack_selector.dart`
   - `piano_roll_save_stack_loader.dart`
   - `piano_roll_detection_panel.dart`
6. The shared save system has only `FretboardSnapshot` and `PianoSnapshot`.
   There is no `PianoRollSnapshot`, so Piano Roll can import from other
   instruments but cannot persist itself as a first-class session.
7. Hum to MIDI is wired for mobile flows, but there is no explicit V2/web
   capability contract yet.

## V1 Capability Inventory

| Capability | Current owner | V2 status | Required target |
|---|---|---|---|
| Playback transport and timeline config | `lib/features/piano_roll/piano_roll_toolbar.dart` | Mock transport strip only | Shared provider-backed transport widgets in both shells |
| Edit tool + snap | `lib/features/piano_roll/piano_roll_toolbar.dart` | Missing | Shared edit inspector in both shells |
| Pitch window + clear | `lib/features/piano_roll/piano_roll_toolbar.dart` | Missing | Shared pitch inspector in both shells |
| Scale highlight picker | `lib/features/piano_roll/piano_roll_scale_picker.dart` | Only a fake V2 chip | Shared scale panel plus live header/dock summaries |
| Hum to MIDI | `lib/features/piano_roll/piano_roll_hum_recorder.dart` | Missing | Capability-gated utility surface |
| Add chord stack | `lib/features/piano_roll/piano_roll_stack_selector.dart` | Local-only mock fields | Shared composer state + V1/V2 renderers |
| Load stack from Fretboard/Piano saves | `lib/features/piano_roll/piano_roll_save_stack_loader.dart` | Missing | Shared import rules + reusable import panel |
| Detection panel | `lib/features/piano_roll/piano_roll_detection_panel.dart` | Missing | Shared analysis panel |
| Selected-column status | `lib/main.dart` footer text | Missing | Shared status chip/readout |
| Grid gestures, playback playhead, scroll-to-tick | `lib/features/piano_roll/piano_roll_grid.dart` | Reused directly | Preserve behavior, then extend for web/landscape |
| Latest hum import navigation | `piano_roll_hum_recorder.dart` + store tests | Missing | Same provider contract exposed in V2 |
| Piano roll save/load | none | none | New `PianoRollSnapshot` + save panel |

## Brainstormed Approaches

### Option 1: Port V1 widgets directly into the V2 shell

Pros:
- fastest visible parity
- least file churn up front

Cons:
- keeps widget-local product logic alive
- preserves duplicated theory/import code
- makes future web and landscape support harder
- leaves V1 and V2 coupled by copy/paste rather than contracts

### Option 2: Extract a shared piano-roll workspace foundation, then recompose V1 and V2

Pros:
- satisfies the UI-agnostic requirement
- lets V1 and V2 share store/rule/provider contracts
- creates the cleanest opening for piano-roll persistence
- gives web and landscape work a stable base

Cons:
- more upfront decomposition work
- requires careful sequencing to avoid regressing current behavior

### Option 3: Replace both shells with a brand-new DAW module

Pros:
- cleanest long-term architecture
- maximum layout freedom

Cons:
- too large for the current scope
- high regression risk
- would discard the strong existing V1 contracts and tests

### Recommendation

Choose **Option 2**.

The repo already has real behavior, focused tests, and specialist-agent
boundaries. The right move is to preserve those contracts, extract the logic
out of local widget state, and let both V1 and V2 become renderers of the same
Piano Roll domain.

## Locked Decisions

These decisions should stay fixed during implementation unless a real blocker
appears:

- V2 is the target product surface, but V1 remains available as a compatibility
  shell and regression harness until sign-off.
- The Piano Roll note timeline remains the single source of truth for editable
  note data.
- Shared Piano Roll behavior must live in models, rules, and Riverpod
  providers, not in V1-only or V2-only widget-local state.
- `lib/utils/note_utils.dart` remains the single source of truth for chord and
  scale catalogs.
- Piano Roll must gain first-class persistence through a new
  `PianoRollSnapshot`.
- `PianoRollSaveStackLoader` continues to import from Fretboard and Piano saves.
  It should not become the primary full-roll loader.
- Hum to MIDI remains mobile-only in this initiative. Web must not expose a
  broken record path.
- Landscape mode is part of scope and must be a real adaptive layout, not just
  the portrait screen stretched sideways.
- This initiative does not add looping, velocity lanes, MIDI export, undo/redo,
  or multi-track sequencing.

## Product Scope

### 1. V2 feature parity with V1

V2 must expose every currently shipped V1 capability:

- playback transport and status
- edit tool and snap controls
- pitch-range controls
- scale-highlighting flow
- Hum to MIDI card and latest-import jump
- stack composer
- save-stack import from Fretboard and Piano
- detection panel and note actions
- selected-column visibility and status

### 2. Missing DAW-management foundation

The initiative should add the missing management capability that makes Piano
Roll a first-class instrument:

- save the entire Piano Roll session
- load or update saved Piano Roll sessions
- preserve tempo, signature, timeline length, pitch window, notes, and
  selection anchor needed to resume work

### 3. Web support

Web support is required with one explicit exception:

- supported on web:
  - editor grid
  - playback
  - stack composer
  - save import
  - piano-roll save/load
  - detection
  - scale/highlight tools
- not supported on web:
  - Hum to MIDI capture

Web should surface a deliberate unsupported-state message or omit the hum card
entirely rather than exposing unusable controls.

### 4. Landscape mode

Landscape must optimize for editing density:

- persistent or semi-persistent inspector rail
- larger visible grid height
- composer and transport pinned without pushing the grid too far down
- no reliance on long vertical scrolling to reach core tools

## Architecture

### 1. Keep `PianoRollState` canonical and introduce focused companion state

`PianoRollState` should remain the canonical editor state for:

- timeline config
- notes
- pitch range
- selection anchor
- active note selection
- active tool
- snap value
- highlighted notes
- latest imported range

Do not stuff every panel-local concern into `PianoRollState`.

Instead, add small UI-agnostic companion providers for state that is shared
across shells but should not live in the core note timeline:

- `PianoRollComposerState`
  - root
  - quality
  - durationTicks
- optional capability provider
  - `supportsHumToMidi`
  - `supportsKeyboardShortcuts`

This keeps the editor model stable while removing shell-local business logic.

### 2. Shared pure rules for stack building and save import

Move widget-embedded algorithms into shared rule helpers:

- best MIDI in range for a pitch class
- chord stack build from root + quality + range anchor
- snapshot-to-stack preview mapping for exact and pitch-class modes

Recommended destination:

- `lib/schema/rules/piano_roll_import_rules.dart`

Keep the rule layer UI-free. Widgets should ask for preview or import results,
not reimplement the logic.

### 3. Shared harmonic analysis through `note_utils.dart`

The detection panel should stop carrying a local chord/scale catalog.

Use the existing shared exact-note analysis APIs from `lib/utils/note_utils.dart`
for:

- chord matches
- scale matches
- formatted labels
- future contextual spelling parity

This closes a drift risk that already exists between the Piano Roll widgets and
the shared instrument foundation.

### 4. Add `PianoRollSnapshot` to the shared save system

Add a new `InstrumentSnapshot` subtype with enough data to round-trip a full
Piano Roll session.

Persist:

- tempo
- key
- time signature
- total measures
- notes
- pitch range start/end
- selected column tick
- snap ticks
- highlighted notes

Do not persist:

- active playback transport state
- latest imported range
- transient note selection IDs

For `InstrumentSnapshot` compatibility fields:

- `selectedNotes` should describe the pitch classes active at the saved
  selected column, if any
- `pendingChord` and `pendingScale` may be derived from the saved selected
  column when possible

### 5. Recompose both shells from shared panels

The implementation should not duplicate the V1 cards into a V2-only set.

Instead:

- keep shared feature widgets for each panel
- add a real V2 shell that arranges them differently
- keep or lightly refactor the V1 shell so it reads from the same providers

This gives us:

- one behavior contract
- two layouts
- fewer parity bugs

### 6. Split large feature files along responsibility boundaries

The current Piano Roll feature has two files that are too large for safe
parallel iteration:

- `lib/features/piano_roll/piano_roll_grid.dart`
- `lib/features/piano_roll/piano_roll_save_stack_loader.dart`

Implementation should split them by responsibility rather than by arbitrary
size:

- painters vs. gesture/controller logic
- import data mapping vs. panel layout
- V2 shell vs. dock/transport subcomponents

This is not unrelated refactoring; it directly supports safer parity work.

## Interaction Model

### Existing interactions that must stay intact

- tap empty cell to add note
- tap note to select
- drag note body to move
- drag right edge to resize
- long-press note to delete
- pinch to zoom
- manual single-finger drag to scroll
- playback auto-scroll behavior
- hum latest-import jump behavior

### New interactions recommended for this initiative

These additions make the Piano Roll feel more DAW-like without changing the
core mental model:

1. **Ruler scrub**
   Drag across the ruler to move `selectedColumnTick` continuously instead of
   only tapping discrete points.

2. **Double-tap empty cell inserts snap-length note**
   Today empty-cell insertion is always one tick. In both shells, double-tap on
   an empty cell should insert a note using the current snap value, which makes
   the edit tool more useful on mobile and web.

3. **Web/desktop shortcuts**
   - `Space`: play/stop
   - `Delete` / `Backspace`: delete selected notes
   - `Ctrl`/`Cmd` + wheel: horizontal zoom
   - `Alt`/`Option` + wheel: vertical zoom

These should augment, not replace, touch interactions.

## Layout Model

### Portrait phone

- transport strip near the top
- main grid centered as the primary surface
- composer dock pinned low
- secondary tools available through panels, bottom sheets, or compact rails

### Landscape phone

- grid on the left
- inspector rail or sheet host on the right
- transport condensed into a single row
- hum/import/save grouped into collapsible utilities rather than a long stack

### Tablet and web

- same shared components
- more persistent side panels
- keyboard shortcuts enabled when supported

## Documentation Contract

This initiative must update:

- `docs/piano_roll.md`
- Piano Roll help content in `lib/ui/core/app_info_panel.dart`
- any new save-system notes needed for `PianoRollSnapshot`

Documentation must describe:

- V2 layout and tool surfaces
- web capability split
- landscape behavior
- new gestures and shortcuts
- save/load/import semantics

## Testing And Verification Contract

Implementation is not done until these are covered:

- store tests for new composer and snapshot flows
- rule tests for import mapping and shared detection
- widget tests for V2 parity-critical controls
- targeted grid tests for new ruler/keyboard behaviors
- save-system round-trip tests for `PianoRollSnapshot`
- `flutter analyze`
- `flutter test`
- `flutter build web --release`
- manual mobile smoke test

For mobile smoke verification, use `serve-sim` if an iOS simulator is
available. Validate at minimum:

- portrait and landscape layouts
- drag, resize, and pinch behavior
- playback start/stop
- hum record button visibility and behavior on mobile
- rotation without broken panel state

## Assumptions To Confirm During Review

- V2 becomes the default Piano Roll surface after parity, but V1 stays in the
  codebase until the team explicitly removes it.
- `PianoRollSaveStackLoader` should keep filtering to Fretboard and Piano saves,
  while full Piano Roll sessions use a dedicated save panel.
- Double-tap empty-cell insertion using current snap is acceptable as the one
  new edit gesture added in this initiative.
