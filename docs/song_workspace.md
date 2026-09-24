# Song Workspace

The `Song` tab provides a pattern-based clip arranger with note, drum, and audio
tracks. It is the timeline workspace; Writer is the section, chord, lyric,
melody, and groove sketch used to plan a song before arranging its clips.

## Overview

- **Tracks**: Note tracks, drum tracks, and audio tracks, each with mute, solo, rename, duplicate, and delete. Writer melody and guitar-strum lanes import as note tracks.
- **Clips**: Instances of reusable patterns (note/drum) or unique audio buffers placed on a track timeline.
- **Patterns**: Note patterns and drum patterns are shared across multiple clip instances; audio clip patterns are 1:1 with their underlying file.
- **Undo/Redo**: the overflow menu offers project-scoped undo and redo for track, clip, pattern, marker, and song-config edits.

## Pattern Reuse

- Editing a shared pattern updates every clip instance that references it.
- **Make Unique** clones a pattern and relinks only the active clip — other clips continue referencing the original.

## Editing

- **Note clips** open a piano-roll editor mounting the full `PianoRollScreenV2` shell (stack builder, detection panel, hum recorder, tools, snap, pitch range, transport). The scale picker and save/load panels are hidden — scale is inherited from the song scale (see below), and load would smash the host pattern length. The editor uses an isolated `ProviderContainer` so edits never leak into the standalone `Roll` tab.
- **Drum clips** open a step sequencer with 8 lanes (kick, snare, hi-hats, clap, toms, crash).

### Song scale

The song carries an optional scale (`SongProjectConfig.scaleRoot` + `scaleName`).
- Set or clear it from the chip in the Song header.
- On compact screens, open **More → Song scale** to keep the header within the available width.
- When set, every note-pattern editor seeds its `highlightedNotes` from the song scale; the per-pattern `highlightedNotes` field is preserved on save as a fallback for when the song scale is cleared later.
- Applying a song scale that conflicts with notes already placed in any pattern prompts a confirmation; on confirm the conflicting notes are removed from every pattern.
- When no song scale is set, the editor falls back to each pattern's own `highlightedNotes`.

## Import

Create clips from existing saves:
- `Piano Roll` save → exact note timings
- `Piano` save → stacked chord at tick 0
- `Fretboard` save → stacked chord at tick 0

New empty patterns default to 1 measure.

## Playback

Song-level transport plays all audible tracks. Muted tracks are silent unless soloed.
Solo takes priority over mute — if any track is soloed, only soloed tracks play.

Writer and Song use the same tempo grid: four ticks per quarter note, with
`60,000 / (tempo × 4)` milliseconds per tick. Meter determines ticks per bar;
at 120 BPM, a 4/4 bar lasts 2 seconds and a 6/8 bar lasts 1.5 seconds. Song live
playback, audio clip start/seek/length/stop timing, and WAV note sample positions
share that conversion. Note durations, sub-tick onset offsets, and boundary
duration trims survive Writer import and Piano Roll editing.

### Transport controls

- **Per-track volume** (`SongTrack.volume`, 0–1, default 1): set from the track
  menu's Volume slider. Note/drum sink volume is `0.8 × track.volume`; audio
  clips pass the gain to the player.
- **Loop region**: long-press-drag on the measure ruler selects a
  measure-snapped region (painted teal). The tick clock wraps at the loop end;
  audio clips that start inside the region re-arm on each pass. The loop chip
  in the transport clears it.
- **Practice tempo**: the `1×/¾×/½×` chip scales the tick duration only
  (patterns play slower; audio clips keep their natural speed, so they drift
  under a multiplier — practice tempo is meant for note/drum material).
- **Metronome + count-in**: the metronome chip toggles
  `settings.metronomeEnabled` (clicks every beat, accented on the measure);
  the `1·2·3` chip enables a one-measure count-in before the clock starts.
- **Auto-follow**: the timeline scrolls to keep the playhead visible during
  playback; a manual horizontal scroll pauses following until the next play.

## Clip operations

Selecting a clip opens the action bar: edit pattern, split at the playhead
(`splitClipAtTick` — slices into two unique patterns; shared siblings keep the
original), duplicate, copy-for-paste (long-press a lane → Paste), transpose
note clips (±1 / ±octave), move to another same-type track, audio trim
(head/tail, honored by the scheduler), make-unique, delete. The transport
`SNAP` chip toggles measure vs beat snapping; the track menu reorders tracks
and sets per-track volume. Clips render content previews: note thumbnails,
drum step dots, audio waveforms, plus the pattern name and a shared-pattern
badge.

## Markers & zoom

Double-tap the ruler to drop a labeled marker (verse, chorus, …); tap a marker
flag to rename or delete it. Pinch horizontally on the timeline to zoom
(`songTimelineZoomProvider`, 0.5×–3×).

## Cross-feature

- **Hum a melody**: the add-clip sheet on note tracks creates an empty clip and
  opens the piano-roll editor (hum recorder included) straight away.
- **Import from Writer**: the header overflow menu rebuilds the song from the
  Songwriter arrangement (`songFromSongwriter`): sections → measures + a marker
  per instance, the harmony lane → a note track of per-bar chord stabs, drum
  lanes → drum tracks, save lanes → voicing note tracks, melody and guitar-strum
  lanes → duration-aware note tracks with millisecond onset offsets; tempo /
  time signature / key copied over.
  Import asks before replacing a non-empty Song and commits the replacement as
  one undoable transaction. Writer audio lanes are not included.
- **Fretboard/Piano to Writer**: use **Add to Writer** in an instrument's
  detection panel to place a detected chord or exact voicing at a chosen Writer
  section and bar. Exact voicings are embedded in the Writer block and do not
  require a library save.

Writer audio lanes are not included in **Import from Writer**. The Song header's
**About Song** help describes Song as the
clip-arrangement workspace and Writer as the section, chord, and lyric sketch.
- **Export WAV**: the overflow menu renders audible note, drum, and supported
  audio tracks to mono PCM16 at 44.1 kHz. WAV clips must be valid little-endian
  PCM16 with one or two channels and an 8,000–96,000 Hz sample rate. Stereo is
  averaged to mono and other supported rates are linearly resampled. Clip trims
  are applied at the source rate; source playback speed, track gain, mute/solo,
  and timeline start ticks are preserved. A missing, compressed, malformed, or
  unsupported audio source blocks the export and identifies the clip with a
  convert-to-PCM16-WAV/re-import instruction.
- **Export Song Bundle**: the overflow menu creates a portable `.mzbundle` ZIP
  containing `manifest.json`, the complete clip arrangement in `song.json`,
  and each referenced original WAV/MP3/M4A source under `audio/`. The manifest
  uses `format: "muzician-song-bundle"` and `schemaVersion: 1`. Each audio entry
  is limited to 50 MB and the compressed archive and its declared contents are
  each limited to 100 MB.
- **Import Song Bundle**: on Android, iOS, macOS, Windows, and Linux, the
  overflow menu opens a system picker for `.mzbundle`. A non-empty Song requires
  confirmation before the picker opens. Import validates the versioned manifest,
  Song schema, exact safe archive paths, all referenced assets, byte lengths,
  and compressed/declared/extracted size limits before writing. Each supported
  WAV/MP3/M4A source is staged and copied under a fresh repository ID; the Song
  and every audio-pattern reference are remapped and replaced only after all
  copies succeed. Failed imports leave the active Song and existing files
  intact. A successful replacement is one undoable action; its previous media
  stays available for Undo/Redo. Canceling replacement leaves Song and files
  unchanged. Web explains that bundle import/export are unsupported because
  local audio assets do not persist across reloads.

Generated-file delivery follows the platform: Android/iOS open the native
share sheet, macOS/Windows/Linux show a save dialog and write bytes to the
selected path, and Web uses browser sharing with a download fallback. Web WAV
export supports note/drum-only Songs; if any audio clip is present, it explains
that WAV export must run on a native platform. Song Bundle import and export are
unavailable on Web because local audio files do not persist across reloads.

## Save / Load

Song projects save as `SongProjectSnapshot` through the shared save browser.
A saved project contains:
- Global config (tempo, time signature, measures)
- All tracks, clips, note/drum/audio patterns, audio asset metadata, and markers
- Audio source files stay in the local repository; use **Export Song Bundle**
  to carry referenced originals to another device

### Session auto-save

The active Song workspace is auto-persisted per project through
`SongSessionsNotifier` (`lib/store/song_sessions_store.dart`), which stores a
`Map<String, SongProject>` keyed by project ID in a single `SharedPreferences`
slot (`@muzician/song_sessions/v1`).  Every mutation in `SongProjectNotifier`
triggers a debounced (~500 ms) write of the map so the last session for every
project is always saved.

`songProjectProvider` (`lib/store/song_project_store.dart`) watches
`selectedProjectId` changes.  When the project changes, the current session is
persisted under the previous project ID, and the session for the new project ID
is loaded from the map (falling back to a default project seeded from the
project's `ProjectConfig` if no session exists).  On app start,
`songSessionsProvider.hydrate()` restores the full map from shared preferences.

Tap the **New Song** button in the Song header to load
`getDefaultSongProject()` into the current project's session slot.  A
confirmation dialog protects against accidental overwrites; on confirm, the
current project's session slot is replaced with the default empty song and its
undo/redo history is cleared.

Song undo history is held only in memory, keeps at most 50 prior snapshots, and
clears on project switch or named save/snapshot load. Continuous clip, trim,
track-mix, and tempo slider gestures form one history step when released. A new
edit after Undo clears Redo.

## Audio Playback Sink

Audio clips on audio tracks are routed through `SongAudioClipSink`.  The
production implementation (`AudioPlayersClipSink`) holds one `AudioPlayer` per
asset id and is configured for simultaneous playback:

- On construction it installs a global `AudioContext` with the iOS
  `playback` category and the `mixWithOthers` option so internal players do
  not preempt each other when their sessions activate.
- `startPlayback` calls `audioSink.prepare(...)` once before the tick loop.
  This binds every scheduled clip's file source via `setSource`, paused.
  The tick loop's parallel `startClip` calls then only seek + resume — no
  concurrent `setSource` races where two clips fired at the same tick could
  leave one player silent.
- Sources stay loaded across clips via `ReleaseMode.stop` so re-triggering a
  clip is just a seek.

## Audio Tracks (v1.1)

Audio tracks host clips from microphone recordings or imported files.

- **Record**: tap an empty audio lane → `Record audio` → 1-measure count-in (metronome hi-hat) → song playback starts in the background while the mic captures. Tap `Stop` to review the take without changing the arrangement. **Audition** plays it once; **Re-record** replaces the pending take at the same track and tick; **Keep take** commits it; **Discard** removes the pending audio file without adding a clip. Cancel during count-in/recording or dismiss the sheet to abort.
- **Import**: tap-lane → `Import audio file` → choose WAV, MP3, or M4A (max 50 MB) via the system file picker.
- **Storage**: audio files live in `appDocs/song_audio/<assetId>.<ext>`. Regular saves reference assets by id; Song Bundles package the referenced source bytes for portability.
- **Tempo**: clip length in ticks tracks the project tempo; the real audio duration never changes.
- **Limits**: no trim, no per-clip volume / pan / fade, no time-stretch, no live monitoring. Mute/solo applies at the track level only.
- **Web**: recording is disabled; import works via the standard file picker but files do not persist across reloads. Web WAV export is limited to note/drum-only Songs; Song Bundle export is unsupported.
- **Broken clips**: if a referenced file is missing on load, the clip renders with a red diagonal stripe and stays silent during playback.
- **Auto-mute**: the target audio track is muted while you record so its prior clips do not bleed back through the mic.

## Project lock

When a project folder is selected (`isProjectLockedProvider`), the Song
workspace inherits tempo and time signature from the project's `ProjectConfig`
via `projectConfigSyncProvider` (`lib/store/project_config_sync.dart`), which
also pushes the project key/scale into the Song store.  The scale chip is
hidden and a `ProjectChip` widget is shown in the Song header next to the New
Song / Add Track buttons.  Change project values through the project config
sheet accessed from the project chip.  Dump and "no project" leave the scale
chip visible and controls free.

## Limitations (v1)

- No clip resize or time-stretching
- Same-track clip overlap not allowed
- No per-clip volume, pan, or fades; track gain and mute/solo are available
