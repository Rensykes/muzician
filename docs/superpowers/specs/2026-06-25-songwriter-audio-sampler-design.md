# Songwriter Audio Sampler Design

Date: 2026-06-25
Status: Draft approved in chat, written for repo review
Scope: A Koala-Sampler-style audio feature inside the Songwriter (writer page) — record or import audio, place it on the bar grid as a new `audio` lane, trim it, fit it to a whole number of bars by looping / one-shot / pitch-preserving time-stretch, play it back in sync with the transport, and annotate its chords with beat-quantized in-clip segments (harmony picks or save references).

## Goal

Give the Songwriter a fourth lane kind — **audio** — so a user can:

1. **Capture** an idea (sung, hummed, played) with a count-in over the section, or **import** a WAV / MP3 / M4A.
2. **Place** the recording on the bar grid of a section as a clip spanning 1..(section − 1) bars.
3. **Adapt** a clip whose natural length differs from its bar span via a per-clip **fit mode**:
   - **loop** — repeat the trimmed region across the span at native pitch;
   - **one-shot** — play once from the bar start, silence the remainder;
   - **stretch** — pitch-preserving time-stretch so the trimmed region exactly fills the span.
4. **Trim** the used region of the source non-destructively.
5. **Mark chords** on the recording with **beat-quantized in-clip segments**, each a harmony chord (chord-wheel pick) or a save reference. Segments are silent metadata that drive chord / Roman-numeral display, scale degrees, and library-match — the recording itself remains the sound.

This is built **in one ship**, structured internally as milestones M1–M8.

## Problem Statement

The Songwriter today is a section → lane → block arrangement map whose lanes are `harmony`, `save`, and `drum`. Every lane sounds through the internal synth or drum voices. There is no way to anchor a *recorded* idea to the bar grid, nor to fit a free-length recording to a musical number of bars, nor to annotate where its chords change.

The Song workspace already proved the audio capture + playback pipeline (`record` → WAV, `audioplayers` playback, `SongAudioRepository`, `AudioAsset`, `SongAudioClipSink`, waveform peaks). But that feature explicitly deferred **trim, time-stretch, and pitch-shift** as non-goals ("native length, no DSP stretch"). The Songwriter needs exactly those, plus a chord-annotation layer the Song feature never had.

The drum lane is the structural precedent: a lane kind whose blocks reference a project-level content list (`SongBlock.patternId` → `SongwriterProjectSnapshot.drumPatterns`). The audio lane mirrors it (`SongBlock.audioClipId` → `SongwriterProjectSnapshot.audioClips`).

## Decisions Log

Locked during brainstorming:

1. **Stretch engine** — pitch-preserving, **pre-rendered offline** (computed once when length/trim/mode/tempo changes, stored as a derived asset). Pure-Dart WSOLA, no native DSP plugin.
2. **Fit mode is per-clip and user-chosen** — `loop`, `oneShot`, or `stretch`.
3. **Chord marking = in-clip segments**, sub-bar, **beat-quantized**.
4. **Segments are silent** — metadata only; the recording is the sound. They feed display, Roman numerals, scale degrees, and library-match (`selectedNotes`).
5. **Clip span** = any whole number of bars, 1 up to (section length − 1).
6. **Ship all at once** — a single spec, milestoned M1–M8.
7. **Reuse the Song audio infra** (`AudioAsset`, `SongAudioRepository`, `SongAudioClipSink` / `AudioPlayersClipSink`, recorder driver, `wav_writer`); add Songwriter-specific model, stretch DSP, recorder store, transport scheduling, and UI. No refactor of the working Song audio feature.
8. **File isolation** — Songwriter audio files live in a dedicated `songwriter_audio/` directory with their own orphan reconcile scope, so neither feature's reconcile can delete the other's files.

## Non-Goals

- Per-clip volume / pan / fade / EQ / effects.
- Pitch-shift independent of time (repitch), or real-time (live) stretch that warps already-playing audio.
- Multiple takes / comp lanes per recording session.
- Live mic monitoring through the mix.
- Audio bundle export (zip JSON + audio) / cross-device portability.
- Sub-beat (free-ms) segment placement — segments snap to beats.
- Segments producing synth sound (they are silent by Decision 4).

## Architecture Overview

Reuse-first. New code is Songwriter-specific; shared code is consumed unchanged except for two small, additive extensions (a `loop` flag on the clip sink, a configurable subfolder on the repository).

```
┌──────────────────────────────────────────────────────────────────────┐
│ UI (features/songwriter)                                              │
│ ─ songwriter_screen_sheet.dart   "Add audio lane" + _AudioLaneRow     │
│ ─ songwriter_audio_clip_sheet.dart   clip editor (trim/fit/segments)  │
│ ─ songwriter_audio_recorder_sheet.dart   count-in → record → preview  │
│ ─ AudioClipTile / waveform thumbnail (reuse Song's peaks painter)     │
└──────────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────────┐
│ Stores (store/)                                                       │
│ ─ songwriter_store            (+ audio lane / clip / segment ops)     │
│ ─ songwriter_audio_recorder_store   (record state machine)            │
│ ─ songwriter_playback_store   (+ audio clip scheduling)               │
└──────────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────────┐
│ Rules (schema/rules/)                                                 │
│ ─ songwriter_audio_rules.dart   flattenAudioClips, fit/length math    │
│ ─ audio_stretch_rules.dart      pure WSOLA (stretchInt16)             │
│ ─ songwriter_rules.dart         (+ makeAudioLane / makeAudioClip)     │
└──────────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────────┐
│ Repository / Domain                                                   │
│ ─ SongAudioRepository (reused; + subdir param; + writeStretched)      │
│ ─ AudioAsset (reused, from models/song_project.dart)                  │
│ ─ models/songwriter.dart: SongLaneKind.audio, AudioClip, ChordSegment │
└──────────────────────────────────────────────────────────────────────┘
```

## Data Model (`lib/models/songwriter.dart`)

All immutable with `copyWith` / `toJson` / `fromJson`, matching existing types. `AudioAsset` is reused from `lib/models/song_project.dart` (already imported here for `DrumPattern`).

```dart
enum SongLaneKind { harmony, save, drum, audio }   // + audio
enum AudioFitMode { loop, oneShot, stretch }

// SongBlock gains one field (placement only; mirrors drum's patternId):
class SongBlock {
  // ... existing ...
  final String? audioClipId;        // → SongwriterProjectSnapshot.audioClips
  // copyWith adds: String? audioClipId, bool clearAudioClipId = false
}

// New content type (heavy fields live here, like DrumPattern):
class AudioClip {
  final String id;
  final String assetId;             // → audioAssets[] (reused AudioAsset)
  final int trimStartMs;            // non-destructive used region start
  final int trimEndMs;              // used region end (== asset.durationMs by default)
  final AudioFitMode fitMode;       // loop | oneShot | stretch
  final String? stretchedAssetId;   // derived WSOLA asset; non-null only for stretch
  final List<ChordSegment> segments;
}

// New silent annotation, beat-quantized in clip-local tick space:
class ChordSegment {
  final String id;
  final int startTick;              // relative to clip start, multiple of ticksPerBeat
  final int spanTicks;              // multiple of ticksPerBeat
  // one of: a harmony pick ...
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;
  // ... or a save reference:
  final String? saveId;
}

class SongwriterProjectSnapshot {
  // ... existing (config, sections, drumPatterns) ...
  final List<AudioAsset> audioAssets;
  final List<AudioClip>  audioClips;
}
```

**Resolution / invariants**

- A block resolves to a clip via `audioClipId` (broken if missing → tile shows a red stripe, silent).
- An `AudioClip` resolves to a playable file: `stretchedAssetId` when `fitMode == stretch` and the derived asset exists; else `assetId`. Each is one `AudioAsset` in `audioAssets`.
- Each `AudioClip` is referenced by exactly one audio `SongBlock` (clips are not reused; mirrors drum pattern 1:1 with its block).
- `segments` live in clip-local ticks within `[0, spanBars * measureTicks)`; on span shrink, segments fully outside the new span are dropped, a segment straddling the edge is clamped.
- `SongwriterProjectSnapshot.selectedNotes` additionally unions each segment's `chordNotes` (and resolved save notes), so analysis / library-match see the recording's harmony.

**Migration** — new fields default to `[]` / `null` in legacy JSON. No version bump; forward-compatible.

## Stretch Engine (`lib/schema/rules/audio_stretch_rules.dart`)

Pure, dependency-free DSP so it is unit-testable and runs anywhere (incl. web).

```dart
/// Pitch-preserving time-stretch via WSOLA (waveform-similarity overlap-add).
/// Mono int16 in, mono int16 out at the same sample rate, length ~ targetMs.
Int16List stretchInt16(Int16List samples, int sampleRate, int targetMs);
```

- WSOLA: fixed analysis hop, search window for the best-correlated overlap, Hann cross-fade. Chosen over a phase vocoder for simplicity and acceptable mono "sketch" quality.
- Runs **off the UI thread** via `compute()` (top-level entry, plain args).
- **Length cap**: source region ≤ 30 s (guarded in UI); longer → disable stretch mode with a hint.

**Render pipeline** (`SongAudioRepository.writeStretched`, additive):

1. Read the source asset's int16 samples for the trimmed region (`_extractInt16Samples` already exists; expose a trimmed read).
2. `targetMs = spanBars * config.beatsPerBar * 60000 / config.tempo`.
3. `stretchInt16(...)` → `wav_writer` → new WAV file → derived `AudioAsset` (`sourceLabel: 'Stretched'`).
4. Store id on the clip as `stretchedAssetId`; delete any previous derived file.

**Re-render triggers** (stretch clips only): change of `spanBars`, `trimStartMs/EndMs`, `fitMode → stretch`, or **tempo**. Debounced (~300 ms); tile shows a "processing" badge; loop / one-shot clips never re-render (native pitch, grid length only). On load, a stretch clip whose derived file is missing/stale re-renders lazily (before first play).

## Playback Integration (`lib/store/songwriter_playback_store.dart`)

Add audio scheduling beside the existing note / drum / metronome sinks, reusing `SongAudioClipSink` (interface in `song_playback_store.dart`) and `AudioPlayersClipSink`.

- **Sink extension (additive)**: `startClip({asset, offsetMs, volume, bool loop = false})` — when `loop`, set `ReleaseMode.loop`; the transport still issues an explicit `stopClip` at span end.
- **New rule** `flattenAudioClips(project) → List<PlacedAudioClip>` where
  `PlacedAudioClip { String playAssetId, int startTick, int endTick, AudioFitMode fitMode, int sourceOffsetMs }`,
  expanded across section repeats exactly like harmony/drum blocks (via `expandSections` + `tileLaneBlocks`), `endTick` clipped to the section.
- **Tick loop**: at `startTick` → `startClip(offset: sourceOffsetMs, loop: fitMode == loop)`; at `endTick` → `stopClip`. Scrub re-evaluates which clips should sound and seeks them, mirroring Song's behavior.
- Per fit mode: **oneShot** plays once from bar start (silent after natural end); **loop** repeats until `endTick`; **stretch** plays the derived asset once (its duration ≈ span).
- `stopPlayback` / transport stop → `stopAll`.

## Recorder & Import (`lib/store/songwriter_audio_recorder_store.dart`)

Mirror the Song recorder state machine (`idle → countIn → recording → finalising → ready`) but wire count-in and background playback to the **Songwriter** transport, and target an audio **lane** + **startBar** (not a Song track).

- Reuse `SongAudioRecorderDriver` (the `record` wrapper) and `SongAudioRepository.writeRecording`.
- Count-in = one section measure of metronome blips; background = `songwriterPlaybackProvider.startPlayback(startTick: barStart)`.
- On confirm: create `AudioAsset` (audioAssets), `AudioClip` (default `fitMode: loop`, full trim, `spanBars = clamp(round(asset bars), 1, section − 1)`), and an audio `SongBlock` at the chosen `startBar` — atomically.
- **Import**: `file_picker` → `SongAudioRepository.importExternalFile` → same atomic commit. Clip name defaults to filename.
- **Web**: record entry hidden (parity with hum-to-MIDI); import enabled; files non-persistent across reload (existing caveat).

## Sheet UI (`lib/features/songwriter/songwriter_screen_sheet.dart`)

- **"Add audio lane"** menu action beside "Add drum lane" (~line 601), creating a `SongLaneKind.audio` lane.
- **`_AudioLaneRow`** (mirror `_DrumLaneRow`, ~line 1569): renders each audio block as a clip tile across its bars — waveform thumbnail (reuse Song's `peaks` painter), a fit-mode glyph (∞ loop / ▷ one-shot / ↔ stretch), a "processing" badge while a stretch re-renders, and segment chord labels under the waveform.
- Tap a tile → **clip editor sheet**. Empty-lane tap → record / import bottom sheet (the recorder entry point).
- Move / resize on the bar grid reuse the existing block gesture surfaces; resize changes `spanBars` (and re-renders stretch clips).

## Clip Editor Sheet (`lib/features/songwriter/songwriter_audio_clip_sheet.dart`)

The Koala-like screen.

```
┌───────────────────────────────────────────────────┐
│  ▷ audition                 [ loop | 1-shot | ↔ ]  │
│  ┌───────────────────────────────────────────────┐ │
│  │ |◀   ~~~~~~~~~~ waveform ~~~~~~~~~~   ▶|        │ │ ← trim handles
│  │   C        G          Am          F           │ │ ← segment row (beat grid)
│  └───────────────────────────────────────────────┘ │
│  span:  ◀  2 bars  ▶   (1 .. section − 1)          │
│  tap a beat → add segment → chord wheel / save     │
└───────────────────────────────────────────────────┘
```

- **Trim handles** set `trimStartMs / trimEndMs` over the waveform.
- **Span stepper** sets `spanBars` (1..section−1).
- **Fit toggle** sets `fitMode`; switching to stretch (or any change while in stretch) schedules a re-render.
- **Segment row** is a beat grid laid over the waveform; tap a beat cell → add/edit a `ChordSegment` via the existing chord-wheel picker or a save picker; drag a segment edge to change `spanTicks` (beat-snapped). Roman numerals render when diatonic (reuse `romanNumeralFor`), recomputed on `setKey`.
- **Audition** plays the clip as it will sound (current fit mode), independent of the transport.

## Persistence, Files, Web

- New snapshot fields ride `SongwriterProjectSnapshot.toJson / fromJson`; default empty. Save remains a `SaveEntry` via the shared browser.
- **Files**: `SongAudioRepository` gains a `subdir` constructor param (default `'song_audio'`); a `songwriterAudioRepositoryProvider` uses `'songwriter_audio'`. Source recordings/imports and derived stretched WAVs both live there.
- **Orphan reconcile** scopes to the Songwriter subfolder; the referenced set = every clip's `assetId` ∪ `stretchedAssetId`. The Song feature reconciles its own `song_audio/` independently — no cross-feature deletion (Decision 8).
- Saves are device-local (audio bytes on disk, referenced by id) — same caveat as Song. Web keeps bytes in memory; record disabled; a banner notes non-persistence.

## Milestones (one ship, built in order)

- **M1 — Model + persistence.** `SongLaneKind.audio`, `AudioFitMode`, `AudioClip`, `ChordSegment`, snapshot lists, `SongBlock.audioClipId`, JSON round-trip, `selectedNotes` union, `makeAudioLane/Clip/Segment` factories, repo `subdir` param + scoped reconcile. Tests: model round-trip, reconcile isolation.
- **M2 — Record + import.** `songwriter_audio_recorder_store`, recorder sheet, atomic commit, web guard. Tests: recorder state machine with fake driver/clock.
- **M3 — Sheet lane.** "Add audio lane", `_AudioLaneRow`, clip tile + waveform thumbnail, place/move/resize. Tests: lane renders, resize changes `spanBars`.
- **M4 — Clip editor (trim + fit + audition).** Editor sheet with trim handles, span stepper, fit toggle, audition. Tests: trim/span edits mutate the clip; audition path.
- **M5 — Transport playback.** `flattenAudioClips`, audio scheduling in `songwriter_playback_store`, `startClip` `loop` flag. Tests: scheduling for loop / one-shot start+stop ticks; scrub re-eval.
- **M6 — Stretch DSP.** `audio_stretch_rules.stretchInt16`, `writeStretched`, stretch fit mode, debounced re-render triggers (span/trim/mode/tempo), processing badge, length cap. Tests: stretch length math on a synthetic sine; trigger matrix.
- **M7 — Segments.** Beat-grid segment editor, chord-wheel / save assignment, Roman numerals, tile labels, `selectedNotes`/library-match feed. Tests: beat-quantization, span-shrink clamp/drop, Roman numeral in key.
- **M8 — Polish + verification.** `dart format`, `flutter analyze`, full `flutter test`; manual device pass (record→fit→stretch→segment→play); compact + wide viewport check.

## Risk Register

1. **WSOLA quality / CPU in pure Dart.** Mono sketch quality only; bound by the 30 s cap and `compute()`. Re-evaluate after device tests; a native plugin is a future option.
2. **Tempo change re-renders all stretch clips.** A batch stall if many exist. Mitigation: lazy (render-on-next-play) + background queue + per-tile processing badge; loop/one-shot are unaffected.
3. **`audioplayers` loop / stop precision.** Native-thread playback does not share the transport clock; minor drift over long sections. Accepted for sketching (same as Song).
4. **Shared file directory.** Reconcile could delete the other feature's files. Mitigated by the dedicated `songwriter_audio/` subfolder + independent reconcile scope (Decision 8).
5. **Scope.** Large for one spec. Mitigated by the M1–M8 milestone order; each milestone is independently buildable and testable.

## Testing Strategy

- **Unit (`test/schema/rules`, `test/models`, `test/store`)**: model JSON round-trip + legacy defaults; `stretchInt16` length on a synthetic 1 kHz sine; `flattenAudioClips` tick math across section repeats; fit-mode length/offset math; segment beat-quantization + span-shrink clamping; reconcile isolation between subfolders; recorder state machine with fakes.
- **Widget (`test/features/songwriter`)**: audio lane renders a clip tile + waveform; resize changes `spanBars`; clip editor trim/span/fit edits; segment add via chord-wheel; processing badge during a stubbed stretch.
- **Manual / device**: iOS + Android record → trim → each fit mode (esp. stretch pitch fidelity) → add segments → play in the transport; import each format; web import + record-hidden + non-persistence banner.

## Future Work (out of scope)

- Native real-time stretch (SoundTouch / Rubber Band via FFI) for live tempo follow + higher fidelity.
- Per-clip volume / fade / pan.
- Free-ms (non-beat) segment placement and segment-driven synth doubling toggle.
- Audio bundle export for cross-device portability.
- Multiple takes / comping.
- Decoded peaks for MP3 / M4A imports (currently flat-band until decoded).
