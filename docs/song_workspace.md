# Song Workspace

The `Song` tab provides a pattern-based clip arranger with note and drum tracks.

## Overview

- **Tracks**: Note tracks, drum tracks, and audio tracks, each with mute, solo, rename, duplicate, and delete.
- **Clips**: Instances of reusable patterns (note/drum) or unique audio buffers placed on a track timeline.
- **Patterns**: Note patterns and drum patterns are shared across multiple clip instances; audio clip patterns are 1:1 with their underlying file.

## Pattern Reuse

- Editing a shared pattern updates every clip instance that references it.
- **Make Unique** clones a pattern and relinks only the active clip — other clips continue referencing the original.

## Editing

- **Note clips** open a piano-roll editor mounting the full `PianoRollScreenV2` shell (stack builder, detection panel, hum recorder, tools, snap, pitch range, transport). The scale picker and save/load panels are hidden — scale is inherited from the song scale (see below), and load would smash the host pattern length. The editor uses an isolated `ProviderContainer` so edits never leak into the standalone `Roll` tab.
- **Drum clips** open a step sequencer with 8 lanes (kick, snare, hi-hats, clap, toms, crash).

### Song scale

The song carries an optional scale (`SongProjectConfig.scaleRoot` + `scaleName`).
- Set or clear it from the chip in the Song header.
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
  lanes → drum tracks, save lanes → voicing note tracks; tempo / time signature
  / key copied over.
- **Export WAV**: the overflow menu renders note + drum tracks to a mono PCM16
  WAV (`renderSongPcm`) and writes it via the platform save dialog. Audio clips
  are excluded in v1 (a dialog notes this when the song has any).

## Save / Load

Song projects save as `SongProjectSnapshot` through the shared save browser.
A saved project contains:
- Global config (tempo, time signature, measures)
- All tracks, clips, note patterns, and drum patterns

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
current project's session slot is replaced with the default empty song.

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

- **Record**: tap an empty audio lane → `Record audio` → 1-measure count-in (metronome hi-hat) → song playback starts in the background while the mic captures → tap `Stop` and the clip is committed to the track immediately. There is no review step; remove the clip from the timeline if you do not want to keep the take. Tap `Cancel` during count-in or recording to abort without producing a clip.
- **Import**: tap-lane → `Import audio file` → choose WAV, MP3, or M4A (max 50 MB) via the system file picker.
- **Storage**: audio files live in `appDocs/song_audio/<assetId>.<ext>`. Save files reference assets by id; cross-device portability is not supported in v1.
- **Tempo**: clip length in ticks tracks the project tempo; the real audio duration never changes.
- **Limits**: no trim, no per-clip volume / pan / fade, no time-stretch, no live monitoring. Mute/solo applies at the track level only.
- **Web**: recording is disabled; import works via the standard file picker but files do not persist across reloads.
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
- No volume, pan, or mixer controls
- No undo/redo
