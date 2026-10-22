# Fretboard

The Studio Fretboard is a playable six-string workbench for exploring notes,
loading voicings and saving ideas. It uses the native `GuitarFretboard`
`CustomPainter`, with native fret geometry and horizontal scrolling.
The default is Standard tuning, 12 frets, capo off and Free input mode.

## Workspace

Project context has its own row above the full Fretboard title. The **?** action
opens shared help. Compact **Free/Chord** and **Exact/Solo**
menus sit together above the board (in the inspector header in short landscape).
Each menu explains its choices and retains a minimum 44px touch target. Setup
contains tuning, capo and fret count; its shortcut exposes tuning/capo in a tooltip.

One compact selection row below the instrument shows the detected
chord or selected-note count. **Actions** opens the selection sheet with exact
MIDI notes, **Save idea**, and **Add to Writer**. The sheet explains why Free or
invalid shapes cannot enter Writer and preserves recognized versus exact-note
handoff. Selection actions stay in this single location across Notes, Voicings
and Setup, including when the inspector is collapsed.

**Library** opens the existing save browser for loading, renaming and linked-Save
updates. **Scale** opens the shared scale picker; an active key replaces the
Scale label, and an off-key chord adds a warning icon.

The inline inspector defaults to **Voicings**. Notes / Voicings / Setup tabs
and the Scale / Library footer remain reachable while its content scrolls.
Collapsing and reopening preserves the selection and each mounted panel's state.
Compact portrait keeps the playable surface above a bounded inspector; wide
and short landscape layouts put the inspector beside the instrument. Scrolling
the inspector does not scroll the instrument out of view. Very short portrait layouts use a single-row header and tighter inspector margins to retain usable controls at enlarged text sizes.

| Tab | Controls |
| --- | --- |
| Notes | Selected pitch classes, chord detection, compatible scales and Clear |
| Voicings | From notes / By chord search and a horizontal native-diagram carousel |
| Setup | Tuning, capo and fret count; Clear all selections remains a secondary action |

### Voicing search

- **From notes** captures the selected pitch classes. Each candidate contains
  every captured note, but may add chord tones. C + E can therefore suggest C,
  Cmaj7, Am and Fmaj7 when realizations fit the instrument. Octave, bass and
  position are not fixed by this filter. When a scale is active, every candidate
  chord tone must belong to it. The project key takes precedence over a local
  scale; without either, the search uses the full chord catalogue. Setting,
  changing or clearing the scale refreshes results without changing the query
  or selected notes. A query containing an outside note returns no suggestions.
- **By chord** chooses a root and quality independently of the captured notes,
  showing available generated realizations within the current instrument bounds.
- Compatible chords are interleaved so hundreds of shapes for one chord do not
  hide the other completions. Both modes retain their criteria when switching. Manual instrument edits
  refresh the note query. The refresh action, **Use current notes**, explicitly recaptures the
  selection after applying a result.
- Tap a card to apply its native notes. **Applied** identifies that result;
  applying does not rewrite search criteria, change result order or reset the
  horizontal carousel. Explicit **By chord** choices retain key-conflict
  confirmation before applying.
- Selecting a detected chord opens By chord in the existing inline picker.
  Empty selection and no-result states explain what to change; the filter is
  never silently relaxed.

Generation uses every supported root/quality. Guitar results cover the configured
physical fret range, requiring every chord tone within a four-fret hand span
plus open/capo strings. Muted inner strings are allowed; results are generated
shapes, not finger-assignment guarantees. There is no arbitrary 24-result cap.

Notes Clear deselects notes; Setup Clear all stays in the workspace. Project-key
changes keep their existing confirmation flow. Root/quality controls adapt to
the inspector width, and cards continue to scroll horizontally at larger text
sizes. Scale and Library are outside the scrolling panel content.

The Studio canvas is 212px tall, with six native 28px string rows,
unchanged 66px fret spacing, and 36×28px note hit regions. These musical targets
remain smaller than named 44px controls; voicing diagrams provide an alternative
for entering complete chords. The renderer keeps its pointer scroll guard,
physical capo mapping and horizontal scrolling. Legacy/controlled hosts keep
their existing geometry.

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
- `chord_voicing_picker.dart` / `chord_diagram.dart`: search/application state
  and centered native mini-diagrams with balanced string-grid margins. Shared voicing rules live in
  `lib/schema/rules/instrument_voicing_search_rules.dart`.
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
