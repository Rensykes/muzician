# Songwriter Audio Slice & Scatter Design

Date: 2026-06-28
Status: Draft approved in chat, written for repo review
Scope: Make the Songwriter audio clip editor DAW-friendly by letting a user **slice** one recording at cut markers (auto-transient seed + manual add/move/delete) and **scatter** the slices onto consecutive bars as independent clips, each time-stretched to its bar so a timing-imperfect take locks to the grid.

## Goal

A user records a phrase that is not metronomically perfect — it rushes or drags. Today the only options are trim (one region) and a single whole-clip fit. There is no way to chop the take into its musical bars and align each bar to the grid.

This feature adds, inside the existing clip editor:

1. **Detect** transient onsets in the recording (`detectOnsets`, off-thread), seeding cut markers, with a **sensitivity** control to get more / fewer cuts.
2. **Adjust** cuts manually — add, drag, or delete a marker on the waveform — so each cut lands where a bar boundary should actually fall (the real downbeat, not the click). Drag is free with an optional snap-to-detected-onset.
3. **Scatter** the slices onto the bar grid: each consecutive slice becomes its own audio clip + block, placed on consecutive bars from the source block's start bar, **default fit `stretch`** so each slice is time-stretched (pitch-preserving) to exactly fill its bar. An imperfect 8-bar take becomes 8 bars locked to the grid.

This is the Ableton "warp to grid" result achieved by reusing the existing per-block clip model (each bar = one clip) instead of building a piecewise-warp engine inside one clip.

## Problem Statement

The Songwriter audio sampler (shipped, `2026-06-25-songwriter-audio-sampler-design.md`) models one recording as one `AudioClip` (trim + fit + chord segments) bound 1:1 to one audio `SongBlock` spanning N bars. Fit modes (`loop` / `oneShot` / `stretch`) already adapt a whole clip to its span, and a pure-Dart WSOLA stretch engine (`stretchInt16`) already exists. What is missing is any way to:

- divide a recording into multiple bar-length pieces, and
- correct internal timing by aligning each piece to a bar.

The shipped model makes this cheap: a "slice" is just another `AudioClip` with a narrower `trimStartMs/EndMs` over the **same** `AudioAsset`. Scattering N slices = creating N clip+block pairs and removing the source pair. No new content type, no new transport path, no new fit engine — onset detection and a marker UI are the only genuinely new pieces.

## Decisions Log

Locked during brainstorming (this round):

1. **Approach = slice & scatter**, not an in-clip slice grid and not a pad/step sequencer. Each slice is a normal `AudioClip` + audio `SongBlock`; reuse the existing model, transport, fit modes, and stretch DSP.
2. **Slicing = auto-transient + manual markers.** Onset detection seeds cuts; the user adds / drags / deletes markers to place each cut at the intended bar boundary. Manual is required because takes are timing-imperfect — the whole point.
3. **Scatter default fit = `stretch`.** Each slice fills exactly one bar, time-stretched to correct timing. Per-clip fit stays switchable (`loop` / `oneShot`) afterward.
4. **Scatter replaces the source.** The source block+clip are removed; the asset persists (shared by the slice clips via trim regions).
5. **Reuse existing infra** — `AudioClip`, `SongBlock.audioClipId`, `SongAudioRepository.readInt16Samples` / `writeStretched`, `audio_stretch_rules`, the stretch controller's `compute()` render path. Onset detection mirrors the stretch render's off-thread pattern.
6. **WAV-only detection.** Onset detection needs int16 samples; only WAV assets carry them (mp3/m4a are undecoded, empty peaks — existing caveat). Slice mode is unavailable (greyed, with a hint) for sample-less assets.
7. **No silent truncation.** When slices exceed available bars or hit an occupied bar, place what fits and surface a snackbar naming how many were dropped.

## Non-Goals

- **Per-clip pitch shift (±semitones).** Deferred to a follow-up spec (resample + WSOLA repitch). Listed in Future Work.
- Piecewise warp markers inside a single clip (continuous time-warp) — slice & scatter approximates this at bar granularity.
- Sub-bar slice placement (slices land on whole bars; default span 1 bar).
- Onset detection for mp3/m4a (needs a decoder; out of scope, same as the sampler spec).
- Choke groups, pads, per-pad FX, a step sequencer (the pad-model alternative was rejected).
- Re-detecting against an already-scattered set (scatter is one-way; re-slice from the source clip before scattering).

## Architecture Overview

Reuse-first. The only new files are an onset-detection rule and a slice-marker overlay/controls in the editor; everything else is additive to existing files.

```
┌──────────────────────────────────────────────────────────────────────┐
│ UI (features/songwriter)                                              │
│ ─ songwriter_audio_clip_sheet.dart   + Slice mode: marker overlay,    │
│     sensitivity slider, add/drag/delete markers, "Scatter to bars"    │
│ ─ songwriter_slice_markers.dart (new)  marker painter + gesture layer │
└──────────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────────┐
│ Stores (store/)                                                       │
│ ─ songwriter_store           + scatterSlices(...) atomic op           │
│ ─ songwriter_slice_controller (new)  runs detectOnsets via compute()  │
└──────────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────────┐
│ Rules (schema/rules/)                                                 │
│ ─ songwriter_slice_rules.dart (new)  detectOnsets, slicePlacements    │
└──────────────────────────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────────────────────────┐
│ Repository / Domain (reused unchanged)                                │
│ ─ SongAudioRepository.readInt16Samples / writeStretched               │
│ ─ AudioClip, SongBlock.audioClipId, AudioFitMode (existing)           │
└──────────────────────────────────────────────────────────────────────┘
```

No model changes. No new persisted fields. Slice state is **ephemeral UI state** (markers exist only while the editor is in slice mode); once scattered, the result is ordinary clips+blocks that persist through the existing snapshot.

## Onset Detection (`lib/schema/rules/songwriter_slice_rules.dart`)

Pure, dependency-free, unit-testable; runs off the UI thread via `compute()`.

```dart
/// Detected onset sample positions within [samples], strictly increasing,
/// excluding 0. Energy/flux peaks above an adaptive threshold scaled by
/// [sensitivity] in [0,1] (higher → lower threshold → more onsets).
List<int> detectOnsets(Int16List samples, int sampleRate, {double sensitivity});

/// compute() entry — plain args bundle, mirrors runStretch.
List<int> runDetectOnsets(DetectOnsetsRequest r);

/// Convert ordered cut positions (sample indexes, 0 implied as the first
/// region start) into placeable slices on consecutive bars.
/// Returns one entry per region in [0..cuts.length]; clamps the count to
/// the bars available from [startBar] to [sectionLengthBars] and reports the
/// dropped overflow count.
SlicePlan slicePlacements({
  required List<int> cutSamples,
  required int totalSamples,
  required int sampleRate,
  required int startBar,
  required int sectionLengthBars,
});

class PlacedSlice { final int trimStartMs; final int trimEndMs; final int bar; }
class SlicePlan { final List<PlacedSlice> slices; final int droppedCount; }
```

**Detection algorithm** (energy-flux, chosen for simplicity over a full spectral method):

1. Frame the signal (e.g. 1024-sample frames, 512 hop). Compute per-frame rectified energy.
2. Spectral-flux-like positive difference between adjacent frames → a novelty curve.
3. Adaptive threshold = local mean + `k(sensitivity) * local std` over a sliding window; pick novelty peaks above it, enforce a refractory gap (e.g. ≥ 50 ms) so one transient yields one onset.
4. Map peak frame → sample index. Return strictly-increasing indexes, excluding 0.

**Sensitivity** maps to the threshold multiplier `k`: sensitivity 0 → high `k` (few, only strong onsets); sensitivity 1 → low `k` (many). Monotonic: higher sensitivity never yields fewer onsets (tested).

**Inputs/limits:** operates on the trimmed region's int16 samples (`repo.readInt16Samples`, sliced to `[trimStartMs, trimEndMs)`). Mono assumed (recordings are mono). Length cap reuses the stretch cap (≤ 30 s region) to bound CPU; longer → slice disabled with a hint.

## Slice Controller (`lib/store/songwriter_slice_controller.dart`)

Mirrors `songwriter_stretch_controller`: a provider that, given a clip, reads the asset's trimmed samples and runs `compute(runDetectOnsets, ...)`, exposing `AsyncValue<List<int>>` (onset sample positions) plus a `processing` flag for a badge. Re-runs when sensitivity changes (debounced ~200 ms). The detected onsets seed the editor's marker list; manual edits live in the editor's local state, not the controller.

## Editor UI (`lib/features/songwriter/songwriter_audio_clip_sheet.dart` + `songwriter_slice_markers.dart`)

A **Slice** toggle enters slice mode (hidden/disabled when the asset has no samples). In slice mode:

- The waveform gains a **marker overlay** (`songwriter_slice_markers.dart`): vertical lines at each cut, draggable; tap empty waveform to add a marker; long-press / drag-off to delete. Markers are stored as clip-local ms in editor state. Reuses the bar-divider painter conventions already in this file.
- A **sensitivity slider** re-runs `detectOnsets`; its result *replaces* the auto markers but preserves user-added/-moved ones flagged manual (auto markers are regenerated, manual markers persist).
- A **snap toggle** (onset / off): while dragging, snap to the nearest detected onset when within a small threshold; off = free placement.
- A **slice count** readout and a **"Scatter to bars"** primary action.
- "Scatter" calls `store.scatterSlices(...)`, closes slice mode, and the section grid now shows N per-bar clips.

Marker math: a marker at clip-local ms → sample index via `sampleRate`. Region i = `[markers[i-1], markers[i])` (with implicit 0 and end). The editor passes cut sample positions to `slicePlacements`.

## Store Op (`lib/store/songwriter_store.dart`)

```dart
/// Replace the source audio block+clip with one clip+block per slice, placed
/// on consecutive bars from the source block's startBar. Each new clip shares
/// the source assetId with the slice's trim region; fit defaults to stretch.
/// Returns the number of slices actually placed (caller shows a notice if
/// fewer than requested).
int scatterSlices({
  required String sectionId,
  required String laneId,
  required String sourceBlockId,
  required List<PlacedSlice> slices,   // already clamped by slicePlacements
  AudioFitMode fitMode = AudioFitMode.stretch,
});
```

One atomic `_replaceSection`/`_replaceLane` mutation:

1. Resolve the source block + clip; capture `startBar`, `assetId`.
2. Remove the source block and its clip.
3. For each placed slice: `addAudioClip(assetId, durationMs: slice region)` with `trimStartMs/EndMs` = slice region; `addAudioBlock(... startBar: slice.bar, spanBars: 1, audioClipId: newClipId)`; clip `fitMode = stretch` → schedules the existing stretch render (one bar target) per clip.
4. Skip any bar already occupied by another lane block (overlap guard mirrors `setBlockPlacement`'s reject); stop at the first occupied bar and let the caller report the remainder via `SlicePlan.droppedCount` (computed pre-commit by `slicePlacements`, refined here if a mid-range bar is occupied).

Reuses existing `addAudioClip` / `addAudioBlock` / `removeAudioBlock` internals; this op composes them under one state write.

## Playback / Stretch (no changes)

Scattered slices are ordinary `stretch`-fit clips. The existing transport (`flattenAudioClips` / audio scheduling) plays them; the existing stretch controller renders each slice's derived WAV to its 1-bar target on creation and on tempo change. The playhead + bar-highlight work already added covers their lanes.

## Edge Cases

- **< 2 regions** (no usable cuts): "Scatter" disabled; hint "Add a cut or raise sensitivity."
- **Slices > available bars** (`sectionLengthBars - startBar`): place the first M, drop the rest; snackbar "Placed M of N slices — section ran out of bars."
- **Occupied target bar**: stop at the first occupied bar; same snackbar with the placed count.
- **Sample-less asset** (mp3/m4a, web in-memory undecoded): slice toggle disabled with "Slicing needs a recorded (WAV) clip."
- **Region > 30 s**: slice disabled with the length hint (matches stretch cap).
- **Zero-length slice** (two markers too close): enforce a minimum region (≥ one stretch frame); markers can't be dropped closer than the minimum.

## Persistence, Files, Web

- **No new persisted fields.** Markers/sensitivity are ephemeral editor state. After scatter, persistence is the existing clips/blocks/derived-stretch-assets path.
- **Files:** each slice's stretched WAV lands in the existing `songwriter_audio/` subfolder via `writeStretched`; orphan reconcile already counts every clip's `assetId` ∪ `stretchedAssetId`, so slice clips are covered with no change.
- **Web:** record is already disabled on web; imported audio is sample-less there, so slice mode is disabled on web (consistent with detection needing WAV samples). No regression.

## Milestones (one ship, in order)

- **M1 — Detection rule.** `songwriter_slice_rules.detectOnsets` + `runDetectOnsets` + `slicePlacements`/`SlicePlan`. Tests: onsets on a synthetic click train near known positions; sensitivity monotonicity; placement clamp + dropped-count math; min-region enforcement.
- **M2 — Slice controller.** `songwriter_slice_controller` running detection via `compute`, debounced on sensitivity, processing flag. Tests: controller emits onsets for a fake sample buffer; re-run on sensitivity change.
- **M3 — Marker UI.** `songwriter_slice_markers` overlay + gestures (add/drag/delete, snap toggle), sensitivity slider, slice-count, in `songwriter_audio_clip_sheet`. Tests: markers render at detected positions; add/delete mutate editor state; snap behavior.
- **M4 — Scatter op + wiring.** `songwriter_store.scatterSlices`, "Scatter to bars" action, snackbar on partial placement. Tests: N slices → N consecutive 1-bar blocks sharing the asset with stretch fit; surplus dropped with count; occupied-bar stop; source removed.
- **M5 — Polish + verification.** `dart format`, `flutter analyze`, full `flutter test`; device pass — record an imperfect take, auto-slice, nudge a marker to a downbeat, scatter, confirm each bar locks to grid on playback; compact + wide viewport.

## Risk Register

1. **Onset-detection quality in pure Dart.** Energy-flux is simpler than spectral methods; sensitivity slider + manual marker editing are the safety net (a bad auto cut is dragged or deleted). Re-evaluate after device tests; a better detector is a localized future swap behind `detectOnsets`.
2. **Stretch artifacts on aggressive correction.** A slice far from one bar in length stretches hard → audible artifacts (same WSOLA caveat as the sampler). Mitigation: markers let the user place cuts near the true bar so correction is small; loop/oneShot remain per-clip alternatives.
3. **Many slices → many stretch renders at once.** Scatter of N slices schedules N renders. Mitigation: reuse the existing debounced/lazy render queue + per-tile processing badge; renders are 1-bar (short).
4. **WAV-only.** Imported mp3/m4a can't be sliced until decoded. Accepted; consistent with the sampler's flat-band caveat. Documented in the UI hint.

## Testing Strategy

- **Unit (`test/schema/rules`):** `detectOnsets` on a synthetic 1 kHz-burst click train (onsets within tolerance of known positions); sensitivity monotonicity (higher → ≥ onset count); `slicePlacements` region math, bar clamp, `droppedCount`; min-region rejection.
- **Unit (`test/store`):** `scatterSlices` produces N consecutive 1-bar blocks sharing `assetId` with `stretch` fit; source block+clip removed; partial placement returns the placed count; occupied-bar stop.
- **Widget (`test/features/songwriter`):** slice mode shows markers at detected positions; sensitivity slider changes marker count; add/delete a marker; "Scatter" replaces the tile with N per-bar tiles; slice disabled for a sample-less asset.
- **Manual / device:** record a deliberately loose 4–8 bar take → auto-slice → drag a marker onto the real downbeat → scatter → play and confirm each bar is grid-locked; verify the partial-placement snackbar by over-slicing a short section.

## Future Work (out of scope)

- **Per-clip pitch shift (±semitones)** — resample + WSOLA repitch, pre-rendered offline; next spec.
- Continuous warp markers within a single clip (sub-bar time-warp) instead of discrete bar slices.
- Onset detection / peaks for decoded mp3/m4a.
- Crossfade at slice boundaries to mask clicks.
- Re-slice / merge an already-scattered set in place.
