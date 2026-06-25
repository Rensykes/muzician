# Songwriter Audio Sampler — Plan 4: Clip Editor + Pitch-Preserving Stretch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Koala-style clip editor sheet — trim handles, bar-span stepper, fit-mode toggle, audition — plus a pure-Dart WSOLA time-stretch that pre-renders a pitch-preserving derived asset whenever a stretch clip's span/trim/mode or the project tempo changes.

**Architecture:** WSOLA lives in a pure rule (`audio_stretch_rules.dart`) runnable in `compute()`. A `SongwriterStretchController` computes the target millisecond length from the clip's bar span, reads the trimmed source region via the repository, runs WSOLA off the UI thread, writes a derived `AudioAsset`, and stamps `stretchedAssetId` on the clip while tracking a "processing" set. The editor sheet edits trim/span/fit and triggers re-render; the lane tile shows a processing badge.

**Tech Stack:** Dart (`Float64List`/`Int16List` DSP), `flutter/foundation` `compute`, Riverpod, `flutter_test`.

**Depends on:** Plans 1–3. Spec: `docs/superpowers/specs/2026-06-25-songwriter-audio-sampler-design.md` (§Stretch engine, Risks 1–2).

Reference files:
- `lib/utils/wav_writer.dart` — `writeWavPcm16Mono(Int16List, sampleRate)`, `parseWavHeader`.
- `lib/store/song_audio_repository.dart` — `_extractInt16Samples` (make public), `writeRecording`, `resolvePath`.
- `lib/features/songwriter/drum_pattern_sheet.dart` — `showWidgetSheet` launch pattern.
- `lib/features/songwriter/songwriter_audio_lane_row.dart` (Plan 2) — tile that will open the editor + show the badge.
- `lib/schema/rules/songwriter_audio_rules.dart` (Plan 3) — `usesStretched` branch already consumes `stretchedAssetId`.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/schema/rules/audio_stretch_rules.dart` | WSOLA `stretchInt16` + `runStretch` compute entry | Create |
| `lib/store/song_audio_repository.dart` | public `extractInt16Samples`, `readInt16Samples`, `writeStretched` | Modify |
| `lib/schema/rules/songwriter_stretch_rules.dart` | pure `stretchTargetMs` + `audioClipSpanBars` | Create |
| `lib/store/songwriter_stretch_controller.dart` | re-render orchestration + processing set | Create |
| `lib/features/songwriter/songwriter_audio_clip_sheet.dart` | the editor sheet | Create |
| `lib/features/songwriter/songwriter_audio_lane_row.dart` | open editor on tap; processing badge | Modify |
| `lib/store/songwriter_store.dart` | `setClipStretchedAsset` helper | Modify |
| Tests | as listed per task | Create |

---

### Task 1: WSOLA time-stretch rule

**Files:**
- Create: `lib/schema/rules/audio_stretch_rules.dart`
- Test: `test/schema/rules/audio_stretch_rules_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/audio_stretch_rules_test.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/audio_stretch_rules.dart';

Int16List _sine(int n, double freq, int sr) => Int16List.fromList([
      for (var i = 0; i < n; i++)
        (sin(2 * pi * freq * i / sr) * 12000).round(),
    ]);

double _rms(Int16List x) {
  if (x.isEmpty) return 0;
  var sum = 0.0;
  for (final s in x) {
    sum += s * s;
  }
  return sqrt(sum / x.length);
}

void main() {
  const sr = 44100;

  test('stretches to ~target length (2x longer)', () {
    final input = _sine(sr, 220, sr); // 1s
    final out = stretchInt16(input, sr, 2000); // → 2s
    expect(out.length, closeTo(sr * 2, sr * 0.02)); // within 2%
  });

  test('compresses to ~target length (0.5x)', () {
    final input = _sine(sr, 220, sr);
    final out = stretchInt16(input, sr, 500);
    expect(out.length, closeTo(sr ~/ 2, sr * 0.02));
  });

  test('preserves energy (output is not silence)', () {
    final input = _sine(sr, 220, sr);
    final out = stretchInt16(input, sr, 1500);
    expect(_rms(out), greaterThan(_rms(input) * 0.4));
  });

  test('handles sub-frame input via resample', () {
    final out = stretchInt16(_sine(200, 220, sr), sr, 20);
    expect(out.length, closeTo(sr * 20 ~/ 1000, 4));
  });

  test('identity when target ~= source length', () {
    final input = _sine(1000, 220, sr);
    final out = stretchInt16(input, sr, (1000 * 1000 / sr).round());
    expect(out.length, closeTo(1000, 4));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/audio_stretch_rules_test.dart`
Expected: FAIL — `stretchInt16` undefined.

- [ ] **Step 3: Implement WSOLA**

Create `lib/schema/rules/audio_stretch_rules.dart`:

```dart
/// Pure pitch-preserving time-stretch (WSOLA) for mono PCM16.
///
/// Sketch quality, tunable via the constants below. No external deps so it runs
/// in `compute()`. See spec Risk 1.
library;

import 'dart:math';
import 'dart:typed_data';

/// Argument bundle for running [stretchInt16] inside `compute()`.
class StretchRequest {
  final Int16List samples;
  final int sampleRate;
  final int targetMs;
  const StretchRequest(this.samples, this.sampleRate, this.targetMs);
}

/// Top-level `compute()` entry point.
Int16List runStretch(StretchRequest r) =>
    stretchInt16(r.samples, r.sampleRate, r.targetMs);

const int _frame = 1024;
const int _synthHop = _frame ~/ 2; // 512
const int _search = 128;

/// Time-stretches [input] (mono int16) to ~[targetMs] at [sampleRate],
/// preserving pitch. Returns a new buffer.
Int16List stretchInt16(Int16List input, int sampleRate, int targetMs) {
  final targetLen = (targetMs / 1000.0 * sampleRate).round();
  if (input.isEmpty || targetLen <= 0) return Int16List(0);
  if ((targetLen - input.length).abs() <= 1) {
    return Int16List.fromList(input);
  }
  if (input.length < _frame) return _linearResample(input, targetLen);

  final ratio = input.length / targetLen; // analysis advance per synth hop
  final window = _hann(_frame);
  final out = Float64List(targetLen + _frame);
  final norm = Float64List(targetLen + _frame);
  final ref = Float64List(_frame); // expected continuation to match next frame

  var outPos = 0;
  var analysisPos = 0.0;
  var first = true;
  while (outPos + _frame <= out.length) {
    final centre = analysisPos.floor();
    if (centre + _frame > input.length) break;
    final a = first ? centre : _bestOffset(input, centre, ref);
    for (var i = 0; i < _frame; i++) {
      out[outPos + i] += input[a + i] * window[i];
      norm[outPos + i] += window[i];
    }
    for (var i = 0; i < _frame; i++) {
      final j = a + _synthHop + i;
      ref[i] = j < input.length ? input[j].toDouble() : 0.0;
    }
    outPos += _synthHop;
    analysisPos += _synthHop * ratio;
    first = false;
  }

  final result = Int16List(targetLen);
  for (var i = 0; i < targetLen; i++) {
    final n = norm[i];
    final v = n > 1e-6 ? out[i] / n : 0.0;
    result[i] = v.clamp(-32768.0, 32767.0).round();
  }
  return result;
}

int _bestOffset(Int16List x, int centre, Float64List ref) {
  final maxStart = x.length - _frame;
  if (maxStart <= 0) return 0;
  final lo = (centre - _search).clamp(0, maxStart);
  final hi = (centre + _search).clamp(0, maxStart);
  const overlap = _frame ~/ 2;
  var bestPos = centre.clamp(0, maxStart);
  var bestCorr = -double.infinity;
  for (var p = lo; p <= hi; p++) {
    var corr = 0.0;
    for (var i = 0; i < overlap; i++) {
      corr += x[p + i] * ref[i];
    }
    if (corr > bestCorr) {
      bestCorr = corr;
      bestPos = p;
    }
  }
  return bestPos;
}

Float64List _hann(int n) {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * cos(2 * pi * i / (n - 1));
  }
  return w;
}

Int16List _linearResample(Int16List input, int targetLen) {
  final out = Int16List(targetLen);
  if (input.length == 1) {
    for (var i = 0; i < targetLen; i++) {
      out[i] = input[0];
    }
    return out;
  }
  for (var i = 0; i < targetLen; i++) {
    final srcPos = i * (input.length - 1) / (targetLen - 1);
    final lo = srcPos.floor();
    final hi = min(lo + 1, input.length - 1);
    final frac = srcPos - lo;
    out[i] = (input[lo] * (1 - frac) + input[hi] * frac).round();
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/audio_stretch_rules_test.dart`
Expected: PASS (all five). If the "preserves energy" RMS ratio is brittle, the WSOLA normalization is the cause — verify `norm` accumulation; do not weaken the test below 0.4 without cause.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/schema/rules/audio_stretch_rules.dart test/schema/rules/audio_stretch_rules_test.dart
flutter analyze lib/schema/rules/audio_stretch_rules.dart
git add lib/schema/rules/audio_stretch_rules.dart test/schema/rules/audio_stretch_rules_test.dart
git commit -m "feat(audio): pure WSOLA pitch-preserving time-stretch"
```

---

### Task 2: Repository — read samples + write a stretched asset

**Files:**
- Modify: `lib/store/song_audio_repository.dart`
- Test: `test/store/song_audio_repository_stretch_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/store/song_audio_repository_stretch_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('stretch_repo_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('writeStretched writes a wav whose duration matches the samples', () async {
    final repo = SongAudioRepository.testWith(
        rootDirectory: tmp, subdir: 'songwriter_audio');
    final samples = Int16List.fromList(List<int>.filled(88200, 0)); // 2s @44.1k
    final asset = await repo.writeStretched(samples: samples, sampleRate: 44100);
    expect(asset.durationMs, inInclusiveRange(1990, 2010));
    expect(asset.sourceLabel, 'Stretched');
    final f = await repo.resolvePath(asset.id, 'wav');
    expect(f.existsSync(), isTrue);
  });

  test('readInt16Samples round-trips written samples', () async {
    final repo = SongAudioRepository.testWith(
        rootDirectory: tmp, subdir: 'songwriter_audio');
    final wav = writeWavPcm16Mono(
        Int16List.fromList([10, -20, 30, -40]), sampleRate: 44100);
    final asset = await repo.writeRecording(wav);
    final back = await repo.readInt16Samples(asset.id, 'wav');
    expect(back.sublist(0, 4), [10, -20, 30, -40]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_repository_stretch_test.dart`
Expected: FAIL — `writeStretched` / `readInt16Samples` undefined.

- [ ] **Step 3: Implement**

In `lib/store/song_audio_repository.dart`:
1. Rename the private `_extractInt16Samples` to public `extractInt16Samples` (update the two internal call sites in `writeRecording`/`importExternalFile`).
2. Add:

```dart
  Future<Int16List> readInt16Samples(String assetId, String format) async {
    final file = await resolvePath(assetId, format);
    if (!file.existsSync()) return Int16List(0);
    final bytes = await file.readAsBytes();
    return extractInt16Samples(bytes);
  }

  Future<AudioAsset> writeStretched({
    required Int16List samples,
    required int sampleRate,
  }) async {
    final wav = writeWavPcm16Mono(samples, sampleRate: sampleRate);
    final asset = await writeRecording(wav);
    return asset.copyWith(sourceLabel: 'Stretched');
  }
```

Add `import '../utils/wav_writer.dart';` if not already imported (it is — used by `writeRecording`). `extractInt16Samples` returns `Int16List`; keep the existing body.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_audio_repository_stretch_test.dart test/store/song_audio_repository_test.dart test/store/song_audio_repository_subdir_test.dart`
Expected: PASS (and the rename did not break existing repo tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/store/song_audio_repository.dart test/store/song_audio_repository_stretch_test.dart
flutter analyze lib/store/song_audio_repository.dart
git add lib/store/song_audio_repository.dart test/store/song_audio_repository_stretch_test.dart
git commit -m "feat(audio): repository read samples + writeStretched"
```

---

### Task 3: Stretch target math + re-render controller

**Files:**
- Create: `lib/schema/rules/songwriter_stretch_rules.dart`
- Create: `lib/store/songwriter_stretch_controller.dart`
- Modify: `lib/store/songwriter_store.dart` (`setClipStretchedAsset`)
- Test: `test/schema/rules/songwriter_stretch_rules_test.dart`
- Test: `test/store/songwriter_stretch_controller_test.dart`

- [ ] **Step 1: Write the failing rule test**

Create `test/schema/rules/songwriter_stretch_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_stretch_rules.dart';

SongwriterProjectSnapshot _p(int tempo) => SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: tempo, beatsPerBar: 4, beatUnit: 4),
      audioClips: const [AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 1000)],
      sections: const [SongSection(id: 's1', lengthBars: 4, order: 0, lanes: [
        SongLane(id: 'l1', kind: SongLaneKind.audio, order: 0, blocks: [
          SongBlock(id: 'b1', startBar: 0, spanBars: 2, audioClipId: 'c1'),
        ]),
      ])],
    );

void main() {
  test('audioClipSpanBars finds the placing block span', () {
    expect(audioClipSpanBars(_p(120), 'c1'), 2);
    expect(audioClipSpanBars(_p(120), 'missing'), isNull);
  });

  test('stretchTargetMs = span bars × bar ms', () {
    // 120 BPM 4/4: 1 bar = 2000ms → 2 bars = 4000ms
    expect(stretchTargetMs(_p(120), 'c1'), 4000);
    // 60 BPM: 1 bar = 4000ms → 2 bars = 8000ms
    expect(stretchTargetMs(_p(60), 'c1'), 8000);
  });
}
```

- [ ] **Step 2: Run + fail, then implement the rule**

Run: `flutter test test/schema/rules/songwriter_stretch_rules_test.dart` → FAIL.

Create `lib/schema/rules/songwriter_stretch_rules.dart`:

```dart
/// Pure helpers for stretch re-rendering decisions.
library;

import '../../models/songwriter.dart';

/// Bar span of the audio block that references [clipId], or null if none.
int? audioClipSpanBars(SongwriterProjectSnapshot project, String clipId) {
  for (final section in project.sections) {
    for (final lane in section.lanes) {
      if (lane.kind != SongLaneKind.audio) continue;
      for (final block in lane.blocks) {
        if (block.audioClipId == clipId) return block.spanBars;
      }
    }
  }
  return null;
}

/// Target stretched length in ms = span bars × bar duration, or null if the
/// clip is unplaced.
int? stretchTargetMs(SongwriterProjectSnapshot project, String clipId) {
  final span = audioClipSpanBars(project, clipId);
  if (span == null) return null;
  final cfg = project.config;
  final barMs = cfg.beatsPerBar * 60000.0 / cfg.tempo;
  return (span * barMs).round();
}
```

Run again → PASS. Commit:

```bash
dart format lib/schema/rules/songwriter_stretch_rules.dart test/schema/rules/songwriter_stretch_rules_test.dart
git add lib/schema/rules/songwriter_stretch_rules.dart test/schema/rules/songwriter_stretch_rules_test.dart
git commit -m "feat(songwriter): stretch target ms + clip span helpers"
```

- [ ] **Step 3: Add `setClipStretchedAsset` to the store**

In `lib/store/songwriter_store.dart`, beside the Plan-1 clip helpers:

```dart
  void setClipStretchedAsset({
    required String clipId,
    required AudioAsset stretchedAsset,
    String? removeAssetId,
  }) {
    final clip = state.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final assets = [
      for (final a in state.audioAssets)
        if (a.id != removeAssetId) a,
      stretchedAsset,
    ];
    final clips = state.audioClips
        .map((c) => c.id == clipId
            ? c.copyWith(stretchedAssetId: stretchedAsset.id)
            : c)
        .toList();
    _set(state.copyWith(audioAssets: assets, audioClips: clips));
  }
```

> Import `AudioAsset` if not visible (it comes via the existing `song_project.dart` import that `songwriter.dart` re-exports — confirm; otherwise add `import '../models/song_project.dart' show AudioAsset;`).

- [ ] **Step 4: Write the failing controller test**

Create `test/store/songwriter_stretch_controller_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_stretch_controller.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('stretch_ctl_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('rerender stamps a stretchedAssetId sized to the span', () async {
    final repo = SongAudioRepository.testWith(
        rootDirectory: tmp, subdir: 'songwriter_audio');
    final c = ProviderContainer(overrides: [
      songwriterAudioRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);

    // Seed a 1s source asset on disk.
    final wav = writeWavPcm16Mono(
        Int16List.fromList(List<int>.filled(44100, 1000)), sampleRate: 44100);
    final src = await repo.writeRecording(wav);

    final store = c.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).id;
    final clipId = store.addAudioClip(assetId: src.id, durationMs: src.durationMs);
    store.setClipFitMode(clipId: clipId, fitMode: AudioFitMode.stretch);
    store.addAudioBlock(sectionId: sectionId, laneId: laneId,
        audioClipId: clipId, startBar: 0, spanBars: 2); // 120 BPM default → 4000ms

    await c.read(songwriterStretchControllerProvider).rerender(clipId);

    final clip = c.read(songwriterProvider).audioClips
        .firstWhere((x) => x.id == clipId);
    expect(clip.stretchedAssetId, isNotNull);
    final stretched = c.read(songwriterProvider).audioAssets
        .firstWhere((a) => a.id == clip.stretchedAssetId);
    expect(stretched.durationMs, inInclusiveRange(3900, 4100));
    expect(c.read(songwriterStretchProcessingProvider).contains(clipId), isFalse);
  });
}
```

> The default `SongwriterConfig` tempo for a freshly seeded project must be 120 for the 4000ms expectation. If `addSection` seeds a different tempo, set it first via the store's tempo setter (read `songwriter_store.dart` — e.g. `store.setTempo(120)`).

- [ ] **Step 5: Implement the controller**

Create `lib/store/songwriter_stretch_controller.dart`:

```dart
/// Orchestrates pitch-preserving stretch re-rendering for audio clips.
library;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../schema/rules/audio_stretch_rules.dart';
import '../schema/rules/songwriter_stretch_rules.dart';
import 'song_audio_repository.dart';
import 'songwriter_store.dart';

/// Clip ids currently being (re)rendered.
final songwriterStretchProcessingProvider =
    StateProvider<Set<String>>((ref) => <String>{});

class SongwriterStretchController {
  SongwriterStretchController(this.ref);
  final Ref ref;

  /// (Re)renders the stretched derived asset for [clipId] sized to its bar span.
  /// No-op for unplaced clips or non-stretch clips.
  Future<void> rerender(String clipId) async {
    final project = ref.read(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final targetMs = stretchTargetMs(project, clipId);
    if (targetMs == null || targetMs <= 0) return;

    final source =
        project.audioAssets.where((a) => a.id == clip.assetId).firstOrNull;
    if (source == null) return;

    final processing = ref.read(songwriterStretchProcessingProvider.notifier);
    processing.update((s) => {...s, clipId});
    try {
      final repo = ref.read(songwriterAudioRepositoryProvider);
      final all = await repo.readInt16Samples(source.id, source.format);
      final sr = source.sampleRate;
      final from = (clip.trimStartMs * sr ~/ 1000).clamp(0, all.length);
      final to = (clip.trimEndMs * sr ~/ 1000).clamp(from, all.length);
      final region = all.sublist(from, to);
      final stretched =
          await compute(runStretch, StretchRequest(region, sr, targetMs));
      final asset = await repo.writeStretched(samples: stretched, sampleRate: sr);
      // Replace any previous derived asset + its file.
      final prev = clip.stretchedAssetId;
      if (prev != null) await repo.delete(prev);
      ref.read(songwriterProvider.notifier).setClipStretchedAsset(
            clipId: clipId, stretchedAsset: asset, removeAssetId: prev);
    } finally {
      processing.update((s) => {...s}..remove(clipId));
    }
  }
}

final songwriterStretchControllerProvider =
    Provider<SongwriterStretchController>(
        (ref) => SongwriterStretchController(ref));
```

> `compute` requires a top-level function (`runStretch`) and sendable args; `StretchRequest` holds only typed-data + ints, which are sendable. In a widget-test (no real isolate issues for small inputs) `compute` runs fine.

- [ ] **Step 6: Run controller test to verify it passes**

Run: `flutter test test/store/songwriter_stretch_controller_test.dart`
Expected: PASS — `stretchedAssetId` set, derived duration ≈ 4000ms, processing set emptied.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format lib/store/songwriter_stretch_controller.dart lib/store/songwriter_store.dart test/store/songwriter_stretch_controller_test.dart
flutter analyze lib/store/songwriter_stretch_controller.dart lib/store/songwriter_store.dart
git add lib/store/songwriter_stretch_controller.dart lib/store/songwriter_store.dart test/store/songwriter_stretch_controller_test.dart
git commit -m "feat(songwriter): stretch re-render controller + processing state"
```

---

### Task 4: Clip editor sheet

**Files:**
- Create: `lib/features/songwriter/songwriter_audio_clip_sheet.dart`
- Modify: `lib/features/songwriter/songwriter_audio_lane_row.dart` (open editor on tap)
- Test: `test/features/songwriter/songwriter_audio_clip_sheet_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/songwriter/songwriter_audio_clip_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_clip_sheet.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  testWidgets('fit toggle updates the clip fit mode', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = c.read(songwriterProvider).sections.single.lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio).id;
    store.loadProject(c.read(songwriterProvider).copyWith(audioAssets: const [
      AudioAsset(id: 'a1', durationMs: 4000, sampleRate: 44100, channels: 1,
          format: 'wav', peaks: [10, 20, 30], sourceLabel: 'r'),
    ]));
    final clipId = store.addAudioClip(assetId: 'a1', durationMs: 4000);
    store.addAudioBlock(sectionId: sectionId, laneId: laneId,
        audioClipId: clipId, startBar: 0, spanBars: 2);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: SongwriterAudioClipBody(
        sectionId: sectionId, laneId: laneId, clipId: clipId))),
    ));

    await tester.tap(find.byKey(const Key('clipFit_oneShot')));
    await tester.pump();
    expect(c.read(songwriterProvider).audioClips.single.fitMode,
        AudioFitMode.oneShot);
  });
}
```

- [ ] **Step 2: Run + fail**

Run: `flutter test test/features/songwriter/songwriter_audio_clip_sheet_test.dart` → FAIL (`SongwriterAudioClipBody` undefined).

- [ ] **Step 3: Implement the editor**

Create `lib/features/songwriter/songwriter_audio_clip_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../store/songwriter_stretch_controller.dart';
import '../../theme/muzician_theme.dart';
import '../song/song_audio_clip_body.dart';
import 'drum_pattern_sheet.dart' show showWidgetSheet; // sheet launcher
import 'songwriter_audio_lane_row.dart' show fitGlyph;

Future<void> showSongwriterAudioClipSheet({
  required BuildContext context,
  required String sectionId,
  required String laneId,
  required String clipId,
}) =>
    showWidgetSheet(
      context: context,
      title: 'Audio Clip',
      child: SongwriterAudioClipBody(
          sectionId: sectionId, laneId: laneId, clipId: clipId),
    );

class SongwriterAudioClipBody extends ConsumerWidget {
  const SongwriterAudioClipBody({
    super.key,
    required this.sectionId,
    required this.laneId,
    required this.clipId,
  });
  final String sectionId;
  final String laneId;
  final String clipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return const SizedBox.shrink();
    final asset =
        project.audioAssets.where((a) => a.id == clip.assetId).firstOrNull;
    final section =
        project.sections.where((s) => s.id == sectionId).firstOrNull;
    final block = section?.lanes
        .where((l) => l.id == laneId)
        .expand((l) => l.blocks)
        .where((b) => b.audioClipId == clipId)
        .firstOrNull;
    if (asset == null || section == null || block == null) {
      return const SizedBox.shrink();
    }
    final store = ref.read(songwriterProvider.notifier);
    final maxSpan = (section.lengthBars - 1).clamp(1, section.lengthBars);

    void rerenderIfStretch() {
      if (ref.read(songwriterProvider).audioClips
          .firstWhere((c) => c.id == clipId)
          .fitMode == AudioFitMode.stretch) {
        ref.read(songwriterStretchControllerProvider).rerender(clipId);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Waveform + trim handles.
        SizedBox(
          height: 80,
          child: _TrimWaveform(
            asset: asset,
            clip: clip,
            onTrim: (startMs, endMs) {
              store.setClipTrim(
                  clipId: clipId, trimStartMs: startMs, trimEndMs: endMs);
              rerenderIfStretch();
            },
          ),
        ),
        const SizedBox(height: 16),
        // Fit-mode toggle.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final mode in AudioFitMode.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ChoiceChip(
                key: Key('clipFit_${mode.name}'),
                avatar: Icon(fitGlyph(mode), size: 16),
                label: Text(mode.name),
                selected: clip.fitMode == mode,
                onSelected: (_) {
                  store.setClipFitMode(clipId: clipId, fitMode: mode);
                  if (mode == AudioFitMode.stretch) {
                    ref.read(songwriterStretchControllerProvider).rerender(clipId);
                  }
                },
              ),
            ),
        ]),
        const SizedBox(height: 16),
        // Span stepper (1..section-1).
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            key: const ValueKey('clipSpanMinus'),
            icon: const Icon(Icons.remove),
            onPressed: () {
              store.setBlockPlacement(
                  sectionId: sectionId, laneId: laneId, blockId: block.id,
                  startBar: block.startBar,
                  spanBars: (block.spanBars - 1).clamp(1, maxSpan));
              rerenderIfStretch();
            },
          ),
          Text('${block.spanBars} bar(s)',
              style: const TextStyle(color: MuzicianTheme.textPrimary)),
          IconButton(
            key: const ValueKey('clipSpanPlus'),
            icon: const Icon(Icons.add),
            onPressed: () {
              store.setBlockPlacement(
                  sectionId: sectionId, laneId: laneId, blockId: block.id,
                  startBar: block.startBar,
                  spanBars: (block.spanBars + 1).clamp(1, maxSpan));
              rerenderIfStretch();
            },
          ),
        ]),
        if (ref.watch(songwriterStretchProcessingProvider).contains(clipId))
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Stretching…',
                  style: TextStyle(color: MuzicianTheme.textSecondary)),
            ]),
          ),
      ]),
    );
  }
}

/// Waveform with two draggable trim handles. Reports ms bounds on drag end.
class _TrimWaveform extends StatefulWidget {
  const _TrimWaveform(
      {required this.asset, required this.clip, required this.onTrim});
  final AudioAsset asset;
  final AudioClip clip;
  final void Function(int startMs, int endMs) onTrim;

  @override
  State<_TrimWaveform> createState() => _TrimWaveformState();
}

class _TrimWaveformState extends State<_TrimWaveform> {
  late double _start = widget.clip.trimStartMs / widget.asset.durationMs;
  late double _end =
      (widget.clip.trimEndMs == 0 ? widget.asset.durationMs : widget.clip.trimEndMs) /
          widget.asset.durationMs;

  void _commit() => widget.onTrim(
        (_start * widget.asset.durationMs).round(),
        (_end * widget.asset.durationMs).round(),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      return Stack(children: [
        Positioned.fill(
          child: AudioClipBody(
            name: widget.asset.sourceLabel,
            durationMs: widget.asset.durationMs,
            format: widget.asset.format,
            peaks: widget.asset.peaks,
            isBroken: false,
          ),
        ),
        _handle(w, _start, const Key('clipTrimStart'), (dx) {
          setState(() => _start = (dx / w).clamp(0.0, _end - 0.02));
        }),
        _handle(w, _end, const Key('clipTrimEnd'), (dx) {
          setState(() => _end = (dx / w).clamp(_start + 0.02, 1.0));
        }),
      ]);
    });
  }

  Widget _handle(double w, double frac, Key key, void Function(double dx) onDx) {
    return Positioned(
      left: (frac * w - 8).clamp(0.0, w - 16),
      top: 0,
      bottom: 0,
      child: GestureDetector(
        key: key,
        onHorizontalDragUpdate: (d) => onDx((frac * w) + d.delta.dx),
        onHorizontalDragEnd: (_) => _commit(),
        child: Container(
          width: 16,
          alignment: Alignment.center,
          child: Container(width: 3, color: MuzicianTheme.sky),
        ),
      ),
    );
  }
}
```

> `showWidgetSheet` is defined in `drum_pattern_sheet.dart`; if it is private there, read that file and use the actual exported sheet helper (e.g. a shared `lib/ui/` sheet function). The test drives `SongwriterAudioClipBody` directly, so the launcher is not on the test path.

- [ ] **Step 4: Open the editor from the lane tile**

In `lib/features/songwriter/songwriter_audio_lane_row.dart`, change the clip tile's `onTap` from the interim `_tileMenu` to:

```dart
            onTap: () => showSongwriterAudioClipSheet(
              context: context,
              sectionId: section.id,
              laneId: lane.id,
              clipId: owner.audioClipId!,
            ),
```

Add `import 'songwriter_audio_clip_sheet.dart';`. Keep `_tileMenu` only if you still want a long-press delete; otherwise remove it and its references to avoid dead code (the editor now hosts fit/span; add a Delete button there if desired).

- [ ] **Step 5: Run the widget test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_audio_clip_sheet_test.dart`
Expected: PASS — tapping the one-shot chip sets `fitMode == oneShot`.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/features/songwriter/songwriter_audio_clip_sheet.dart lib/features/songwriter/songwriter_audio_lane_row.dart test/features/songwriter/songwriter_audio_clip_sheet_test.dart
flutter analyze lib/features/songwriter
git add lib/features/songwriter/songwriter_audio_clip_sheet.dart lib/features/songwriter/songwriter_audio_lane_row.dart test/features/songwriter/songwriter_audio_clip_sheet_test.dart
git commit -m "feat(songwriter): audio clip editor — trim, span, fit, stretch trigger"
```

---

### Task 5: Tempo-change re-render + processing badge on the tile

**Files:**
- Modify: `lib/store/songwriter_stretch_controller.dart` (a tempo listener provider)
- Modify: `lib/features/songwriter/songwriter_audio_lane_row.dart` (badge)

- [ ] **Step 1: Re-render all stretch clips when tempo changes**

Add to `lib/store/songwriter_stretch_controller.dart`:

```dart
/// Watches the project tempo and re-renders every stretch clip when it changes.
/// Instantiate once (e.g. `ref.watch(songwriterStretchTempoWatcherProvider)` in
/// the songwriter screen) so the listener is alive while the tab is open.
final songwriterStretchTempoWatcherProvider = Provider<void>((ref) {
  ref.listen<int>(
    songwriterProvider.select((p) => p.config.tempo),
    (prev, next) {
      if (prev == null || prev == next) return;
      final controller = ref.read(songwriterStretchControllerProvider);
      for (final clip in ref.read(songwriterProvider).audioClips) {
        if (clip.fitMode == AudioFitMode.stretch) {
          controller.rerender(clip.id);
        }
      }
    },
  );
});
```

In `lib/features/songwriter/songwriter_screen_sheet.dart`, in the top-level build of the sheet/screen widget, add `ref.watch(songwriterStretchTempoWatcherProvider);` so the watcher is mounted. (Read the screen's `build` and add the line near the other `ref.watch` calls.)

- [ ] **Step 2: Show the processing badge on the tile**

In `songwriter_audio_lane_row.dart`, in the clip-tile `Stack`, add after the fit glyph:

```dart
                if (ref.watch(songwriterStretchProcessingProvider)
                    .contains(owner.audioClipId))
                  const Positioned(
                    left: 4, top: 2,
                    child: SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.6)),
                  ),
```

Add `import '../../store/songwriter_stretch_controller.dart';`.

- [ ] **Step 3: Analyze, run songwriter widget + store tests, commit**

```bash
flutter test test/features/songwriter/ test/store/songwriter_stretch_controller_test.dart
dart format lib/store/songwriter_stretch_controller.dart lib/features/songwriter/songwriter_audio_lane_row.dart lib/features/songwriter/songwriter_screen_sheet.dart
flutter analyze lib/features/songwriter lib/store/songwriter_stretch_controller.dart
git add lib/store/songwriter_stretch_controller.dart lib/features/songwriter/songwriter_audio_lane_row.dart lib/features/songwriter/songwriter_screen_sheet.dart
git commit -m "feat(songwriter): tempo-driven stretch re-render + processing badge"
```

---

### Task 6: Verification gate

- [ ] **Step 1: Full P4 test set**

Run:
```bash
flutter test \
  test/schema/rules/audio_stretch_rules_test.dart \
  test/store/song_audio_repository_stretch_test.dart \
  test/schema/rules/songwriter_stretch_rules_test.dart \
  test/store/songwriter_stretch_controller_test.dart \
  test/features/songwriter/
```
Expected: all PASS.

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/schema/rules lib/store lib/features/songwriter`
Expected: no new issues.

- [ ] **Step 3: Device smoke — stretch fidelity**

Record a ~3s chord strum → set fit = stretch → set span to 2 bars → editor shows "Stretching…" then plays back filling 2 bars **at the original pitch** (verify chords are not detuned). Change project tempo → clip re-renders to match. Trim the head/tail → re-renders. Confirm loop/one-shot clips still play without re-render.

---

## Self-Review

**Spec coverage (P4 = M6 stretch + the M4 editor):** WSOLA pitch-preserving stretch ✓ (T1); off-thread via `compute` ✓ (T5/controller); derived asset write + source read ✓ (T2); target-ms from span × tempo ✓ (T3); re-render on trim/span/mode ✓ (T4) and tempo ✓ (T5); processing badge ✓ (T4 sheet + T5 tile); editor with trim handles + span stepper + fit toggle ✓ (T4); length cap (note: enforce ≤30 s by disabling stretch when `source.durationMs > 30000` — add the guard in the controller's `rerender` and grey the stretch chip when over cap; spec Risk 1). Audition: the editor relies on transport playback for now — a dedicated in-sheet audition button can reuse `songwriterAudioClipSinkProvider`; add it if device testing shows it is needed.

**Placeholder scan:** No "TBD". Notes about `showWidgetSheet` visibility, default tempo, and `_tileMenu` cleanup carry concrete instructions/fallbacks.

**Type consistency:** `stretchInt16`/`runStretch`/`StretchRequest` (T1) used verbatim by the controller (T5). `writeStretched`/`readInt16Samples`/`extractInt16Samples` (T2) match controller calls. `stretchTargetMs`/`audioClipSpanBars` (T3) match controller usage. `setClipStretchedAsset` (T3) signature matches the controller call. `songwriterStretchControllerProvider`/`songwriterStretchProcessingProvider`/`songwriterStretchTempoWatcherProvider` consistent across T3–T5 and the editor. `fitGlyph` imported from Plan 2's lane row.
