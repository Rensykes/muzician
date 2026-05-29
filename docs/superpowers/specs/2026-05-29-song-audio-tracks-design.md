# Song Audio Tracks Design

Date: 2026-05-29
Status: Draft approved in chat, written for repo review
Scope: First-version audio tracks in the Song workspace — record from microphone or import from file, place clips on the grid, render waveforms, play back in sync with note and drum tracks

## Goal

Extend the existing Song workspace with a third track family — **audio tracks** — that can host audio clips coming from:

1. **Microphone recording** with a count-in, overdubbed against the rest of the song.
2. **File import** (WAV / MP3 / M4A) via the system file picker.

Each audio clip lives on the timeline at a chosen start tick and renders as a waveform block whose grid length tracks the project tempo. Mute, solo, rename, delete, and shared transport all work identically to existing tracks.

The first version is structurally clean rather than feature-rich. No trim, no per-clip volume, no time-stretch, no mixer — the same v1 envelope as note and drum tracks.

## Problem Statement

The current Song workspace can only express what can be played by the internal synth: note patterns and drum patterns. There is no way to:

- capture an idea sung or hummed in tempo with the rest of the song
- bring in a reference loop, a guitar take recorded elsewhere, a sample
- arrange recorded vocal phrases against programmed parts

Both `record` and `audioplayers` are already declared in `pubspec.yaml`, and the `piano_roll_hum_recorder` flow proves the mic capture pipeline works on iOS and Android. The infrastructure is in place; what's missing is a domain and a UI that bind audio clips to the Song timeline.

The existing pattern model (`SongTrack` → `SongClipInstance` → `NotePattern`/`DrumPattern`) is reusable for musical content because two clips can share the same notes. Audio buffers do not share — "editing" raw audio means re-recording — so the audio model needs slightly different semantics inside the same overall shape.

## Decisions Log

The following nine decisions were locked in during brainstorming:

1. **Track architecture** — new dedicated `SongTrackType.audio` alongside `note` and `drum`. Audio clips only live on audio tracks.
2. **Storage** — audio files written to app storage as separate files (`appDocs/song_audio/<assetId>.<ext>`), referenced by id from the project JSON. Save files stay small.
3. **Tempo relationship** — native length, no DSP stretch. The asset's source of truth is `durationMs`; tick length on the grid is derived from project tempo and recomputed when tempo changes.
4. **v1 operations** — record, import, place (drag start tick), rename, delete, mute/solo via track header. No trim, no volume, no fade.
5. **Entry point** — extend the existing tap-lane bottom sheet. When the active track is audio, the sheet shows "Record audio" and "Import audio file".
6. **Recording UX** — overdub flow: 1-measure count-in, project plays while mic records, stop opens a preview with waveform and "Confirm / Retry / Discard" before the clip lands on the grid.
7. **Format** — record WAV PCM mono 44.1 kHz / 16-bit; import WAV, MP3, M4A. Web: record not supported (parity with `hum_to_midi`), import works via standard file picker.
8. **Clip rendering** — waveform peaks pre-computed once at commit, stored as a normalised `List<int>` (0–255) inside `AudioAsset`, rendered by a `CustomPainter`.
9. **Monitoring** — no live mic monitoring in v1. Project playback uses speakers/headphones, mic records independently. Zero feedback risk.

## Non-Goals

- Trim handles or non-destructive edits on audio clips
- Per-clip volume, pan, fade, mute (track-level mute/solo only)
- Time-stretch / pitch-shift / repitch
- Multiple takes per recording session (each preview commits or discards)
- Live mic monitoring through the project mix
- Audio effects, reverb, compression
- Cloud-backed audio storage or export bundle (zip with audio inside) — local files only

These are explicitly deferred and will be addressed by later specs.

## Architecture Overview

Four layers, each owning a single responsibility. Boundaries are enforced so each layer can be tested in isolation.

```
┌────────────────────────────────────────────────────────────────┐
│ UI (features/song)                                             │
│ ─ SongArrangerTimeline  (renders audio clips alongside others) │
│ ─ SongAudioRecorderSheet  (overdub modal)                      │
│ ─ AudioClipBody / AudioWaveformPainter                         │
│ ─ existing bottom-sheet extended with two new actions          │
└────────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────────┐
│ Stores (store/)                                                │
│ ─ song_project_store         (extended for audio clip ops)     │
│ ─ song_audio_recorder_store  (record state machine)            │
│ ─ song_playback_store        (extended with AudioClipSink)     │
└────────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────────┐
│ Repository (store/song_audio_repository.dart)                  │
│ ─ writeRecording(bytes, format) → assetId                      │
│ ─ importExternalFile(path) → assetId (copies into app storage) │
│ ─ delete(assetId)                                              │
│ ─ resolvePath(assetId) → File                                  │
│ ─ computePeaks(File, targetBins) → List<int>                   │
└────────────────────────────────────────────────────────────────┘
                          │
┌────────────────────────────────────────────────────────────────┐
│ Domain (models/song_project.dart)                              │
│ ─ AudioAsset             (durationMs, sampleRate, peaks, ...)  │
│ ─ AudioClipPattern       (1:1 link to AudioAsset)              │
│ ─ SongTrackType.audio    (new enum case)                       │
│ ─ SongPatternType.audio  (new enum case)                       │
└────────────────────────────────────────────────────────────────┘
```

**Information flow on record:**

1. User taps empty audio lane → bottom sheet → "Record audio"
2. `SongAudioRecorderSheet` opens; user taps Record
3. `song_audio_recorder_store` triggers count-in via `song_playback_store`, then starts mic capture via `record` package and starts project playback (mute the target track during capture)
4. User taps Stop → recorder finalises WAV file via the repository, computes peaks, exposes a `PendingTake { assetId, durationMs, peaks }` to the sheet
5. Preview UI plays the take (over silence) via `audioplayers`
6. On "Confirm" → store calls `song_project_store.addAudioClip(trackId, startTick, asset)`, sheet closes
7. On "Discard" / "Retry" → repository deletes the orphan file

**Information flow on import:**

1. User taps empty audio lane → bottom sheet → "Import audio file"
2. `file_picker` returns a path (or bytes on web)
3. Repository copies the file into `appDocs/song_audio/`, probes duration + sample rate, computes peaks
4. New `AudioAsset` + `AudioClipPattern` + `SongClipInstance` committed atomically

## Data Model

Added to `lib/models/song_project.dart`. All immutable, with `copyWith` / `toJson` / `fromJson` matching existing types.

```dart
enum SongTrackType { note, drum, audio }      // + audio
enum SongPatternType { note, drum, audio }    // + audio

class AudioAsset {
  final String id;              // uuid; matches the filename stem
  final int durationMs;         // source of truth for clip length in time
  final int sampleRate;         // 44100 for record, original for import
  final int channels;           // 1 for record, 1 or 2 for import
  final String format;          // 'wav' | 'mp3' | 'm4a'
  final List<int> peaks;        // 0..255, length ~ 200..800
  final String sourceLabel;     // 'Recording' or original filename
}

class AudioClipPattern {
  final String id;              // referenced by SongClipInstance.patternId
  final String name;            // user-editable label
  final String assetId;         // links to AudioAsset
}

class SongProject {
  // ... existing fields ...
  final List<AudioAsset> audioAssets;
  final List<AudioClipPattern> audioPatterns;
}
```

`SongClipInstance` does not change shape — its existing `patternId` + `patternType: SongPatternType.audio` is enough.

**Derived (not persisted)** in `lib/schema/rules/song_audio_rules.dart`:

```dart
int audioClipLengthTicks(AudioAsset asset, SongProjectConfig config) {
  final ticksPerBeat = config.timeSignature.ticksPerBeat;
  final beatsPerSecond = config.tempo / 60.0;
  return ((asset.durationMs / 1000.0) * beatsPerSecond * ticksPerBeat).round();
}
```

When the project tempo changes, every audio clip's grid length is recomputed on the fly. The real audio duration never changes.

**Invariants**

- Each `AudioClipPattern` is referenced by exactly one `SongClipInstance`. Patterns are not reused.
- Each `AudioAsset` is referenced by exactly one `AudioClipPattern`.
- `SongClipInstance.patternType == audio` ⟺ track type is `audio`.
- `removeAudioClip(clipId)` deletes, in order: the clip instance, the pattern, the asset, and the file on disk. Wrapped in a single store action.

**Migration**

New fields default to `[]` when absent in legacy save JSON. No version bump required; the JSON schema is forward-compatible. Loading a project with audio clips on a build that does not know about audio is a future risk — addressed by adding a soft warning, not blocking the load. Out of scope for v1 since we control both writers and readers.

## Storage Layer

`lib/store/song_audio_repository.dart` — a small file-system façade.

**Filesystem layout**

```
appDocs/
  song_audio/
    <assetId>.wav    // recordings, always WAV
    <assetId>.mp3    // imports keep original ext
    <assetId>.m4a
```

There is no project-scoped subfolder in v1 because the active save session loads at most one project at a time. Orphan cleanup is per-asset, not per-project. A future spec can introduce project folders if multi-project caching becomes needed.

**Public API**

```dart
class SongAudioRepository {
  Future<AudioAsset> writeRecording(Uint8List wavBytes);
  Future<AudioAsset> importExternalFile(String externalPath);
  Future<void> delete(String assetId);
  Future<File> resolvePath(String assetId, String format);
  Future<List<int>> computePeaks(File file, {int targetBins = 400});
}
```

- `writeRecording` writes the WAV bytes, parses the WAV header for `durationMs`/`sampleRate`/`channels`, computes peaks, returns a populated `AudioAsset`.
- `importExternalFile` copies the file into `song_audio/`, probes metadata with `audioplayers` (it exposes `getDuration`), computes peaks. For non-WAV formats peak computation decodes via PCM samples extracted by a small native helper or, for v1, by playing once and sampling amplitudes — see Risk #1.
- `delete` removes the file; missing-file is not an error.
- `resolvePath` is the only way the playback sink locates the audio file at play time.
- `computePeaks` returns a normalised `List<int>` of length `targetBins`.

**Orphan handling**

- Discarded takes: the recorder store calls `delete(pendingAsset.id)` on Retry/Discard.
- Deleted clips: `song_project_store.removeAudioClip` calls `delete`.
- Crash recovery: every time a `SongProject` finishes loading, the repository scans `song_audio/` and removes any file whose `assetId` is not referenced by the just-loaded project. Cheap: directory listing + set diff. This subsumes the separate `checkIntegrity` step mentioned under Persistence: integrity (missing file → broken clip) and orphan cleanup (extra file → delete) happen in one pass.

**Web fallback**

On `kIsWeb`, the repository switches to an in-memory `Map<String, Uint8List>` keyed by `assetId`. Files do not persist across reloads, but the app save still serialises (a future spec will inline base64 on web — out of scope here). Record is disabled on web; import works via the standard file picker.

## Recorder State Machine

`lib/store/song_audio_recorder_store.dart` — a Riverpod `NotifierProvider` exposing `SongAudioRecorderState`.

```
                 ┌─────────────┐
                 │    idle     │
                 └──────┬──────┘
                        │ start(trackId, startTick)
                        ▼
                 ┌─────────────┐
                 │   countIn   │  1 measure metronome only
                 └──────┬──────┘
                        │ countdown done
                        ▼
                 ┌─────────────┐
                 │  recording  │  mic open + project plays
                 └──────┬──────┘
                        │ stop()
                        ▼
                 ┌─────────────┐
                 │ finalising  │  flush WAV, compute peaks
                 └──────┬──────┘
                        │ asset ready
                        ▼
                 ┌─────────────┐
                 │   preview   │  tap play to audition the take
                 └─┬───────┬───┘
       confirm()   │       │   discard() / retry()
                   ▼       ▼
            commit clip   delete asset
                   │       │
                   └───┬───┘
                       ▼
                 ┌─────────────┐
                 │    idle     │
                 └─────────────┘
```

**State**

```dart
class SongAudioRecorderState {
  final SongAudioRecorderStatus status;   // idle, countIn, recording, finalising, preview, error
  final String? targetTrackId;
  final int? startTick;
  final int elapsedMs;
  final AudioAsset? pendingAsset;
  final String? errorMessage;
}
```

**Behavioural rules**

- The target audio track is auto-muted during recording, so any existing clips on that same track do not bleed back into the mic through the speakers. The original mute state is restored on stop.
- Project playback runs from `startTick` exactly; the count-in is in front of `startTick`, not inside it.
- `stop()` is a no-op when not in `recording`. `start()` is rejected unless `idle` or `error`.
- Errors during mic access (permission denied, device busy) transition to `error` with a human-readable `errorMessage`. The sheet shows the message with a "Try again" button.
- The store does not own the recorder's hardware lifetime past `finalising`. After commit/discard, the `record` instance is released.

**Permissions**

- `Permission.microphone` requested by the store on first `start()`.
- Permanently denied: show a single sheet with copy and a "Open settings" CTA via `permission_handler` (new dependency, ~lightweight).
- Web: not invoked, sheet only shows "Import audio file".

## Import Flow

`file_picker` package handles selection (new dependency, widely used, supports iOS / Android / macOS / Windows / Web).

- Allowed extensions: `wav`, `mp3`, `m4a`.
- Max size guard: 50 MB per file. Above → user-facing error in the sheet, no crash.
- Probing: WAV parsed inline; MP3/M4A duration via `audioplayers.getDuration` (the player loads, reads metadata, never plays).
- On success: an `AudioAsset` and `AudioClipPattern` are committed atomically alongside a `SongClipInstance` at the chosen `startTick`. The clip name defaults to the original filename (without extension), editable later.

## Clip Rendering

`SongArrangerTimeline` already paints note clips and drum clips via shared geometry helpers. We add one branch.

`AudioWaveformPainter` (Custom Painter):

- Input: `List<int> peaks` (0..255), clip rect, accent color (mid-blue by default to distinguish from note green / drum orange).
- Renders a mirrored amplitude envelope: for bin *i*, draws a vertical bar from `centerY - h/2` to `centerY + h/2` where `h = (peak[i] / 255) * rectHeight * 0.9`.
- When the clip is narrower than `peaks.length`, downsamples by taking max-per-pixel-column. When wider, repeats nearest neighbour.

`AudioClipBody`:

- Top-left label: clip name + duration (`m:ss`).
- Center: waveform painter.
- Right edge: a small rounded `wav` / `mp3` / `m4a` chip — disambiguates recorded vs imported at a glance.

Drag, select, delete, rename use the same gesture surfaces as note/drum clips.

## Playback Integration

`song_playback_store.dart` currently dispatches to two sinks (notes via `NotePlayer`, drums via drum voices). Add a third: **`AudioClipSink`**.

**Scheduling model**

- Tick zero of project playback corresponds to `t = 0` on the transport clock.
- For each audio clip on a non-muted (or soloed) audio track:
  - Compute its `startMs = startTick → ms` using current tempo.
  - When the transport crosses `startMs`, the sink starts an `AudioPlayer` for that clip's file, seeked to `0` (whole-clip playback).
  - If the user starts the song mid-clip, sink computes the in-clip offset (`transportMs - startMs`) and seeks the player there before play.
  - When the transport reaches `startMs + asset.durationMs`, the sink stops the player.

**Concurrency**

- One `AudioPlayer` instance per simultaneously sounding clip; reused via a small pool (most songs have at most 4-8 audio clips overlapping).
- `audioplayers` already runs on a native audio thread; no extra isolate needed.

**Tempo changes**

- Already-playing audio clips do not "stretch" — they continue at native rate until natural end. Future tempo changes shift the *next* clip start tick but do not warp running playback. This matches Decision 3.

**Stop / scrub**

- `transport.stop()` stops all sinks. `transport.seek(tick)` cancels all in-flight audio players, then re-evaluates which clips should be playing at the new position with their correct in-clip offsets.

**Mute / solo**

- Reuses existing rules: any soloed track means non-soloed tracks are silent. Mute hides the sink output. Identical to note/drum.

## Persistence

`SongProjectSnapshot` (`models/save_system.dart`) wraps `SongProject` for the shared save browser. New fields ride along automatically through `SongProject.toJson` / `fromJson`.

**What's persisted in the save**

- `audioAssets` (metadata + peaks, no audio bytes)
- `audioPatterns`
- New `SongClipInstance`s with `patternType: audio`

**What's not persisted in the save**

- The WAV / MP3 / M4A bytes — they live on disk under `song_audio/`. The save references them by `assetId`.

**Implication**: a save is portable only on the same device. Cross-device portability needs a "bundle export" feature (zip with the JSON + audio files). Explicitly deferred.

**Load behaviour**

- After deserialising, the project store invokes the repository's load-time scan (see Storage Layer → Orphan handling). Assets whose files are missing mark their clips as "broken" — clip renders with a red diagonal stripe and is silent during playback. The user can delete the clip or re-record. No crash.

## Web Fallback

- Record: disabled. The bottom-sheet "Record audio" entry is hidden on `kIsWeb`, matching the existing hum-to-MIDI pattern.
- Import: enabled. `file_picker` returns bytes (not a path) on web; repository keeps them in memory.
- Playback: `audioplayers` on web uses `<audio>` elements — same API, slightly higher latency. Acceptable for v1 (web is not the primary target).
- Save/load: works, but audio bytes are lost across reloads. UI shows a banner on Song tab on web explaining this.

## New Dependencies

- `file_picker` (≥ 8.x) — system file picker for import, all platforms.
- `permission_handler` (≥ 11.x) — uniform microphone permission UX, especially the "permanently denied → open settings" flow on Android.

Both are widely maintained, MIT-licensed, and small. Added to `pubspec.yaml` alongside the existing `record` and `audioplayers`.

## Risk Register

1. **Peak computation cost for compressed imports.** Decoding a 5-minute MP3 to compute peaks is non-trivial in pure Dart. v1 mitigation: cap import to 50 MB and run peak computation off the UI thread via `compute()`. If unacceptable on cold devices, fallback to a simpler "loudness window" using `audioplayers` polling during a silent pre-roll. Re-evaluated after first device tests.
2. **Mic permission UX divergence.** iOS prompts once and never again; Android can permanently deny. `permission_handler` smooths this but adds a dependency. Acceptable for the value it adds.
3. **Crash mid-recording.** Partial WAV file orphaned on disk. Mitigated by the start-up scan that removes assets not referenced by the loaded project.
4. **Audio + note playback drift.** `audioplayers` runs on native threads and does not share a clock with the in-app transport tick. Drift over long songs is possible. v1: accept drift; song lengths are typically under 4 minutes. Future spec can integrate a more rigid scheduling layer.
5. **`file_picker` on macOS / Linux.** Plugin is reliable on mobile and web; desktop support is incomplete on Linux. Documented as a known gap, not a blocker.

## Testing Strategy

**Unit (`test/`)**

- `models/song_project_test.dart` — JSON round-trip for new `AudioAsset` / `AudioClipPattern`; default empty lists for legacy JSON.
- `schema/rules/song_audio_rules_test.dart` — `audioClipLengthTicks` math against known cases (60 BPM, 120 BPM, different time signatures).
- `store/song_audio_repository_test.dart` — with an `IOOverrides`-stubbed filesystem: write/delete/orphan-scan behaviour. Peak computation on a synthetic 1 kHz sine wave WAV.
- `store/song_audio_recorder_store_test.dart` — full state machine driven by a fake `Recorder` + fake `Clock`. Asserts auto-mute on start, asset commit on confirm, file deletion on discard, error transitions on permission denied.
- `store/song_playback_store_test.dart` — scheduling correctness for audio clips: starts at `startMs`, stops at `startMs + durationMs`, scrub re-evaluates correctly.

**Widget (`test/`)**

- `features/song/song_arranger_timeline_test.dart` — audio clip renders waveform painter, drag changes `startTick`.
- `features/song/song_audio_recorder_sheet_test.dart` — count-in → recording → preview → confirm flow with a fake recorder store.

**Manual / device**

- iOS + Android: record-confirm-play-back-in-mix loop; import each format; web import smoke; web save/load loses audio gracefully; permission denial recovery.

## Future Work (out of scope for v1)

- Trim handles (offset + length without re-encoding)
- Per-clip volume / pan / fade in-out
- Time-stretch and pitch-shift
- Multiple takes per session with a comp lane
- Audio bundle export (zip with audio + JSON)
- Effects rack
- Sidechain ducking from note onsets
- Live mic monitoring toggle with headphone detection
