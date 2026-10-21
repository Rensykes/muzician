# Fretboard

The Studio Fretboard is a playable six-string workbench for exploring notes,
loading voicings and saving ideas. It uses the native `GuitarFretboard`
`CustomPainter`, with native fret geometry and horizontal scrolling.
The default is Standard tuning, 12 frets, capo off and Free input mode.

## Workspace

Project context has its own row above the full Fretboard title. The **?** action
opens shared help. Free/Chord controls and the current tuning/capo readout sit
above the board; tapping the readout opens **Setup** in the inspector.

Below the board, a compact summary shows the first detected chord or **Exact
selection**, plus the selected MIDI notes with octave labels. **Save idea**
opens the existing save browser and naming flow as an outlined action. The
filled **Add to Writer** action keeps the
recognized-chord versus exact-note choice and explains why Free selections
cannot enter Writer. **Library** opens the same save browser for loading,
renaming and linked-Save updates. **Scale** opens the shared scale picker;
when a key is active its name replaces the Scale label, and an off-key chord adds
a warning icon.

The inline inspector defaults to **Voicings** and can collapse without
clearing selection or recreating the picker. Underlined Notes / Voicings / Setup
tabs replace the separate inspector heading. Compact root/quality selectors
lead directly to native voicing previews; project-key suggestions follow them.
Scale, Library and Instrument setup remain in a compact footer:


| Tab | Controls |
| --- | --- |
| Notes | Selected pitch classes (tap to focus), chord detection, compatible scales, Clear |
| Voicings | Project-key diatonic chords, chromatic root/quality, scrollable native chord diagrams; tap a voicing to apply |
| Setup | Exact/Solo view, tuning categories/presets, capo stepper and fret choices; subdued Clear all selections action below the settings |

Selecting a detected chord switches to the existing inline voicing picker;
it does not create another picker sheet. A committed voicing remains in
control until a manual board edit returns it to detection. Setup's Clear all
stays in the workspace; Notes Clear deselects notes. Project-key changes still
use their confirmation flow.

Notes starts directly below its tab and sizes to its detection results, without
a reserved blank viewport. The page owns vertical scrolling on compact screens;
the bounded inspector rail owns it on wide screens. Setup keeps related controls
close, labels the native capo control once, and places the destructive clear
action last while preserving its 44px touch target.

At widths of at least 700px with at least 500px available height, content and
a 316–360px inspector column sit beside one another, each scrollable. Compact
and short windows use a single scrolling page. The Studio canvas is 212px tall,
with six native 28px string rows, unchanged 66px fret spacing, and 36×28px note
hit regions. These musical targets remain smaller than named 44px controls;
voicing diagrams provide an alternative for entering complete chords. The
renderer keeps its pointer scroll guard and maps compact rows directly to
notes. Chord mode shows selected/focused positions clearly; Free retains all
note labels. Legacy/controlled hosts retain their existing geometry. All
strings and tools remain reachable, including 844×390 landscape.

Studio and Studio Muzician share this layout. Sheets, diagrams and the native
canvas consume the inherited immutable palette and repaint when it changes.
Theme switching keeps the project, notes, focus, picker and committed state.
Unthemed legacy hosts retain the previous fixed Scale/Chord dock composition.

## Playing and settings

- **Free:** select multiple positions on a string. Ideas remain savable and
  loadable; changing to Chord does not silently remove duplicate positions.
- **Chord:** tapping a new fret replaces the selected position on that string;
  tapping it again deselects it. Writer requires a nonempty valid shape with
  at most one position per string.
- **Exact/Solo:** Exact shows the full board; Solo hides unrelated positions
  when notes are selected while keeping focused pitch classes visible.
- **Tuning:** presets are grouped as Standard, Metal and Midwest Emo. Tuning
  choices use stored MIDI pitches; display spelling follows Sharps/Flats.
- **Capo:** Off or physical frets 1–11. The capo scrolls into view and selected
  pitches transpose by the capo delta. Voicing loading uses physical frets;
  the renderer never applies capo offset twice.
- **Tap versus scroll:** the native pointer-down/up distance guard rejects
  note insertion during a drag. Tap audition and horizontal scrolling keep
  their existing behavior.

When a local scale is active, adding an outside note uses the existing
out-of-key dialog and optional persistent suppression. A real project uses
the project off-scale safeguard. Applying a scale with conflicting selected
notes asks before removing those notes.

## Project key and spelling

A selected project's tonic and scale/mode are canonical for Writer, Fretboard
and Piano. Setting, changing or clearing that key from Scale or a compatible
scale chip requires confirmation, including the first key on an unkeyed
project. Cancel retains the previous key. Confirming updates the shared key
without transposing selected notes; loading an instrument Save does not
replace it. Dump or no project keeps scale choices local. Tempo and meter are
available through the project context chip.

Settings → Prefer flat note names changes musical labels only, including
board notes, detection, roots, diatonic chords and scale labels. MIDI pitches,
custom Save names and exact Harmony labels stay literal and unchanged.

## Implementation

- `lib/main.dart`: instrument composition and existing setup/save builders.
- `lib/features/instrument_shared/instrument_screen.dart`: Studio composition,
  summary/actions and inspector; legacy fallback remains explicit.
- `lib/features/instrument_shared/shared_detection_panel.dart` and
  `shared_scale_picker.dart`: binding-driven detection/key controls.
- `lib/features/fretboard/fretboard.dart`: native board, pointer guard,
  one-shot scroll-to-fret and immutable painter palette.
- `chord_voicing_picker.dart` / `chord_diagram.dart`: voicing generation,
  committed/detected sync and native mini-diagrams.
- `capo_control.dart`, `tuning_selector.dart`, `fretboard_save_panel.dart`:
  instrument settings and Save browser integration.
- `lib/models/fretboard.dart`, `lib/schema/rules/fretboard_rules.dart`,
  `lib/store/fretboard_store.dart`: immutable model, musical rules and state.

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
