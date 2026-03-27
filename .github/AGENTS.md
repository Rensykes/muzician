# Muzician Agent Directory

This file documents the multi-agentic workflow available for Muzician development. Use these agents in GitHub Copilot Chat by selecting them from the agent picker or by describing your task — Copilot will route to the most appropriate specialist automatically.

---

## Agents at a Glance

| Agent | File | Role | Tools |
|-------|------|------|-------|
| [Music Theory Expert](#music-theory-expert) | `music-theory.agent.md` | Music theory logic, chord/scale detection, interval math | read, search, edit, execute |
| [Instrument Renderer](#instrument-renderer) | `instrument-renderer.agent.md` | CustomPainter, gesture handling, fretboard/piano/roll UI | read, search, edit, execute |
| [State Architect](#state-architect) | `state-architect.agent.md` | Riverpod providers, immutable state, data-flow architecture | read, search, edit, execute |
| [Save System Engineer](#save-system-engineer) | `save-system.agent.md` | Persistence, JSON serialization, folder/save operations | read, search, edit, execute |
| [Accessibility & UX Reviewer](#accessibility--ux-reviewer) | `accessibility-ux.agent.md` | WCAG audits, touch targets, haptics, screen reader support | read, search *(review only)* |
| [Code Quality Auditor](#code-quality-auditor) | `code-quality.agent.md` | Dart conventions, static analysis, dead code, duplication | read, search, execute *(audit only)* |

---

## Music Theory Expert

**File**: `.github/agents/music-theory.agent.md`

**Persona**: A western music theory domain expert who also writes Dart. Knows the difference between a dominant 7th and a major 7th, can spell all modes, and understands enharmonic equivalence.

**Invoke when**:
- Adding a new chord quality (e.g. `add9`, `maj13`, `power`)
- Adding a new scale type (e.g. `lydian dominant`, `bebop`, `octatonic`)
- Fixing chord detection logic in `detectFirstChord` or `detectChordsAndScales`
- Extending the piano roll detection panel with more chord/scale types
- Implementing voice leading or inversion logic
- Debugging incorrect note names or pitch-class calculations
- Ensuring the piano chord picker's quality symbols stay in sync with `note_utils.dart`

**Key files owned**:
- `lib/utils/note_utils.dart` — single source of truth for all music theory
- `lib/schema/rules/*.dart` — pitch helpers per feature
- Detection panels in each feature

**Example invocation**:
> "Add the Lydian mode and Phrygian mode to the scale picker."

---

## Instrument Renderer

**File**: `.github/agents/instrument-renderer.agent.md`

**Persona**: A Flutter rendering specialist who thinks in canvas coordinates, gesture arenas, and scroll physics. Expert in making pixels and touch events do exactly what musicians need.

**Invoke when**:
- Fixing a visual rendering bug in the fretboard, piano, or piano roll
- Adding new visual features (e.g. animated note markers, color theming, capo highlight)
- Debugging scroll behavior or gesture conflicts
- Working on the piano roll's pinch-to-zoom, drag-to-resize, or long-press delete
- Optimizing CustomPainter `shouldRepaint` logic
- Working on the landscape modals (`LandscapeFretboardModal`, `LandscapePianoModal`)
- Adding hit-test logic for new interactive elements in a painter

**Key files owned**:
- `lib/features/fretboard/fretboard.dart`
- `lib/features/piano/piano_keyboard.dart`
- `lib/features/piano_roll/piano_roll_grid.dart`
- `lib/features/fretboard/chord_diagram.dart`

**Example invocation**:
> "The piano roll note resize handle is too small on mobile. Make it easier to grab."

---

## State Architect

**File**: `.github/agents/state-architect.agent.md`

**Persona**: A Riverpod 2.x architecture purist. Designs provider graphs, enforces immutability, and keeps widget rebuild scope as narrow as possible.

**Invoke when**:
- Designing state for a new feature
- Adding a new `NotifierProvider` or `StateProvider`
- Reviewing whether state belongs in a store or in local widget state
- Optimizing which widgets rebuild on a given state change
- Implementing a one-shot scroll signal or manual-edit counter
- Debugging unexpected widget rebuilds
- Reviewing `copyWith` coverage on a model class

**Key files owned**:
- `lib/store/` — all Riverpod stores
- `lib/models/` — all immutable data types
- `lib/schema/rules/` — validation and default factories

**Example invocation**:
> "Add a `PianoRollPlaybackState` to the piano roll store for a future playback feature."

---

## Save System Engineer

**File**: `.github/agents/save-system.agent.md`

**Persona**: A persistence engineer who treats data integrity as a first principle. Never loses user data, always handles corrupted storage gracefully, and thinks carefully about schema versioning.

**Invoke when**:
- Adding `PianoRollSnapshot` to the save system
- Implementing export/import of progression libraries
- Adding metadata to save entries or folders
- Handling storage corruption or migration between schema versions
- Debugging save/load failures
- Extending the save manager modal (new folder operations, bulk actions)
- Adding breadcrumb navigation or save ordering features

**Key files owned**:
- `lib/models/save_system.dart`
- `lib/schema/rules/save_system_rules.dart`
- `lib/store/save_system_store.dart`
- `lib/features/save_system/`

**Example invocation**:
> "Add a PianoRollSnapshot type so the piano roll can save and load progressions."

---

## Accessibility & UX Reviewer

**File**: `.github/agents/accessibility-ux.agent.md`

**Persona**: A WCAG 2.1 and mobile accessibility specialist who evaluates apps from the perspective of users with visual, motor, and cognitive impairments. Produces structured audit reports.

> **Read-only**: This agent reviews and recommends — it does not edit code.

**Invoke when**:
- Running an accessibility audit before a release
- Checking color contrast of the glassmorphism dark theme against text/UI elements
- Evaluating whether custom painter interactions are accessible to screen readers
- Reviewing touch target sizes for fret cells, piano keys, and toolbar buttons
- Checking haptic feedback coverage and differentiation
- Assessing the discoverability of non-obvious gestures (pinch-zoom, long-press)
- Getting WCAG-referenced recommendations for a specific screen

**Example invocation**:
> "Run a full accessibility audit on the piano roll screen."

---

## Code Quality Auditor

**File**: `.github/agents/code-quality.agent.md`

**Persona**: A Dart code quality specialist who runs `dart analyze`, hunts dead code, finds cross-feature duplication, and enforces the project's own coding standards rigorously.

> **Read-only**: This agent audits and reports — it does not edit code.

**Invoke when**:
- Running a code quality audit before a release
- Finding dead code or unused private methods
- Checking `dart analyze` findings and triaging them
- Identifying cross-feature duplication (e.g. local chord interval maps that duplicate `note_utils.dart`)
- Reviewing naming convention compliance with `dart-n-flutter.instructions.md`
- Auditing `copyWith` coverage across all model classes
- Checking that error handling exists at persistence boundaries

**Example invocation**:
> "Run a full code quality audit on lib/features/ and report all duplication."

---

## Multi-Agent Workflows

Some tasks benefit from routing across multiple agents sequentially:

### Adding a new chord type
1. **Music Theory Expert** → add the interval to `chordIntervals` in `note_utils.dart`
2. **State Architect** → check whether any state struct needs updating
3. **Code Quality Auditor** → verify no drift between note_utils and detection panel copies

### Adding a new feature (e.g. audio playback)
1. **State Architect** → design the state model and providers
2. **Instrument Renderer** → add playback position indicator to the piano roll painter
3. **Save System Engineer** → extend `InstrumentSnapshot` with playback settings if needed
4. **Accessibility & UX Reviewer** → audit play/pause controls for WCAG compliance

### Pre-release quality check
1. **Code Quality Auditor** → generate a full P0–P3 report
2. **Accessibility & UX Reviewer** → generate a WCAG audit report
3. Developers action findings using **Music Theory**, **Instrument Renderer**, **State Architect**, or **Save System Engineer** as appropriate

### Save system schema migration
1. **Save System Engineer** → design the migration, new key, `fromJson` changes
2. **State Architect** → review provider-layer changes
3. **Code Quality Auditor** → verify no orphaned `switch (snapshot)` cases remain

---

## Agent Conventions

- All editing agents (`music-theory`, `instrument-renderer`, `state-architect`, `save-system`) run `dart analyze` on the affected files after every edit.
- Review agents (`accessibility-ux`, `code-quality`) produce structured reports with severity levels (Critical / Major / Minor) and concrete fix suggestions.
- Every agent references specific file paths and function names — not generic advice.
- The coding standards in `.github/instructions/dart-n-flutter.instructions.md` apply to all output from editing agents.
