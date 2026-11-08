# Writer — Feature Guide

This guide covers the **Writer** arrangement surface: how each feature behaves,
how to use it, and where it lives in the code.

---

## Workspace roles and entry

**Writer** is the section, chord, and lyric sketch. It is the only arrangement
workspace in the app.

A new install opens Writer. On later starts the app restores the last content
workspace among Fretboard, Piano, Roll, and Writer; visiting Settings
does not replace that choice. If saved workspace data cannot be read, the app
keeps workspaces closed and offers Retry or Start fresh. Start fresh first
preserves the original stored strings in **Settings → Data Recovery**, where
each backup can be read, copied, exported, or deleted after confirmation.

Projects created through the usual project flow use the configured default
Harmony instrument, prompting for the first choice if that default is unset;
the choice is saved in Settings for future projects. **New project** in Writer
asks for Piano or Fretboard on every creation and stores that choice on the new
project without changing the app-wide default. Each new section starts with a
primary Harmony lane using its project's default; additional Harmony lanes ask
for their instrument when created. An empty Harmony lane with no anchored
Save/Voicing lane can change instruments while keeping its lane identity.

Fretboard Harmony headers provide **Sound: Clean / Distorted**. This is the
same device preference as Fretboard audition and applies to Harmony, Guitar
Strum, and legacy Melody guitar playback; explicit Melody lane sounds override
it. Changing it leaves the saved chord and its notes intact. Writer uses
an unframed transport, plain Bars/Repeat disclosures, and compact mixer rows
separated by dividers while preserving the musical cells and all lane controls.

### Create a separate project from Writer

Writer's main-menu **New project** creates and selects a new Save System
project with an empty Writer session. If the current Writer session differs
from its bound
active named Writer Save (or from the full project-default session when no
Save is bound), choose **Keep**, **Discard**, or **Cancel** before switching.
**Keep** retains the outgoing project's session. **Discard** restores its
bound active Writer Save through the normal canonical block reconciliation
path, keeping the current project config and forking changed linked block
content when needed. If no valid Writer Save is bound, Discard clears that
project's Writer session and binding. Either Discard path preserves every
named Save entry. **Cancel** leaves the current project and session in place
and creates no project. The new project's Piano/Fretboard choice belongs to its project
config and does not update the Settings default.

The project key is tonic plus scale/mode. Set, change, or clear it from
Writer's KEY chip or the Fretboard/Piano scale controls, then confirm the
project update. Cancel leaves the previous key and selected notes untouched.
The confirmed key is shared across Writer and the instrument tabs; loading
an instrument Save, including one in Roll, does not override it. Dump and
no-project scale choices remain local.

**Settings → Prefer flat note names** controls spelling throughout the workspaces:
for example D# minor pentatonic becomes Eb minor pentatonic. It changes labels,
preserving the key, pitches, and custom names. **Change chord** uses a seven-degree
wheel when supported; for pentatonic and other unsupported scales it opens the
root/quality picker directly, with the current key retained. Wheel labels follow
the device's text-size setting, and each degree is available as a labeled
accessibility action.

---

## 1. Writer playback

The Writer used to be silent — blocks were visual guides and only the metronome
clicked. It now plays the whole arrangement.

**What you hear**

- **Harmony blocks** sound their chord as a per-bar stab: the chord fires on the
  block's first bar and again on every bar boundary it spans. Named exact
  Harmony plays its saved Piano MIDI notes or Fretboard string/fret positions
  in their original register. Symbolic Harmony uses the block's `chordNotes`
  (stacked upward from octave 4), falling back to root + quality intervals.
- **Save blocks** sound the voicing they reference — piano keys play their exact
  MIDI notes, fretboard shapes map string+fret through the tuning. A block whose
  saved item was deleted stays silent.
- **Drum lanes** play their pattern hits at native (16th-note) resolution, tiled
  across the bars the block covers.
- **Melody lanes** play duration-aware notes from named, reusable patterns edited
  in Piano Roll. A melody's length is its last note rounded up to whole bars.
  Tiles show the pattern's single-pass window and its block placement against
  the section timeline. A block shorter than its melody clips it at the
  placement edge; a block longer than its melody plays once and then holds a
  silent tail. Notes and voices also stop at the section edge, and melody
  content never loops past its last note.
- **Guitar-strum lanes** play down/up steps from a 16th-note grid against one
  explicitly selected Fretboard Harmony lane. Source selection offers Guitar
  Harmony lanes only, and a new strum lane is available only when an unused
  source exists.
  Each source can belong to only one strum lane in a section. Other lanes hide
  that occupied source; the owning lane retains its current selection.
  Unassigned lanes reserve no source. If its saved source becomes invalid,
  the lane shows **Unresolved** and stays silent until repaired; a truly
  unassigned lane shows **Unassigned** and never follows the primary Harmony
  lane. Each pattern tile
  previews its ordered down/up events on the tick grid. Chord tones are
  staggered by 12 ms and gated for half a beat; delayed voices shorten at a
  block edge so they release inside it. Each 44×44 step shows down, up, or off
  and supports keyboard focus and Enter/Space activation.
- The **metronome** is unchanged and still follows the Settings toggle.

**Tempo timing** — Writer uses four ticks per quarter note, so a tick lasts
`60,000 / (tempo × 4)` ms in every meter. At 120 BPM, a 4/4 bar lasts 2 seconds
and a 6/8 bar lasts 1.5 seconds. Writer playback, audio clip timing, and WAV note
positions use this same tick duration; the time signature changes ticks per bar,
not tick duration.

**Playhead**

While playing, the active bar cell is highlighted and the sheet auto-scrolls to
keep the current section in view. Press play/stop from the Writer header.

**How to try it**

1. Open **Writer**, add a section, tap a bar, pick a chord from the wheel.
2. Optionally add a drum lane (section menu → *Add drum lane*) and tap in some
   hits.
3. Add a melody lane to create or reuse a pattern. In its Piano Roll editor,
   use **Bars** to extend the canvas to the melody's bars and the rename action
   to name it, then **Save**. Add a guitar-strum lane to program down/up steps
   and choose its Guitar Harmony source.
4. Press play — chords stab, melody sustains for its note lengths, strums voice
   the anchored chords, drums groove, and the playhead sweeps.

**Code:** `lib/schema/rules/songwriter_playback_rules.dart`
(`flattenPlaybackEvents`, `chordMidiNotes`, `snapshotMidiNotes`,
`activePositionForBar`), driven by `lib/store/songwriter_playback_store.dart`.

### Melody length, naming, reuse, and instrument performance

At an empty bar, choose **Use existing pattern** to place another block linked
to that pattern, or **Create new pattern** to start one in Piano Roll. Reuse
keeps the same notes and Piano/Fretboard mapping, so arrangements such as
A–B–A–B can share pattern A. A melody is named in its Piano Roll editor. Its
**Bars** stepper extends the canvas from 1 to 32 bars and cannot shrink below
the bar containing the last note. The melody Piano Roll locks tempo and time
signature to the project, so its bars always match the saved project. Saving
applies the edited name and notes and stores the length as the whole bars
containing the last note, with a one-bar minimum; a note ending inside a bar
still occupies that whole bar, with silence after it. Changing Bars or
shortening a placement never deletes notes. Renaming a shared melody updates
every linked block label; cancelling leaves the previous name and content.

A new block uses the melody's full bar count when that placement is valid. It
may instead be shortened or rejected if no valid placement is available, even
when bars appear free, because existing automatic repeat origins must be
preserved. Subsequent moves and resizing use the same rules, with one
compatibility exception: a retained over-long placement may move without
changing its span, but any resize must end within the placement limit. A
bar-aligned melody limits placements to its last-note bar. An older
non-bar-aligned stored length may use its rounded-up bar count for placement
validation and creation until the next melody save normalizes it. A placement
may shrink to any whole bar but cannot extend beyond that placement limit.
The block placement is shown separately in bars against the section's total
length. A shorter placement clips notes at the placement edge. A placement
longer than its melody, typically retained from an older project, keeps its
occupied bars, plays the melody once, and shows a silent tail; it never loops
the melody. Adding a Melody lane creates a one-bar pattern and a one-bar
placement. On the first save after notes are added to that empty pattern, the
placement expands to the melody's full bar count when the whole span fits the
section and lane. This happens whether you first add notes from the block tile
or from **Edit performance**. Every save also normalizes the stored length to
whole bars. Later saves never resize placements, so editing a reused
pattern's length does not change existing blocks. Legacy melodies stored longer
than 32 bars keep their notes, but playback and the hatched silent tail stop at
bar 32, so later notes stay inaudible until the melody is saved within the
editor cap.

The Melody timeline wraps in numbered four-bar rows. Each block's miniature,
non-interactive piano roll shows its notes across the single-pass window and
clipped edges, with pitch aligned across continuation rows and a separate name
strip. A diagonal hatch and summary mark the silent-tail bars of a longer
placement. Linked previews update together; missing patterns or
missing/incompatible canonical Saves show a warning instead of cached notes.
The detail row marks unresolved content so it is distinguishable from an empty
pattern. Use Piano Roll to edit notes.
A block crossing rows has continuation segments and one final-edge handle;
drag to resize in whole bars,
or use **Adjust placement** to move or resize without dragging. Resizing stops
at the placement limit: the last-note bar for normalized melodies, or the
rounded-up stored length for legacy non-bar-aligned patterns until their next
save. An over-long legacy placement can shrink directly to a valid span, while
a move that keeps its span leaves the silent tail in place, and **Adjust
placement** explains the melody limit when the requested length exceeds it. A
completed drag is one undo step;
cancelling leaves the placement unchanged. Automatic lane
repeats are marked and reserve their visible bars, including repeats clipped at
the section edge. Changes that overlap them or shift their existing origins by
changing the lane's natural period are rejected; use the Melody lane's **Repeat** control first
when necessary. **Repeat / reuse** picks a free start in the same lane and makes
a new placement sharing the pattern and canonical Save. It copies the source
placement's span, capped by the melody's placement limit and the free space at
that start; it does not force the full melody length, so a short window can be
repeated as-is. A free start can still be rejected if no span preserves
existing repeats. Missing or unresolved content cannot be repeated. Shared edits
affect all linked placements; **Make Unique** detaches only the selected
placement, and resizing never changes the shared pattern. **Delete placement** removes
one authored placement and its automatic repetitions without deleting its Save;
if that would move another block's repeats, reduce the lane repeat first. A
clipped placement can be resized back inside a shortened section. Incompatible
canonical Saves remain intact and content editing is disabled until resolved.

Each pattern has one Piano or Fretboard performance target. Piano uses each
note's MIDI key; Fretboard stores a playable string and physical fret for each note and
preserves those positions when the Writer session is reopened or the pattern is
reused from a canonical Writer Save. A fret position must match the note's pitch
under the current tuning, capo, and fret count. The selected
instrument performance view and its position editing are unavailable while
any note is outside that instrument's current playable range; the Piano Roll
remains available for correcting the notes. The target controls the physical
view and mapping, independently of the Melody lane's **Sound**. New Melody lanes
default to Piano; choose Piano, Clean guitar, or Distorted guitar per lane. An
older unset lane displays **Pattern sounds** and retains its per-pattern
Piano/Fretboard sound, using the shared device guitar tone for Fretboard, until
an explicit sound is chosen. The choice does not change the performance mapping,
other lanes, or global guitar preference; it takes effect at the next transport
start.

---

## 2. Portrait & landscape

Writer reflows responsively — no separate layouts, no overflow at phone sizes
in either orientation.

- **Piano/Fretboard detection** — the shared results panel scrolls vertically
  when it exceeds the available height.
- **Writer** uses the selected Studio appearance, with project context first,
  then the full Writer title, **Save version**, and labelled Undo/Redo and
  **Writer versions** icons. A compact key/BPM/play/metronome strip follows;
  controls wrap at larger text sizes and remain in the Writer menu too. Drafts persist
  automatically; **Draft changed** describes a difference from a named Writer
  version. A single section fills the available width. Multiple sections use
  two columns at 1100 logical pixels or wider. Chord sheets put common actions
  first and retain all advanced actions. Section controls share a compact row;
  **Section actions** contains Remove section, recoverable with Undo. Chord
  rows use 64-pixel filled cells and 44-pixel add slots, growing for lyrics,
  distinct Save names, and larger text. Guitar Strum shows an explicit Source
  beside its title and neutral placement strips with accented direction previews,
  keeps Unassigned silent, and groups its 44-pixel 16th steps by the project's
  canonical beat grid (four per quarter-note beat, two per eighth-note beat).
  Steps can wrap within their labelled group on compact screens; no group crosses a bar boundary.
  Open Writer sheets and isolated melody editors follow live theme changes
  while retaining edits.

**Code:** `lib/features/songwriter/songwriter_header.dart`,
`lib/features/songwriter/songwriter_screen_sheet.dart`.

---

## Interactive in-app guide

The Writer header has a **`?`** button that launches a step-through
**coach-mark tour**: it dims the screen, spotlights one real UI element at a
time (header, sections, add-section) and shows a tooltip with Back / Skip / Next.
It runs only when you tap `?` (no auto-popup), works in portrait and landscape,
and gracefully skips any step whose target isn't on screen.

**Code:** engine `lib/ui/core/coach_overlay.dart` (`CoachStep`,
`startCoachTour`); step script
`lib/features/songwriter/songwriter_coach_steps.dart`.

## Known follow-up

- The **Fretboard** (and possibly **Piano**) tab still overflows in landscape —
  pre-existing, tracked separately, not part of this work.

Studio Harmony cells in a mixed row share the tallest cell’s height so their top and bottom edges align. Entirely empty rows retain compact 44-pixel slots; scaled text, lyrics and Save names can increase row height.
