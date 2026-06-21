# Song & Writer — Feature Guide

This guide covers everything added in the **Song & Writer completion** work: how
each feature behaves, how to use it, and where it lives in the code. It spans the
two arrangement surfaces — the **Writer** (lead-sheet style) and the **Song**
(clip arranger) — plus the bridges between them.

If you just want the short version: *both pages now play the whole song out
loud, the Song arranger gained a full set of editing tools, and both screens
work in portrait and landscape.*

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
- The **metronome** is unchanged and still follows the Settings toggle.

**Playhead**

While playing, the active bar cell is highlighted and the sheet auto-scrolls to
keep the current section in view. Press play/stop from the Writer header.

**How to try it**

1. Open **Writer**, add a section, tap a bar, pick a chord from the wheel.
2. Optionally add a drum lane (section menu → *Add drum lane*) and tap in some
   hits.
3. Press play — chords stab, drums groove, the playhead sweeps.

**Code:** `lib/schema/rules/songwriter_playback_rules.dart`
(`flattenPlaybackEvents`, `chordMidiNotes`, `snapshotMidiNotes`,
`activePositionForBar`), driven by `lib/store/songwriter_playback_store.dart`.

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

**Import from Writer** — the Song header overflow menu (⋮) → *Import from
Writer* rebuilds the song from the current Writer arrangement:

- sections (with repeats expanded) → measures, plus one **marker per section
  instance**;
- the **harmony lane** → a note track of per-bar chord stabs (one pattern per
  block, reused across repeats);
- **drum lanes** → drum tracks carrying the same patterns;
- **save lanes** → note tracks of stacked-chord voicings from the resolved saves;
- tempo, time signature, and key are copied over.

It asks for confirmation before replacing a non-empty song.

**Export WAV** — the overflow menu → *Export WAV* renders the note and drum
tracks to a mono PCM16 WAV (sine voices for notes, a small synth kit for drums,
per-track volume applied) and writes it through the system save dialog. **Audio
clips are not included yet** — a dialog says so when the song has any.

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
  Export actions live in the header overflow menu (⋮) to keep the row compact.
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
- WAV export excludes audio clips (v1). Note/drum-only for now.
- Audio trim is numeric-slider only; waveform-drag handles and fade in/out are
  future polish.
