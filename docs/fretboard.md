# Fretboard

An interactive guitar fretboard rendered entirely with `CustomPainter`. Supports multiple tunings, capo, chord voicing loading, scale highlighting, and a landscape modal view.

When height is tight, including landscape and compact screens with enlarged
text, the header, mode selector, fretboard, and detection area scroll above the
fixed Scale/Chord dock. The board retains its full size; scroll to reach lower
strings or detection controls. Mode, chord-picker, and scale-picker controls
provide at least 44×44px tap regions, including scale categories and clear actions.

---

## Architecture

```
lib/
  models/fretboard.dart               ← data types
  schema/rules/fretboard_rules.dart   ← tunings, pitch helpers, validation
  store/fretboard_store.dart          ← Riverpod NotifierProvider
  features/fretboard/
    fretboard.dart                    ← CustomPainter grid (GuitarFretboard)
    fretboard_feature.dart            ← Fretboard tab screen shell
    fretboard_screen_v2_mockup.dart   ← landscape-optimized mockup variant
    fretboard_save_panel.dart         ← save/load panel (wraps SaveBrowserPanel)
    capo_control.dart                 ← capo position stepper
    chord_diagram.dart                ← chord shape mini-diagram
    chord_voicing_picker.dart         ← chord root + quality → load to fretboard
    note_detection_panel.dart         ← detect chord/scale from selected cells
    scale_picker.dart                 ← scale root + type → highlight fretboard
    tuning_selector.dart              ← preset tuning picker
```

---

## Data Model (`lib/models/fretboard.dart`)

| Type | Description |
|---|---|
| `TuningName` | Enum — 10 presets (standard, dropD, openG, openD, openE, DADGAD, halfStepDown, fullStepDown, openA, openC) |
| `TuningCategory` | Enum — standard / drop / open |
| `StringTuning` | MIDI note number for one string's open pitch |
| `Tuning` | Named tuple: `name`, `category`, `strings` (6 × `StringTuning`), `displayName` |
| `FretCell` | A cell on the grid: `stringIndex`, `fret`, `noteName`, `isSelected`, `isHighlighted`, `isRoot` |
| `FretCoordinate` | A selected position: `stringIndex`, `fret`, `noteName` |
| `ChordVoicing` | A named chord shape: `name`, list of `FretCoordinate` |
| `FretboardState` | Full state: `tuning`, `numFrets`, `capo`, `viewMode`, `inputMode`, `selectedCells`, `highlightedNotes` |
| `FretboardViewMode` | Enum — `exact`, `exactFocus` |
| `FretboardInputMode` | Enum — free / chord |

---

## Schema / Rules (`lib/schema/rules/fretboard_rules.dart`)

| Export | Description |
|---|---|
| `tunings` | `Map<TuningName, Tuning>` — all 10 preset tunings |
| `chromaticSharp` / `chromaticFlat` | Chromatic note arrays |
| `positionMarkerFrets` | `{3, 5, 7, 9, 12, 15, 17, 19, 21}` — dot marker positions |
| `getPitchClassAtFret(tuning, string, fret)` | Returns pitch class string (e.g. `"C#"`) |
| `getNoteWithOctaveAtFret(tuning, string, fret)` | Returns note + octave (e.g. `"C#4"`) |
| `isNaturalNote(pitchClass)` | True for A B C D E F G |
| `isValidPitchClass(pc)` | Validates against chromatic arrays |
| `validateTuning(tuning)` | Returns `({bool valid, List<String> errors})` |
| `getDefaultFretboardState()` | Returns standard-tuned, 15-fret, no-capo state |

---

## Store (`lib/store/fretboard_store.dart`)

Provider: `fretboardProvider` (Riverpod `NotifierProvider<FretboardNotifier, FretboardState>`)

Auxiliary providers:
- `pendingChordProvider` — `StateProvider<({String root, String quality})?>` 
- `pendingScaleProvider` — `StateProvider<({String root, String scaleName})?>` 

### Key actions

| Method | Description |
|---|---|
| `toggleCell(stringIndex, fret)` | Select / deselect a fret cell; enforces one-per-string in chord mode |
| `setTuning(tuningName)` | Switch tuning preset, rebuild cells |
| `setNumFrets(n)` | Change visible fret count (1–24) |
| `setCapo(fret)` | Set capo position |
| `setViewMode(mode)` | Switch display mode |
| `setInputMode(mode)` | Switch input mode (free / chord) |
| `loadVoicing(voicing)` | Apply a `ChordVoicing` as selected cells |
| `clearSelectedNotes()` | Clear all cell selection |
| `reset()` | Restore defaults |
| `getCurrentTuning()` | Returns active `Tuning` |
| `getFretCells()` | Returns computed `List<FretCell>` grid |

---

## Widgets

### `GuitarFretboard`
The main fretboard widget. Rendered entirely with `CustomPainter` + `RepaintBoundary`.

**Controls (top bars):**
1. **Input Mode Bar** — `Free` vs `Chord` toggle (see [Input Modes](#input-modes) below).
2. **View Mode Bar** — `Exact` / `Exact + Focus` selector.

**Painter logic:**
- String lines spaced vertically, fret lines spaced horizontally
- Nut drawn as thick line at fret 0
- Position dot markers at standard fret positions (3, 5, 7, 9, 12…)
- Capo shown as a coloured bar across all strings
- Selected cells drawn as filled circles with note name label
- Highlighted (scale) cells drawn as outlined circles
- Root note cells use accent colour (`sky`)

**Interaction:**
- `GestureDetector.onTapUp` → `toggleCell(string, fret)` with `lightImpact` haptic

**Layout:**
- `LayoutBuilder` ensures the fretboard fills available width
- `RepaintBoundary` isolates paint from surrounding rebuilds

---

### `CapoControl`
A row with `−` / `+` buttons to step the capo position between 0 and 11. Calls `fretboardProvider.notifier.setCapo()`. Shows `"No capo"` at 0.

---

### `TuningSelector`
A horizontal `Wrap` of pill buttons, one per `TuningName`. Active tuning is highlighted. Tapping calls `setTuning()` with `lightImpact`. Groups displayed by `TuningCategory` via a section label above each group.

---

### `ChordVoicingPicker`
Lets the user pick a chord root (12 chromatic notes) and quality (major, minor, 7, maj7, m7, dim, aug, sus2, sus4). Tapping "Load" calls `fretboardProvider.notifier.loadVoicing(voicing)`, which places the chord shape directly on the fretboard.

Chord tones are computed from a semitone-interval map (`_chordIntervals`) rather than the `music_notes` package, to ensure correct cross-string placement.

---

### `NoteDetectionPanel`
Reads `pendingChordProvider` and `pendingScaleProvider`. Displays:
- The detected chord name (e.g. `"C/E"` or `"Cmaj7"`) using the global Sharps/Flats preference
- The detected scale name (e.g. `"Eb dorian"` in Flats mode) using the same preference as board notes and the Scale dock
- A "Clear" button that resets both providers

Detection uses the shared exact-note-aware API (`detectChordResultsFromExactNotes` / `detectScaleResultsFromExactNotes`) from `note_utils.dart`, supporting inversion-aware slash-chord results and the full picker scale catalog. Tapping a chip writes canonical root/quality or root/scaleName into the pending providers.

**Settings → Prefer flat note names** persists across restarts and updates note
labels, scale/chord controls, and project key labels immediately. Pitches,
positions, and custom Save/unknown Harmony names stay unchanged.

---

### `ScalePicker`
Root + scale type selector (major, natural minor, major pentatonic, minor pentatonic, dorian, mixolydian, etc.). Tapping "Highlight" writes `pendingScaleProvider` and calls the store to populate `highlightedCells` and mark the `rootNote`.

---

### `ChordDiagram`
A compact `CustomPainter` rendering of a 5-fret chord box diagram. Draws:
- 6 vertical string lines
- 5 horizontal fret lines
- Filled dots for each fret position in the voicing
- Open / muted string indicators at the top
- Fret number label if the diagram doesn't start at fret 1

Used as a preview inside `ChordVoicingPicker`.

---

## State Flow

```
TuningSelector → fretboardProvider.setTuning()
                          │
                 GuitarFretboard repaints
                          │
              User taps cell → toggleCell()
                          │
        NoteDetectionPanel reads pendingChordProvider
```

## Behaviour Notes

- Input modes: The fretboard supports two input modes selected via the `_InputModeBar`. In **free** mode any number of notes may be placed on any string, subject to the existing scale-highlight guard. In **chord** mode only one note per string is allowed; tapping a new fret on an already-occupied string replaces the existing note on that string, making it straightforward to build chord voicings. The active mode is stored as `FretboardState.inputMode` and toggled via `FretboardNotifier.setInputMode()`.

- Out-of-key confirmation: If a scale highlight is active and the user attempts to add a note outside that scale, the app shows an out-of-key confirmation dialog. The dialog offers a "Don't show again" option which persists to settings. See implementation: [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart).

- View-mode control: The fretboard exposes an in-page view-mode control (`exact` / `exactFocus`) for local display preference. Tools such as chord/scale pickers do not force the view mode. Relevant code: [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart).

- Scroll guard: To prevent accidental note insertion while scrolling horizontally, the fretboard uses a pointer-down/ up movement threshold and ignores taps that exceed the threshold distance. See: [lib/features/fretboard/fretboard.dart](lib/features/fretboard/fretboard.dart).

- Scale highlight & conflicts: Applying a scale highlights pitch classes across the board and will warn if the selected scale conflicts with already-selected notes (offers to remove conflicting notes). See: [lib/features/fretboard/scale_picker.dart](lib/features/fretboard/scale_picker.dart).

---

## Recent Changes — 2026-03-23

- **Capo behavior:** Setting the capo now animates the fretboard to the capo position and transposes currently selected notes by the capo delta so their pitches remain correct.
- **Chord picker / voicings:** Selecting a chord voicing animates the fretboard to the voicing's base fret (the nearest physical occurrence) and loads the voicing as selected cells.
- **Detection vs committed voicing:** The picker shows detected chords by default. When a user explicitly commits a voicing (taps to load), it overrides detection until the user makes a manual fretboard edit; unfocusing without selection reverts to detection.
- **Manual-edit signal:** Manual fretboard edits now clear any committed voicing so detection regains control.
- **Implementation notes:** Added two inter-widget signals in the store — `scrollToFretProvider` (one-shot int?) and `fretboardManualEditProvider` (counter). Voicing generation and `loadVoicing()` were adjusted to operate on physical frets (capo handled separately) to avoid double-applying the capo offset.
- **Bugfixes & diagnostics:** Fixed a bug where the capo was being applied twice in pitch calculations. Static checks ran locally; modified files compile cleanly. One minor unused helper (`_toSharp`) remains for cleanup.
- **Next steps:** Remove the unused helper or integrate it into parsing, and verify the piano page for analogous capo/selection issues.

---

## Recent Changes — 2026-03-23 (input modes)

- **Free mode / Chord mode:** Added `FretboardInputMode` enum (`free`, `chord`) to the data model and `FretboardState`. Default is `free`.
- **Chord mode constraint:** In chord mode `toggleCell` enforces one note per string: tapping a new fret on an occupied string replaces the existing note; tapping the selected fret deselects it. All other input-mode behaviour (scale guard, view mode, capo) is unchanged.
- **Free mode:** Existing multi-note-per-string behaviour is preserved, including the out-of-key scale guard.
- **`_InputModeBar` widget:** A two-button bar (`Free` / `Chord`) is rendered above the existing view-mode bar inside `GuitarFretboard`. Tapping a button calls `FretboardNotifier.setInputMode()` with a light haptic.
- **`setInputMode()`:** New method on `FretboardNotifier`. Persists `inputMode` in `FretboardState` via `copyWith`.


---

## Info Panel

File: `lib/ui/core/app_info_panel.dart`

A shared, dismissible help overlay. Opened by tapping the **?** button in the top-right corner of the Fretboard screen header (opens the info sheet pre-selected on the Fretboard tab).

### Entry point

```dart
showAppInfoPanel(context, initialTab: 0); // 0 = Fretboard, 1 = Piano, 2 = Piano Roll
```

### Fretboard tab sections

| Section | Content |
|---|---|
| **Gestures** | Tap fret cell to select / deselect |
| **Input & View Modes** | Free mode, Chord mode, Exact / Exact+Focus views |
| **Panels & Tools** | Tuning (10 presets), Capo (0–11), Chord voicing picker, Scale picker, Detection panel, Saves |

## Project lock

When a project is selected, the instrument inherits its tonic and scale/mode,
tempo, and time-signature where applicable. The scale picker can set, change,
or clear the project key after confirmation, including the first key on an
unkeyed project. Cancel keeps the previous key; confirming updates Writer,
Fretboard, and Piano without transposing selected notes. Instrument Save loads
retain the project key. Tempo and meter use the project config sheet from the
project chip in the header. Dump and "no project" leave scale choices local.

**Scale dock label:** The Scale dock tab shows the active project key (e.g.
"C major") as its label when the selected project has a key configured. When
the real project has no key, the label is `"Scale"`. In Dump or with no project,
the label uses the local active scale or `"Scale"` when none is present.
See `_resolveScaleDockState()` in `lib/main.dart`.

**chordOffKey warning:** When the committed chord contains notes outside the
active project key, the Scale dock tab turns orange and shows a warning icon.
This is driven by `InstrumentBinding.chordOffKey`, computed by
`fretboardChordOffKeyProvider` in `lib/store/fretboard_store.dart`. The flag
is passed as `scaleOffKey` to `InstrumentScreen` → `DockTab.warning`.

**Shared scale picker:** The scale picker (`SharedScalePicker` in
`lib/features/instrument_shared/shared_scale_picker.dart`) reads
`activeProjectKeyProvider` and treats the real project key as authoritative. The
active-scale chip turns orange when the committed chord is off-key and the
project is locked (`chordOffKey && isProjectLocked`).

**Chord picker header:** The shared chord picker parts in
`lib/features/instrument_shared/chord_picker_parts.dart` provide
`ChordPickerHeader` — a reusable header row showing the active chord as a
badge. Used by both the Fretboard and Piano chord pickers.

## Saves and Writer handoff

Saving a fretboard selection outside Writer stores an idea in the selected
project root, including its Free or Chord input mode. Loading restores that
mode. Free remains savable, loadable, and playable for exploration on the
instrument. Writer accepts only Chord mode with a nonempty valid selection
and at most one position per string; changing modes does not silently delete
duplicate-string notes. Free is excluded from Writer handoff, saved-source
reuse, linked editing, playback, and import into Song. Free-to-melody conversion
is outside this phase.

In the save browser, **Use in Writer** explicitly links that
existing project-root save to a selected Writer section and placement without
moving or copying it; its ID and root folder stay unchanged as it becomes a
Harmony Save. Dump-root ideas stay in Dump. A fresh **Add to Writer**
handoff creates a new named save after the destination is chosen. Harmony
chord saves keep the symbolic Writer chord together with its native Fretboard
realization. **Add exact notes as Harmony** accepts valid Chord selections
even when the app recognizes no chord, preserving native positions and the
chosen name for Harmony Library reuse. Unknown Harmony offers Change chord,
Replace chord, and native editing; theory actions wait for a symbolic chord
identity. Symbolic Harmony native edits must match its chord pitch classes
and normalize the pending-chord label. Exact Harmony native edits preserve
the name and update its notes without inventing a root or quality.

If a linked Save is used by multiple Writer blocks, updating it offers
**Update all placements** or **Create a unique instance**. The unique choice
creates a standalone Save in the project and leaves Writer blocks unchanged.
Use **Replace chord** on a Writer block to apply that Save to one placement,
preserving its bar, duration, repeats, and lyrics. A Fretboard realization
that does not fit the valid tuning, capo, and fret range produces an actionable
settings error and does not change the chord or Save. Renaming a shared linked
Save changes its name for all placements.
