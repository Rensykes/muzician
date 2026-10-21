# Piano

The Studio Piano is a playable MIDI keyboard for selecting exact keys,
exploring voicings and saving ideas. `PianoKeyboard` uses a widget `Stack`,
with white keys first and black keys overlaid above them. Its compact chord
previews use `CustomPainter`. The default range is 61 keys, C2–C7.

## Workspace

Project context has its own row above the full Piano title. The **?** action
opens shared help. Setup in the inspector exposes the current range, and the
Instrument setup footer action shows its full range label in a tooltip.

Below the keyboard, a compact summary shows the first detected chord or
**Exact selection**, plus selected MIDI notes with their octaves. **Save
idea** is outlined and opens the existing save browser/naming flow. The filled
**Add to Writer** action keeps
recognized-chord and exact-note handoff, including unrecognized combinations.
**Library** opens the same browser for loading, renaming and linked-Save
updates. **Scale** opens the shared picker, displays the active key and warns
when a committed chord contains notes outside the project key.

The inline inspector defaults to **Voicings** and can collapse without
clearing selected MIDI keys or resetting its local picker state. Underlined
Notes / Voicings / Setup tabs replace a separate inspector heading. Compact
root/quality selectors share one row with a labelled octave dropdown and lead
directly to native inversion previews, followed by project-key suggestions.
Scale, Library and Instrument setup remain available in its compact footer:

| Tab | Controls |
| --- | --- |
| Notes | Pitch-class focus, inversion-aware chord detection, compatible scales, Clear |
| Voicings | Project-key diatonic chords, chromatic root/quality, octave selector and root/first/second inversion diagrams |
| Setup | Exact/Solo view and 49/61/88-key ranges; subdued Clear all selections action below the settings |

Selecting a detected chord switches to the one existing inline picker.
Committed voicings override detection until a manual keyboard edit. Notes
Clear deselects keys; Setup Clear all also removes local filters and stays in
the workspace. The octave dropdown has a 48px target. Studio voicing cards
are 102×100px at
standard text size, with 6px corners and native 86×44px keyboards. All three
inversions fit a 390px viewport. Cards grow with text scale and scroll
horizontally; legacy cards retain their original 142px minimum width.

Notes starts directly below its tab and sizes to its results. Compact screens
use the page's vertical scroll, while wide screens use the bounded inspector
rail, without a second vertical scroller inside detection. Setup labels the
native range control once and keeps Clear all selections after the settings
as a text action with a 44px minimum touch target.

At widths of at least 700px with at least 500px available height, content and
a 316–360px inspector column sit beside one another with independent scrolling.
Compact and short windows use a scrolling page. The Studio keyboard canvas is
226px tall: white keys are 42×190px and black keys 26×118px. Horizontal key
positions and hit testing remain native; scrolling reveals the remaining range.
Legacy hosts retain 42×210px white keys and 26×130px black keys. Named controls
use at least 44px tap regions, while native black-key widths remain smaller.
Short landscape scrolls the full page rather than further shrinking keys.

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
physical keyboard. **Solo** hides unrelated keys when a selection exists;
**Exact** retains the full keyboard. Voicings load exact MIDI keys in the
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
- `piano_chord_picker.dart` / `piano_chord_diagram.dart`: octave/inversions and
  immutable palette-aware miniature painter.
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
