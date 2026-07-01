# Audio Slice & Scatter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user slice one Songwriter recording at auto-transient + manual markers and scatter the slices onto consecutive bars as stretch-fit clips, locking a timing-imperfect take to the grid.

**Architecture:** A slice is just another `AudioClip` (narrower trim over the same `AudioAsset`) bound to its own 1-bar audio `SongBlock`. New pieces are an off-thread onset-detection rule, an ephemeral marker UI in the clip editor, and one atomic `scatterSlices` store op that reuses `addAudioClip`/`addAudioBlock`/`removeAudioBlock`. No model or persistence changes.

**Tech Stack:** Dart / Flutter, Riverpod, `compute()` for off-thread DSP, `package:flutter_test`. Reuses `SongAudioRepository.readInt16Samples`, `audio_stretch_rules`, the stretch render controller.

Spec: `docs/superpowers/specs/2026-06-28-songwriter-audio-slice-scatter-design.md`

---

## File Structure

- Create `lib/schema/rules/songwriter_slice_rules.dart` — pure onset detection + slice placement (`detectOnsets`, `runDetectOnsets`, `DetectOnsetsRequest`, `slicePlacements`, `PlacedSlice`, `SlicePlan`).
- Create `lib/store/songwriter_slice_controller.dart` — provider running `detectOnsets` via `compute`, debounced on sensitivity.
- Create `lib/features/songwriter/songwriter_slice_markers.dart` — marker painter + gesture overlay widget.
- Modify `lib/store/songwriter_store.dart` — add `scatterSlices`.
- Modify `lib/features/songwriter/songwriter_audio_clip_sheet.dart` — slice mode toggle, sensitivity slider, marker overlay, "Scatter to bars".
- Tests: `test/schema/rules/songwriter_slice_rules_test.dart`, `test/store/songwriter_scatter_test.dart`, `test/features/songwriter/songwriter_slice_mode_test.dart`.

---

## Task 1: Onset detection rule

**Files:**
- Create: `lib/schema/rules/songwriter_slice_rules.dart`
- Test: `test/schema/rules/songwriter_slice_rules_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_slice_rules.dart';

Int16List _clickTrain(int sampleRate, List<int> onsetMs, int totalMs) {
  final n = (sampleRate * totalMs / 1000).round();
  final out = Int16List(n);
  for (final ms in onsetMs) {
    final start = (sampleRate * ms / 1000).round();
    for (var i = 0; i < 1500 && start + i < n; i++) {
      // Short decaying burst = a transient.
      out[start + i] = (20000 * (1 - i / 1500)).round();
    }
  }
  return out;
}

void main() {
  const sr = 44100;

  test('detectOnsets finds bursts near known positions', () {
    final samples = _clickTrain(sr, [0, 500, 1000, 1500], 2000);
    final onsets = detectOnsets(samples, sr, sensitivity: 0.5);
    // 0 is excluded (implicit region start); expect ~3 internal onsets.
    expect(onsets.length, inInclusiveRange(2, 5));
    for (final target in [500, 1000, 1500]) {
      final targetSample = sr * target ~/ 1000;
      final near = onsets.any((o) => (o - targetSample).abs() < sr * 60 ~/ 1000);
      expect(near, isTrue, reason: 'no onset near ${target}ms');
    }
  });

  test('higher sensitivity never yields fewer onsets', () {
    final samples = _clickTrain(sr, [0, 250, 500, 750, 1000], 1300);
    final low = detectOnsets(samples, sr, sensitivity: 0.1).length;
    final high = detectOnsets(samples, sr, sensitivity: 0.9).length;
    expect(high, greaterThanOrEqualTo(low));
  });

  test('slicePlacements maps cuts to consecutive bars and clamps overflow', () {
    final plan = slicePlacements(
      cutSamples: [sr, 2 * sr, 3 * sr],
      totalSamples: 4 * sr,
      sampleRate: sr,
      startBar: 2,
      sectionLengthBars: 4,
    );
    // 4 regions requested, only bars 2 and 3 free -> 2 placed, 2 dropped.
    expect(plan.slices.length, 2);
    expect(plan.droppedCount, 2);
    expect(plan.slices[0].bar, 2);
    expect(plan.slices[1].bar, 3);
    expect(plan.slices[0].trimStartMs, 0);
    expect(plan.slices[0].trimEndMs, 1000);
    expect(plan.slices[1].trimStartMs, 1000);
    expect(plan.slices[1].trimEndMs, 2000);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/songwriter_slice_rules_test.dart`
Expected: FAIL — `songwriter_slice_rules.dart` does not exist / symbols undefined.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

/// Detected onset sample positions in [samples], strictly increasing and
/// excluding 0. Energy-novelty peaks above an adaptive threshold whose
/// strictness is set by [sensitivity] in [0,1] (higher -> more onsets).
List<int> detectOnsets(
  Int16List samples,
  int sampleRate, {
  double sensitivity = 0.5,
}) {
  const frame = 1024;
  const hop = 512;
  if (samples.length < frame * 2) return const [];

  final frames = ((samples.length - frame) / hop).floor() + 1;
  final energy = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    final start = f * hop;
    var sum = 0.0;
    for (var i = 0; i < frame; i++) {
      final s = samples[start + i] / 32768.0;
      sum += s * s;
    }
    energy[f] = sum / frame;
  }

  // Positive energy difference = novelty curve.
  final novelty = Float64List(frames);
  for (var f = 1; f < frames; f++) {
    final d = energy[f] - energy[f - 1];
    novelty[f] = d > 0 ? d : 0.0;
  }

  // Adaptive threshold: local mean + k*std over a sliding window.
  // k shrinks with sensitivity so more peaks pass when sensitivity is high.
  final k = 2.4 - 2.0 * sensitivity.clamp(0.0, 1.0); // ~2.4 .. 0.4
  const win = 16;
  final refractoryFrames = (sampleRate * 0.05 / hop).ceil(); // >=50 ms apart
  final onsets = <int>[];
  var lastFrame = -refractoryFrames - 1;
  for (var f = 1; f < frames; f++) {
    final lo = math.max(1, f - win);
    final hi = math.min(frames - 1, f + win);
    var mean = 0.0;
    for (var j = lo; j <= hi; j++) {
      mean += novelty[j];
    }
    mean /= (hi - lo + 1);
    var varSum = 0.0;
    for (var j = lo; j <= hi; j++) {
      final d = novelty[j] - mean;
      varSum += d * d;
    }
    final std = math.sqrt(varSum / (hi - lo + 1));
    final thr = mean + k * std;
    final isPeak = novelty[f] > thr &&
        novelty[f] >= novelty[f - 1] &&
        (f + 1 >= frames || novelty[f] >= novelty[f + 1]);
    if (isPeak && f - lastFrame > refractoryFrames) {
      final pos = f * hop;
      if (pos > 0) onsets.add(pos);
      lastFrame = f;
    }
  }
  return onsets;
}

/// Argument bundle for running [detectOnsets] inside `compute()`.
class DetectOnsetsRequest {
  const DetectOnsetsRequest(this.samples, this.sampleRate, this.sensitivity);
  final Int16List samples;
  final int sampleRate;
  final double sensitivity;
}

/// Top-level `compute()` entry, mirrors `runStretch`.
List<int> runDetectOnsets(DetectOnsetsRequest r) =>
    detectOnsets(r.samples, r.sampleRate, sensitivity: r.sensitivity);

/// One placeable slice: a trim region (ms, clip-local) on a target bar.
class PlacedSlice {
  const PlacedSlice({
    required this.trimStartMs,
    required this.trimEndMs,
    required this.bar,
  });
  final int trimStartMs;
  final int trimEndMs;
  final int bar;
}

/// Result of [slicePlacements]: the slices that fit, and how many were dropped
/// for lack of bars.
class SlicePlan {
  const SlicePlan({required this.slices, required this.droppedCount});
  final List<PlacedSlice> slices;
  final int droppedCount;
}

/// Turn ordered cut positions (sample indexes; 0 and end are implicit) into
/// regions placed on consecutive bars from [startBar]. The region count is
/// `cutSamples.length + 1`; it is clamped to the bars available from
/// [startBar] to [sectionLengthBars], and the overflow is reported.
SlicePlan slicePlacements({
  required List<int> cutSamples,
  required int totalSamples,
  required int sampleRate,
  required int startBar,
  required int sectionLengthBars,
}) {
  final bounds = <int>[0, ...cutSamples, totalSamples];
  final regions = bounds.length - 1;
  final available = (sectionLengthBars - startBar).clamp(0, sectionLengthBars);
  final placeable = math.min(regions, available);
  int msOf(int sample) => (sample * 1000 / sampleRate).round();
  final slices = <PlacedSlice>[
    for (var i = 0; i < placeable; i++)
      PlacedSlice(
        trimStartMs: msOf(bounds[i]),
        trimEndMs: msOf(bounds[i + 1]),
        bar: startBar + i,
      ),
  ];
  return SlicePlan(slices: slices, droppedCount: regions - placeable);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/songwriter_slice_rules_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/songwriter_slice_rules.dart test/schema/rules/songwriter_slice_rules_test.dart
git commit -m "feat(songwriter): onset detection + slice placement rules"
```

---

## Task 2: Slice controller

**Files:**
- Create: `lib/store/songwriter_slice_controller.dart`
- Test: covered indirectly by Task 4 widget test; no isolated unit test (it is a thin `compute` wrapper, like `songwriter_stretch_controller`).

- [ ] **Step 1: Write the implementation**

Read `lib/store/songwriter_stretch_controller.dart` first to match its provider style and repository access.

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/songwriter.dart';
import '../schema/rules/songwriter_slice_rules.dart';
import 'song_audio_repository.dart';
import 'songwriter_store.dart';

class SliceDetectionState {
  const SliceDetectionState({
    this.onsets = const [],
    this.processing = false,
  });
  final List<int> onsets; // sample positions within the trimmed region
  final bool processing;
}

/// Runs onset detection for [clipId]'s trimmed region off the UI thread.
/// Re-run by calling [detect] (debounced by the caller's slider).
class SongwriterSliceController extends Notifier<SliceDetectionState> {
  Timer? _debounce;

  @override
  SliceDetectionState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SliceDetectionState();
  }

  Future<void> detect({required String clipId, required double sensitivity}) async {
    _debounce?.cancel();
    final completer = Completer<void>();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      await _run(clipId, sensitivity);
      completer.complete();
    });
    return completer.future;
  }

  Future<void> _run(String clipId, double sensitivity) async {
    final project = ref.read(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final asset =
        project.audioAssets.where((a) => a.id == clip.assetId).firstOrNull;
    if (asset == null) return;

    state = const SliceDetectionState(processing: true);
    final repo = ref.read(songwriterAudioRepositoryProvider);
    final full = await repo.readInt16Samples(asset.id, asset.format);
    if (full.isEmpty) {
      state = const SliceDetectionState();
      return;
    }
    final sr = asset.sampleRate <= 0 ? 44100 : asset.sampleRate;
    final startSample = (clip.trimStartMs * sr / 1000).round().clamp(0, full.length);
    final endRaw = clip.trimEndMs == 0 ? full.length : (clip.trimEndMs * sr / 1000).round();
    final endSample = endRaw.clamp(startSample, full.length);
    final region = Int16List.sublistView(full, startSample, endSample);

    final onsets = await compute(
      runDetectOnsets,
      DetectOnsetsRequest(Int16List.fromList(region), sr, sensitivity),
    );
    state = SliceDetectionState(onsets: onsets, processing: false);
  }
}

final songwriterSliceControllerProvider =
    NotifierProvider<SongwriterSliceController, SliceDetectionState>(
      SongwriterSliceController.new,
    );
```

Note: confirm `AudioAsset` exposes `sampleRate` and `format`; if `sampleRate` is absent, read it from the repo's WAV header path used by the stretch controller and mirror that here.

- [ ] **Step 2: Analyze**

Run: `dart analyze lib/store/songwriter_slice_controller.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/store/songwriter_slice_controller.dart
git commit -m "feat(songwriter): slice detection controller (off-thread)"
```

---

## Task 3: scatterSlices store op

**Files:**
- Modify: `lib/store/songwriter_store.dart` (add method near `addAudioBlock`, ~line 618)
- Test: `test/store/songwriter_scatter_test.dart`

- [ ] **Step 1: Write the failing test**

Read an existing store test (e.g. `test/store/songwriter_audio_playback_test.dart`) for the harness: how a `ProviderContainer` is built, how an audio lane + asset + clip + block are seeded. Reuse that setup.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_slice_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  test('scatterSlices replaces source with consecutive 1-bar stretch clips', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(songwriterProvider.notifier);

    // --- Seed: 4-bar section, audio lane, one source clip+block at bar 0. ---
    // (Use the same seeding helpers the existing audio playback test uses.)
    final ids = seedAudioSourceBlock(store, sectionLengthBars: 4, startBar: 0);

    final placed = store.scatterSlices(
      sectionId: ids.sectionId,
      laneId: ids.laneId,
      sourceBlockId: ids.blockId,
      slices: const [
        PlacedSlice(trimStartMs: 0, trimEndMs: 500, bar: 0),
        PlacedSlice(trimStartMs: 500, trimEndMs: 1000, bar: 1),
        PlacedSlice(trimStartMs: 1000, trimEndMs: 1500, bar: 2),
      ],
    );

    expect(placed, 3);
    final project = container.read(songwriterProvider);
    final lane = project.sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.id == ids.laneId);
    final audioBlocks = lane.blocks.where((b) => b.audioClipId != null).toList()
      ..sort((a, b) => a.startBar.compareTo(b.startBar));
    expect(audioBlocks.map((b) => b.startBar), [0, 1, 2]);
    expect(audioBlocks.every((b) => b.spanBars == 1), isTrue);
    // Source block gone.
    expect(audioBlocks.any((b) => b.id == ids.blockId), isFalse);
    // All slice clips share the source asset and are stretch-fit.
    for (final b in audioBlocks) {
      final clip = project.audioClips.firstWhere((c) => c.id == b.audioClipId);
      expect(clip.assetId, ids.assetId);
      expect(clip.fitMode, AudioFitMode.stretch);
    }
  });
}
```

If the existing tests have no `seedAudioSourceBlock` helper, write one in this test file: create an `AudioAsset` (via `store.addAudioAsset`), an audio lane (`store.addLane(kind: SongLaneKind.audio, ...)`), a clip (`store.addAudioClip`), and a block (`store.addAudioBlock`), returning their ids. Mirror the construction used in `test/features/songwriter/songwriter_audio_lane_test.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_scatter_test.dart`
Expected: FAIL — `scatterSlices` undefined.

- [ ] **Step 3: Write the implementation**

Add to `SongwriterNotifier` (in `lib/store/songwriter_store.dart`). IMPORTANT ordering: add the slice clips (which reference `assetId`) BEFORE removing the source block, because `removeAudioBlock` deletes the asset file when no remaining clip references it.

```dart
/// Replace the source audio block+clip with one clip+block per slice on
/// consecutive bars. Each new clip shares the source assetId with the slice's
/// trim region; fit defaults to stretch (timing correction). Skips a bar
/// already occupied by another block. Returns how many slices were placed.
int scatterSlices({
  required String sectionId,
  required String laneId,
  required String sourceBlockId,
  required List<PlacedSlice> slices,
  AudioFitMode fitMode = AudioFitMode.stretch,
}) {
  final lane = state.sections
      .where((s) => s.id == sectionId)
      .expand((s) => s.lanes)
      .where((l) => l.id == laneId)
      .firstOrNull;
  final source = lane?.blocks.where((b) => b.id == sourceBlockId).firstOrNull;
  final clipId = source?.audioClipId;
  final assetId =
      clipId == null ? null : state.audioClips.where((c) => c.id == clipId).firstOrNull?.assetId;
  if (lane == null || source == null || assetId == null) return 0;

  // Bars occupied by OTHER blocks (the source's own bars are free to reuse).
  final occupied = <int>{
    for (final b in lane.blocks)
      if (b.id != sourceBlockId)
        for (var i = b.startBar; i < b.endBar; i++) i,
  };

  var placed = 0;
  for (final s in slices) {
    if (occupied.contains(s.bar)) break; // stop at the first blocked bar
    final newClipId = addAudioClip(
      assetId: assetId,
      durationMs: s.trimEndMs - s.trimStartMs,
    );
    setClipTrim(
      clipId: newClipId,
      trimStartMs: s.trimStartMs,
      trimEndMs: s.trimEndMs,
    );
    setClipFitMode(clipId: newClipId, fitMode: fitMode);
    addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: newClipId,
      startBar: s.bar,
      spanBars: 1,
    );
    placed++;
  }

  // Remove the source LAST so its asset survives (slice clips now reference it).
  if (placed > 0) {
    removeAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      blockId: sourceBlockId,
    );
  }
  return placed;
}
```

Add the import at the top of the file: `import '../schema/rules/songwriter_slice_rules.dart';` (for `PlacedSlice`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_scatter_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the wider store + audio suite for regressions**

Run: `flutter test test/store test/features/songwriter/songwriter_audio_lane_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_scatter_test.dart
git commit -m "feat(songwriter): scatterSlices store op"
```

---

## Task 4: Slice marker overlay widget

**Files:**
- Create: `lib/features/songwriter/songwriter_slice_markers.dart`
- Test: marker rendering asserted in Task 5's widget test.

- [ ] **Step 1: Write the implementation**

A stateless overlay: given marker fractions (0..1 across the waveform width) it paints vertical lines and exposes tap-to-add / drag / delete via callbacks. State (the marker list) lives in the editor (Task 5).

```dart
import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// Draggable cut markers over the clip waveform. [markers] are fractions in
/// [0,1] across the width. Tapping empty space calls [onAdd] with the tapped
/// fraction; dragging a marker calls [onMove]; a marker dragged out (or
/// long-pressed) calls [onDelete]. Pure presentation — the editor owns state.
class SongwriterSliceMarkers extends StatelessWidget {
  const SongwriterSliceMarkers({
    super.key,
    required this.markers,
    required this.onAdd,
    required this.onMove,
    required this.onDelete,
  });
  final List<double> markers;
  final void Function(double fraction) onAdd;
  final void Function(int index, double fraction) onMove;
  final void Function(int index) onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onAdd((d.localPosition.dx / w).clamp(0.0, 1.0)),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarkerPainter(markers, MuzicianTheme.sky),
                  ),
                ),
              ),
              for (var i = 0; i < markers.length; i++)
                Positioned(
                  left: (markers[i] * w - 11).clamp(0.0, w - 22),
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    key: Key('sliceMarker_$i'),
                    onHorizontalDragUpdate: (d) => onMove(
                      i,
                      ((markers[i] * w) + d.delta.dx).clamp(0.0, w) / w,
                    ),
                    onLongPress: () => onDelete(i),
                    child: const SizedBox(
                      width: 22,
                      child: Center(
                        child: SizedBox(width: 2, child: ColoredBox(color: MuzicianTheme.sky)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.markers, this.color);
  final List<double> markers;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (final m in markers) {
      final x = m * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.markers != markers || old.color != color;
}
```

- [ ] **Step 2: Analyze**

Run: `dart analyze lib/features/songwriter/songwriter_slice_markers.dart`
Expected: No issues found. (If `ColoredBox`/`SizedBox` const composition warns, adjust to a `Container(width: 2, color: ...)`.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/songwriter/songwriter_slice_markers.dart
git commit -m "feat(songwriter): slice marker overlay widget"
```

---

## Task 5: Slice mode in the clip editor

**Files:**
- Modify: `lib/features/songwriter/songwriter_audio_clip_sheet.dart`
- Test: `test/features/songwriter/songwriter_slice_mode_test.dart`

- [ ] **Step 1: Write the failing test**

Read `test/features/songwriter/songwriter_audio_clip_sheet_test.dart` for how the sheet is pumped with a seeded clip. Then:

```dart
// Pump the clip sheet for a WAV-backed clip, enter slice mode, assert markers
// appear after detection, and that "Scatter" replaces the source tile.
testWidgets('slice mode shows markers and scatter creates per-bar tiles',
    (tester) async {
  // ... seed project with a WAV asset whose samples yield >=2 onsets ...
  // ... pump SongwriterAudioClipBody, tap the Slice toggle (Key('clipSliceToggle')) ...
  // await tester.pumpAndSettle();
  // expect(find.byKey(const Key('sliceMarker_0')), findsWidgets);
  // await tester.tap(find.byKey(const Key('clipScatter')));
  // await tester.pumpAndSettle();
  // expect(audio blocks on the lane to be > 1);
});
```

Keep this test focused; if real onset detection is awkward to seed deterministically in a widget test, stub the controller via a provider override that returns fixed onsets, and assert the marker count + scatter result.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_slice_mode_test.dart`
Expected: FAIL — no `clipSliceToggle` / `clipScatter` keys.

- [ ] **Step 3: Implement slice mode**

In `_SongwriterAudioClipBodyState`, add local state:

```dart
bool _sliceMode = false;
double _sensitivity = 0.5;
List<double> _markerFracs = []; // 0..1 across the trimmed region
```

- Add a Slice toggle button (`Key('clipSliceToggle')`), shown only when the asset has samples (`asset.peaks.isNotEmpty` is a proxy for WAV; otherwise disable with a tooltip "Slicing needs a recorded (WAV) clip").
- On entering slice mode, call `ref.read(songwriterSliceControllerProvider.notifier).detect(clipId: clipId, sensitivity: _sensitivity)`, then convert returned onset sample positions to fractions of the region length and seed `_markerFracs` (auto markers). Re-run on sensitivity slider change.
- Render `SongwriterSliceMarkers` over the `_TrimWaveform` when `_sliceMode`, wiring `onAdd`/`onMove`/`onDelete` to mutate `_markerFracs` via `setState`.
- Add a sensitivity `Slider` (`Key('clipSensitivity')`) and a slice-count label.
- Add a "Scatter to bars" `FilledButton` (`Key('clipScatter')`), enabled when `_markerFracs` yields >= 1 region beyond the first (i.e. at least one marker). On tap:

```dart
final project = ref.read(songwriterProvider);
final cfg = project.config;
final asset = project.audioAssets.firstWhere((a) => a.id == clip.assetId);
final sr = asset.sampleRate <= 0 ? 44100 : asset.sampleRate;
final regionMs = (clip.trimEndMs == 0 ? asset.durationMs : clip.trimEndMs) - clip.trimStartMs;
final totalSamples = (regionMs * sr / 1000).round();
final cutSamples = (_markerFracs.toList()..sort())
    .map((f) => (f * totalSamples).round())
    .toList();
final plan = slicePlacements(
  cutSamples: cutSamples,
  totalSamples: totalSamples,
  sampleRate: sr,
  startBar: block.startBar,
  sectionLengthBars: section.lengthBars,
);
final placed = ref.read(songwriterProvider.notifier).scatterSlices(
  sectionId: section.id,
  laneId: laneId,
  sourceBlockId: block.id,
  slices: plan.slices,
);
if (context.mounted) {
  if (plan.droppedCount > 0) {
    // show snackbar: "Placed $placed slices, ${plan.droppedCount} dropped — section ran out of bars."
  }
  Navigator.of(context).maybePop();
}
```

Note: the slice trim ms in `plan.slices` are region-local; since the source clip's own `trimStartMs` is the region origin, add `clip.trimStartMs` to each slice's `trimStartMs/trimEndMs` before passing to `scatterSlices` so trims are asset-absolute. Verify against how `setClipTrim` interprets values (asset-absolute ms) and adjust `slicePlacements` inputs or the scatter call accordingly.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_slice_mode_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format**

Run: `dart analyze lib/features/songwriter/songwriter_audio_clip_sheet.dart && dart format lib/features/songwriter/songwriter_audio_clip_sheet.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/songwriter_audio_clip_sheet.dart test/features/songwriter/songwriter_slice_mode_test.dart
git commit -m "feat(songwriter): slice mode UI + scatter action in clip editor"
```

---

## Task 6: Full verification

- [ ] **Step 1: Analyze the whole library**

Run: `dart analyze lib`
Expected: No issues found.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 3: Manual device pass**

Record a deliberately loose 4-bar take → open the clip → Slice → adjust sensitivity → drag a marker onto a real downbeat → Scatter → play and confirm each bar is grid-locked. Over-slice a short section to see the partial-placement snackbar.

- [ ] **Step 4: Commit any format/analyze fixes**

```bash
git add -A
git commit -m "chore(songwriter): slice & scatter verification pass"
```

---

## Self-Review Notes

- **Spec coverage:** detection (Task 1) · sensitivity + off-thread (Tasks 1–2) · manual markers add/move/delete (Task 4–5) · scatter to consecutive bars, default stretch, source removal (Task 3) · overflow/occupied-bar handling + snackbar (Tasks 1, 3, 5) · WAV-only gating (Task 5) · tests at each layer (all). Pitch is intentionally absent (deferred).
- **Open verification points flagged inline (resolve during implementation):** `AudioAsset.sampleRate` existence (Tasks 2, 5); whether `setClipTrim` ms are asset-absolute vs region-local (Task 5 trim-origin note). These are codebase facts the implementing agent must confirm against the model before finalizing each task.
- **Type consistency:** `PlacedSlice`/`SlicePlan`/`detectOnsets`/`runDetectOnsets`/`scatterSlices` names are used identically across tasks and tests.
