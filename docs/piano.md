# Piano

The Studio Piano is a playable MIDI keyboard for selecting exact keys,
exploring voicings and saving ideas. `PianoKeyboard` uses a widget `Stack`,
with white keys first and black keys overlaid above them. Its compact chord
previews use `CustomPainter`. The default range is 61 keys, C2–C7.

## Workspace

Project context has its own row above the full Piano title. The **?** action
opens shared help. A compact **Full/Solo** menu above the keyboard explains
both display modes. Setup contains the current range, and the footer shortcut
shows its full range label in a tooltip.

One compact selection row below the keyboard shows a detected chord
or selected-note count. **Actions** opens a sheet containing exact MIDI notes,
**Save idea**, and **Add to Writer**, preserving recognized and exact-note handoff.
These actions have one consistent home across all inspector tabs and remain
available when the inspector is collapsed.

**Library** opens the existing save browser for loading, renaming and linked-Save
updates. **Scale** opens the shared picker, displays the active key and warns
when a committed chord contains notes outside the project key.

The inline inspector defaults to **Voicings**. Notes / Voicings / Setup tabs
and the Scale / Library footer remain reachable while its content scrolls.
Collapsing and reopening preserves the selection and each mounted panel's state.
Compact portrait keeps the playable surface above a bounded inspector; short
landscape and shorter wide layouts put the inspector beside the instrument, while
wide layouts with at least 640px body height dock it below a full-width scaled
canvas (three columns at 1100px or wider). Scrolling
the inspector does not scroll the instrument out of view. Very short portrait layouts use a single-row header and tighter inspector margins to retain usable controls at enlarged text sizes.

| Tab | Controls |
| --- | --- |
| Notes | Selected pitch classes, chord detection, compatible scales and Clear |
| Voicings | From notes / By chord search and a horizontal native-diagram carousel |
| Setup | 49/61/88-key ranges; Clear all selections remains a secondary action |

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
- Compatible chords are interleaved before alternate realizations. Both modes
  retain their criteria when switching. Manual instrument edits
  refresh the note query. The refresh action, **Use current notes**, explicitly recaptures the
  selection after applying a result.
- Tap a card to apply its native notes. **Applied** identifies that result;
  applying does not rewrite search criteria, change result order or reset the
  horizontal carousel. Explicit **By chord** choices retain key-conflict
  confirmation before applying.
- Selecting a detected chord opens By chord in the existing inline picker.
  Empty selection and no-result states explain what to change; the filter is
  never silently relaxed.

Generation covers all registers in the active keyboard range and ordered
inversions/open spacings spanning at most 23 semitones. Each result includes all
chord tones; notes are never dropped at range boundaries. This is a bounded
catalog of realizations, not every possible doubled-note or reordered voicing.
The preview expands to three C-aligned octaves when needed to show every note.

Notes Clear deselects notes; Setup Clear all stays in the workspace. Project-key
changes keep their existing confirmation flow. Root/quality controls adapt to
the inspector width, and cards continue to scroll horizontally at larger text
sizes. Scale and Library are outside the scrolling panel content.

The Studio keyboard canvas is 226px tall: white keys are 42×190px and
black keys 26×118px. Horizontal key positions and hit testing remain native;
scrolling reveals the remaining range. Legacy hosts retain 42×210px white keys
and 26×130px black keys. Named controls use at least 44px tap regions, while
native black-key widths remain smaller.

Studio and Studio Muzician share the layout. The keyboard, diagrams, sheets
and controls consume the inherited palette. Switching themes retains project,
selected MIDI keys, focus and picker state. Unthemed legacy hosts retain the
previous Scale/Chord dock composition.

## Ranges and interaction

| Preset | MIDI bounds | Note bounds |
| --- | --- | --- |
| 49 keys | 36–84 | C2–C6 |
| 61 keys (default) | 36–96 | C2–C7 |
| 88 keys | 21–108 | A0–C8 |

Tap a key to audition and select/deselect it. Horizontal drag scrolls the
keyboard. There is no glissando or added global transport. White-key x is
`whiteIndex * 42`; black-key x is `whiteIndex * 42 - 13`, and black keys
remain above whites for hit testing.

Selected/focused keys receive the palette accent; ordinary keys keep their
white/black physical identity. Studio keeps black keys opaque when scale
highlights or pitch-class focus dim unrelated content, preserving a readable
physical keyboard. **Full** shows every note label; **Solo** labels only selected
MIDI keys, even when pitch-class focus is active. With no selection, Solo shows
no labels. Every physical key remains visible and playable in both views.
Saved mode identifiers remain compatible with older Saves. Voicings load exact MIDI keys in the
current range and use the existing one-shot scroll-to-MIDI signal.

## Project key and spelling

A selected project's tonic and scale/mode are canonical for Writer, Piano and
Fretboard. Setting, changing or clearing that key from Scale or a compatible
scale chip requires confirmation, including the first key on an unkeyed
project. Cancel keeps the previous key. Confirming updates the shared key
without transposing selected MIDI notes. Instrument Save loads retain the
project key. Dump or no project keeps scale choices local. Tempo/meter remain
available from the project context chip.

Local scale conflicts ask before removing selected keys. Adding a key outside
an active local scale uses the existing out-of-key dialog and persistent
suppression preference; real projects use the project off-scale safeguard.

Settings → Prefer flat note names affects keyboard labels, roots, voicings,
detection and scale/project-key labels only. Slash bass and octaves remain
visible. MIDI pitches, custom Save names and exact Harmony labels do not
change.

## Implementation

- `lib/main.dart`: instrument composition and existing setup/save builders.
- `lib/features/instrument_shared/instrument_screen.dart`: Studio summary,
  inspector and legacy fallback.
- `shared_detection_panel.dart`, `shared_scale_picker.dart`,
  `chord_picker_parts.dart`: instrument bindings, canonical callbacks and
  project-key confirmation.
- `lib/features/piano/piano_keyboard.dart`: widget keyboard, taps, dimming and
  one-shot MIDI scroll.
- `piano_chord_picker.dart` / `piano_chord_diagram.dart`: search/application
  state and immutable palette-aware miniature painter. Shared voicing rules
  live in `lib/schema/rules/instrument_voicing_search_rules.dart`.
- `piano_range_selector.dart` / `piano_save_panel.dart`: range and existing
  Save browser/native linked-Save behavior.
- `lib/models/piano.dart`, `lib/schema/rules/piano_rules.dart`,
  `lib/store/piano_store.dart`: immutable model, range rules and state.

## Saves and Writer handoff

Saving a piano voicing outside Writer stores a free idea in the selected
project root. In the save browser, **Use in Writer** explicitly links that
existing project-root save to a selected Writer section and placement without
moving or copying it; its ID and root folder stay unchanged as it becomes a
Harmony Save. Dump-root ideas stay in Dump. A fresh **Add to Writer**
handoff creates a new named save after the destination is chosen. Harmony
chord saves keep the symbolic Writer chord together with its native Piano
realization. **Add exact notes as Harmony** accepts any nonempty valid Piano
selection, including unrecognized combinations. It preserves exact MIDI notes
and the chosen name and makes the block reusable from the Harmony Library.
Unrecognized Harmony offers Change chord, Replace chord, and native editing;
theory actions wait for a symbolic chord identity. Symbolic Harmony native
edits must still match its chord pitch classes and normalize the pending-chord
label. Exact Harmony native edits preserve the name and update its notes
without inventing a root or quality.

If a linked Save is used by multiple Writer blocks, updating it offers
**Update all placements** or **Create a unique instance**. The unique choice
creates a standalone Save in the project and leaves Writer blocks unchanged.
Use **Replace chord** on a Writer block to apply that Save to one placement,
preserving its bar, duration, repeats, and lyrics. Renaming a shared linked
Save changes its name for all placements.
