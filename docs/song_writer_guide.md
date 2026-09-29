# Song & Writer — Feature Guide

This guide covers everything added in the **Song & Writer completion** work: how
each feature behaves, how to use it, and where it lives in the code. It spans the
two arrangement surfaces — the **Writer** (lead-sheet style) and the **Song**
(clip arranger) — plus the bridges between them.

If you just want the short version: *both pages now play the whole song out
loud, the Song arranger gained a full set of editing tools, and both screens
work in portrait and landscape.*

---

## Workspace roles and entry

**Writer** is the section, chord, and lyric sketch. **Song** is the clip
arrangement workspace for note, drum, and audio tracks. Song's **More** menu
has **About Song** help explaining the distinction and **Import from Writer**.
When Song is empty, a timeline action also offers **Import from Writer** if the
current Writer content can produce tracks.

A new install opens Writer. On later starts the app restores the last content
workspace among Fretboard, Piano, Roll, Song, and Writer; visiting Settings
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

### Create a separate project from Writer

Writer's **New project** creates and selects a new Save System project with an
empty Writer session. If the current Writer session differs from its bound
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

---

## 1. Writer playback

The Writer used to be silent — blocks were visual guides and only the metronome
clicked. It now plays the whole arrangement.

**What you hear**

- **Harmony blocks** sound their chord as a per-bar stab: the chord fires on the
  block's first bar and again on every bar boundary it spans. Pitches come from
  the block's `chordNotes` (stacked upward from octave 4), falling back to the
  root + quality intervals.
- **Save blocks** sound the voicing they reference — piano keys play their exact
  MIDI notes, fretboard shapes map string+fret through the tuning. A block whose
  saved item was deleted stays silent.
- **Drum lanes** play their pattern hits at native (16th-note) resolution, tiled
  across the bars the block covers.
- **Melody lanes** play duration-aware notes from reusable patterns edited in
  Piano Roll. Tiles show the pattern's exact musical duration and its block
  placement against the section timeline. A block longer than its pattern
  repeats it from the block start; a shorter block clips it at the placement
  edge. Notes and voices also stop at the section edge.
- **Guitar-strum lanes** play down/up steps from a 16th-note grid against one
  explicitly selected Fretboard Harmony lane. Source selection offers Guitar
  Harmony lanes only, and a strum lane is available only when one exists.
  Multiple strum lanes may share a source. If its saved source becomes invalid,
  the lane shows **Unresolved** and stays silent until repaired; a truly
  unassigned lane shows **Unassigned** and never follows the primary Harmony
  lane. Each pattern tile
  previews its ordered down/up events on the tick grid. Chord tones are
  staggered by 12 ms and gated for half a beat; delayed voices shorten at a
  block edge so they release inside it. Each 44×44 step shows down, up, or off
  and supports keyboard focus and Enter/Space activation.
- The **metronome** is unchanged and still follows the Settings toggle.

**Tempo timing** — Writer and Song use four ticks per quarter note, so a tick
lasts `60,000 / (tempo × 4)` ms in every meter. At 120 BPM, a 4/4 bar lasts
2 seconds and a 6/8 bar lasts 1.5 seconds. Live Writer/Song playback, Song audio
clip timing, and WAV note positions use this same tick duration; the time
signature changes ticks per bar, not tick duration.

**Playhead**

While playing, the active bar cell is highlighted and the sheet auto-scrolls to
keep the current section in view. Press play/stop from the Writer header.

**How to try it**

1. Open **Writer**, add a section, tap a bar, pick a chord from the wheel.
2. Optionally add a drum lane (section menu → *Add drum lane*) and tap in some
   hits.
3. Add a melody lane to create or reuse a pattern, or a guitar-strum lane to
   program down/up steps and choose its Guitar Harmony source.
4. Press play — chords stab, melody sustains for its note lengths, strums voice
   the anchored chords, drums groove, and the playhead sweeps.

**Code:** `lib/schema/rules/songwriter_playback_rules.dart`
(`flattenPlaybackEvents`, `chordMidiNotes`, `snapshotMidiNotes`,
`activePositionForBar`), driven by `lib/store/songwriter_playback_store.dart`.

### Melody pattern duration, reuse, and instrument performance

At an empty bar, choose **Use existing pattern** to place another block linked
to that pattern, or **Create new pattern** to start one in Piano Roll. Reuse
keeps the same notes and Piano/Fretboard mapping, so arrangements such as
A–B–A–B can share pattern A. A new block defaults to the pattern's full duration
when the following bars are free; its placement can be shortened or extended
within the section and around neighboring blocks. The pattern duration comes
from its actual note-pattern length, shown in bars plus any remaining beats and
ticks; the block placement is shown separately in bars against the section's
total length. A longer placement repeats the pattern; a shorter placement
clips notes at the block edge. Editing a reused pattern's duration does not
resize existing blocks, so their repeat or clip behavior remains visible.

Each pattern has one Piano or Fretboard performance target. Piano uses each
note's MIDI key; Fretboard stores a playable string and physical fret for each note and
preserves those positions when the Writer session is reopened or the pattern is
reused from a canonical Writer Save. A fret position must match the note's pitch
under the current tuning, capo, and fret count. The selected
instrument performance view and its position editing are unavailable while
any note is outside that instrument's current playable range; the Piano Roll
remains available for correcting the notes. The target controls the physical
view and mapping; Writer keeps its existing synthesized playback sound.

---

## 2. Song transport

The transport strip gained practice and looping controls. Chips appear after the
BPM/BAR/SIG readouts (the row scrolls horizontally if space is tight).

| Control | What it does |
|---|---|
| **1× / ¾× / ½×** | Practice tempo — slows the playhead without editing patterns. Audio clips keep their natural speed, so this is for note/drum material. |
| **Metronome** | Toggles the click (every beat, accented on the downbeat). |
| **1·2·3** | One-measure metronome count-in before playback starts. |
| **Loop chip** | Appears when a loop region is set; tap to clear it. |

**Loop region** — long-press-drag on the measure ruler to select a
measure-snapped range (painted teal). Playback wraps at the loop end; audio clips
that begin inside the region re-trigger on each pass.

**Auto-follow** — the timeline scrolls to keep the playhead visible while
playing. Scrolling manually pauses following until the next time you press play.

**Per-track volume** — open a track's menu (⋯) → *Volume* for a 0–100 % slider.
Note, drum, and audio output all honor it.

**Code:** `lib/store/song_playback_store.dart` (loop wrap, tempo multiplier,
count-in, metronome sink, volume-aware event firing), transport UI in
`lib/features/song/song_screen.dart`, ruler drag in
`lib/features/song/song_arranger_timeline.dart`.

---

## 3. Reading the timeline

Clips are no longer flat blocks — they show their content at a glance:

- **Note clips** render a mini piano-roll thumbnail (note rectangles scaled to
  the pattern's pitch range).
- **Drum clips** render a step-dot grid, one row per active lane.
- **Audio clips** render their waveform (unchanged).
- Every clip shows its **pattern name** (when wide enough) and a **link badge**
  with a count when the pattern is shared by multiple clips.

**Code:** `_ClipLanePainter` in
`lib/features/song/song_arranger_timeline.dart`.

---

## 4. Clip operations

Select a clip to open the action bar (it scrolls horizontally on narrow
screens). Available actions:

| Action | Notes |
|---|---|
| **Edit** | Opens the pattern editor (piano roll or drum sequencer). |
| **Split** ✂ | Splits the clip at the playhead into two **unique** patterns. Other clips sharing the original pattern are untouched. Park the playhead inside the clip first. |
| **Trim** (audio only) | Head/tail trim sliders; the scheduler plays only the trimmed window. |
| **Duplicate** | Copies the clip immediately after itself. |
| **Copy / Paste** | Copy puts the pattern on a clipboard; long-press a compatible lane → *Paste copied clip* to drop a shared-pattern instance. |
| **Transpose** (note only) | ▲/▼ shift by a semitone; long-press for a full octave. Shared patterns transpose every instance. |
| **Move to track** | Relocates the clip to another same-type track (rejected if the slot is occupied). |
| **Make unique** | Detaches a shared clip onto its own pattern copy. |
| **Delete** | Removes the clip (and the pattern if now orphaned). |

**Snap** — the transport `SNAP ▭ / ♩` chip toggles measure vs beat snapping for
creating, moving, resizing, and pasting clips.

**Track order** — a track's menu (⋯) has *Move up* / *Move down*.

**Code:** store ops in `lib/store/song_project_store.dart`
(`splitClipAtTick`, `setAudioClipTrim`, `transposeClipPattern`,
`moveClipToTrack`, `addClipReference`, `moveTrack`), split maths in
`lib/schema/rules/song_split_rules.dart`, action bar in
`lib/features/song/song_clip_action_bar.dart`.

---

## 5. Markers & zoom

- **Markers** — double-tap the ruler to drop a labeled flag (Verse, Chorus, …).
  Tap a flag to rename or delete it. Flags are painted orange on the ruler.
- **Zoom** — pinch horizontally on the timeline to scale it between 0.5× and 3×.

**Code:** `SongMarker` on `SongProject` (`lib/models/song_project.dart`),
marker store ops + `songTimelineZoomProvider` in
`lib/store/song_project_store.dart`, ruler painting/gestures in
`lib/features/song/song_arranger_timeline.dart`.

---

## 6. Cross-feature bridges

**Hum a melody** — on a note track, the add-clip sheet offers *Hum a melody*,
which creates an empty clip and opens the piano-roll editor with the hum
recorder ready.

**Import from Writer** — choose the action on an empty Song timeline when the
current Writer content can produce tracks, or open **More** → *Import from
Writer*. The conversion rebuilds the song from the current Writer arrangement:

- sections (with repeats expanded) → measures, plus one **marker per section
  instance**;
- the **harmony lane** → a note track of per-bar chord stabs (one pattern per
  block, reused across repeats);
- **drum lanes** → drum tracks carrying the same patterns;
- **save lanes** → note tracks of stacked-chord voicings from the resolved saves;
- **melody and guitar-strum lanes** → duration-aware Song note tracks, including
  the strum's 12 ms tone offsets;
- tempo, time signature, and key are copied over.

It asks for confirmation before replacing meaningful Song state, including
trackless edits such as user-created markers or nondefault Song config; only an
untouched default Song skips confirmation.
Writer audio lanes remain in Writer and are not included in this conversion.
Imported note offsets and durations are also used by Song live playback and WAV
rendering.

**Fretboard/Piano handoff** — in the instrument detection panel, choose
*Add to Writer*, select a detected chord or the exact instrument voicing, then
choose a Writer section and bar. A chord placement belongs to a Harmony lane
with the same instrument; its symbol and native Piano/Fretboard realization
stay together in one Harmony Save. An exact voicing remains a separate
placement in a Save/Voicing lane anchored to a compatible Harmony lane. A
native handoff offers a compatible Save/Voicing lane or stages one when none
exists. A saved root idea can also be explicitly linked with **Use in Writer**,
preserving its root save and sharing later edits across placements.

If there is no selected project, the project picker opens; canceling it leaves
the selection and Writer untouched. An empty Writer project can create its
default eight-bar section before placement. Occupied bars are identified in
text and offer replace-with-confirmation, choose-another-bar, or cancel. If the
project changes while choosing a bar, Writer cancels the handoff and explains
that the destination changed. Occupancy includes expanded lane repeats.
Replacing a repeated placement updates its stored source block in place, so
every copy gets the new chord or voicing at the same offsets; the confirmation
explains that all copies change together.

Tap a Harmony block and choose **Edit in Piano** or **Edit in Fretboard** to
open its native instrument representation. When a Save is used in multiple
Writer placements, updating it offers **Update all placements** or **Create
standalone Save**. The standalone choice leaves Writer unchanged. Use
**Replace chord** on a Writer block to apply that Save to one placement; its
bar, duration, repeats, and local lyrics stay in place. The Save must match the
Harmony lane's instrument. The Harmony block action **Create standalone Save**
copies the complete chord Save to the project root and leaves all existing
placement links alone; **Make Unique** keeps its detach behavior for other
block kinds. Deleting a Harmony lane removes its dependent Save/Voicing lanes
in the same undoable change, as the confirmation explains. A Save/Voicing lane
with a stale explicit anchor stays visible in its own unresolved row and can
only be reanchored to a compatible Harmony lane; it never falls back to
primary. Tap one of its Save blocks to open the native editor when available,
or choose **Remove save**. If no Harmony lane can accept the blocks, choose
**Remove lane** from the unresolved row. If a Guitar Strum source is removed or
changed to Piano, its saved anchor shows **Unresolved** and stays silent until
you choose another Guitar Harmony lane. An unassigned anchor shows
**Unassigned** and never follows the primary Harmony lane. Section category
folders are managed by Writer; deleting a block
removes its link while keeping recoverable content. Named Song versions retain
the block content as saved. Loading an older version forks content whose shared
save has since changed, while keeping the current project's tempo, meter, and
key after showing any differences.

**Record an audio take** — in Song, tap an empty audio lane and choose *Record
audio*. After count-in, stop to open the take review. **Audition** plays the
pending take once; **Re-record** replaces it at the same track and tick;
**Keep take** adds it to the arrangement; **Discard** deletes it without
changing the Song. Dismissing the review also discards the pending take.

**Export WAV** — the overflow menu → *Export WAV* renders all audible note,
drum, and supported audio tracks to mono PCM16 at 44.1 kHz. Audio sources must
be valid little-endian PCM16 WAV files with one or two channels at 8,000–96,000
Hz. Stereo is downmixed and other supported rates are resampled. Trim values
use source samples; source speed, track gain, mute/solo, and tick-based clip
starts are preserved. A missing, compressed, malformed, or unsupported source
blocks export with the clip name and a convert/re-import instruction.

Android/iOS share the generated file; macOS/Windows/Linux save it to a selected
path. Web supports note/drum-only WAVs through browser sharing or download; a
Song with any audio clip is blocked with guidance to export from a native
platform.

**Export Song Bundle** — Song's overflow menu packages the clip arrangement as
a versioned `.mzbundle` ZIP with `manifest.json`, `song.json`, and the original
referenced audio sources (WAV/MP3/M4A). Individual audio entries are limited to
50 MB; the archive and its declared contents are limited to 100 MB. Native
platforms share or save the bundle.

**Import Song Bundle** — on Android, iOS, macOS, Windows, and Linux, choose
*Import Song Bundle* from the Song overflow menu and select a `.mzbundle` with
the system picker. If the current Song has content, confirm replacement before
the picker opens. Import checks the bundle version, Song schema, safe archive
paths, referenced assets, declared and extracted byte lengths, and size caps
before changing the repository. Audio sources receive fresh local IDs; project
references are remapped and the Song is replaced only after all files copy.
Failure leaves the current Song and files intact. Success creates one undoable
replacement and retains previous media for Undo/Redo. Canceling confirmation
leaves both Song and files unchanged. Web explains that bundle import/export
are unsupported because its audio repository is filesystem-backed.

**Undo and redo** — each workspace's overflow menu exposes project-scoped
history, capped at 50 prior snapshots in memory. Song replacement through
Import from Writer or Song Bundle takes one undo step. New project, project
switch, and named save/snapshot load clear history; a new edit clears Redo.
Writer delete snackbars share the normal Writer undo history and dismiss when a
later edit makes the original snackbar action stale.

**Code:** `songFromSongwriter` (`lib/schema/rules/song_from_writer_rules.dart`),
`renderSongPcm` (`lib/schema/rules/song_render_rules.dart`),
`exportSongToWav` (`lib/features/song/song_export_actions.dart`),
`importFromSongwriter` in `lib/store/song_project_store.dart`.

---

## 7. Portrait & landscape

Both screens reflow responsively — no separate layouts, no overflow at phone
sizes in either orientation.

- **Song** — on height-starved (landscape) viewports the header collapses to a
  slim single row so the timeline keeps the vertical space. The New / Import /
  Export WAV / Export Song Bundle / Import Song Bundle actions live in the
  **More** menu to keep the row compact. When Song is empty and Writer content
  can produce tracks, **Import from Writer** also appears on the timeline; the
  More entry remains available. If the empty-state copy and actions need more
  height than the timeline has, that content scrolls vertically.
- **Piano/Fretboard detection** — the shared results panel scrolls vertically
  when it exceeds the available height.
- **Writer** — in landscape the title row is dropped and the overflow button
  moves into the config strip; when the viewport is wide enough the section
  cards flow in **two columns**.

**Code:** `lib/features/song/song_screen.dart`,
`lib/features/songwriter/songwriter_header.dart`,
`lib/features/songwriter/songwriter_screen_sheet.dart`.

---

## Interactive in-app guide

Both the Song and Writer headers have a **`?`** button that launches a
step-through **coach-mark tour**: it dims the screen, spotlights one real UI
element at a time (transport, timeline, add-track, overflow on Song; header,
sections, add-section on Writer) and shows a tooltip with Back / Skip / Next.
It runs only when you tap `?` (no auto-popup), works in portrait and landscape,
and gracefully skips any step whose target isn't on screen.

**Code:** engine `lib/ui/core/coach_overlay.dart` (`CoachStep`,
`startCoachTour`); step scripts `lib/features/song/song_coach_steps.dart` and
`lib/features/songwriter/songwriter_coach_steps.dart`.

## Known follow-up

- The **Fretboard** (and possibly **Piano**) tab still overflows in landscape —
  pre-existing, tracked separately, not part of this work.
- Audio trim is numeric-slider only; waveform-drag handles and fade in/out are
  future polish.
