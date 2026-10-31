# Piano Roll Hum Accuracy, Web/Desktop Hum, and Selectable Sound Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Hum-to-MIDI more accurate, enable it on web and desktop, and let each piano roll choose its playback sound.

**Architecture:** Pitch analysis stays pure Dart in `lib/schema/rules/mono_pitch_rules.dart`; a new pure `HumPcmFramer` turns PCM bytes into `PitchFrame`s so the whole pipeline is testable with synthetic signals (no microphone). The sound is a `PianoRollSound` value held in `PianoRollState`, persisted in `PianoRollSnapshot`, and read by the playback sink and grid auditions.

**Tech Stack:** Flutter, Riverpod, `record` 6.2.1 (already supports web/macOS/Linux/Windows), `audioplayers`, `flutter_test`.

Spec: `docs/superpowers/specs/2026-10-31-piano-roll-hum-accuracy-sound-design.md`

**Spec deltas found while planning (the plan wins):**
- A `windows/` runner **does** exist (and `record_windows` is locked), so Windows is included; no extra permission file is needed there.
- The `record` web worklet already resamples to the requested 16 kHz (`record.worklet.js` builds a `Resampler(contextRate, requestedRate)`), so the session keeps requesting 16 kHz and no sample-rate plumbing is needed.
- The octave guard is done by a 5-frame median over frame frequencies (`smoothPitchFrames`), not inside YIN: YIN already takes the first dip under threshold, and a per-window "fix" cannot tell an octave error from a real octave.
- Concrete latency bug found: when a pitch change commits after `switchFrames` frames, the new note's start is the *commit* frame, not the first frame of the new pitch. Task 4 back-dates it.
- The playback sink typedef is **not** changed (many tests override it); the default sink reads the sound from `pianoRollProvider` at call time.

## File Structure

| File | Responsibility |
|---|---|
| `lib/schema/rules/mono_pitch_rules.dart` (modify) | `analyzeHumWindow`, `NoiseFloorTracker`, `smoothPitchFrames`, segmenter fixes, tuning field `reattackGapMs` |
| `lib/utils/hum_pcm_framer.dart` (create) | Pure PCM16 bytes → `PitchFrame` list (window 1024, hop 256, adaptive gate) |
| `lib/utils/mic_pitch_session.dart` (modify) | Thin `record` wrapper that feeds `HumPcmFramer` |
| `lib/store/hum_to_midi_store.dart` (modify) | Catch unsupported/failed microphone start |
| `lib/features/piano_roll/piano_roll_hum_recorder.dart` (modify) | Remove web gate |
| `macos/Runner/*.entitlements`, `macos/Runner/Info.plist` (modify) | Microphone permission |
| `lib/models/piano_roll.dart` (modify) | `PianoRollSound`, `PianoRollState.sound` |
| `lib/models/save_system.dart` (modify) | `PianoRollSnapshot.sound` |
| `lib/store/piano_roll_store.dart` (modify) | `setSound`, load restores sound |
| `lib/store/save_system_store.dart` (modify) | Keep sound when project config rewrites a snapshot |
| `lib/features/piano_roll/piano_roll_save_panel.dart` (modify) | Capture sound |
| `lib/utils/timbre_synth.dart` (create) | Organ / synth lead / bell sample renderers |
| `lib/utils/note_player.dart` (modify) | `previewTimbre(PianoRollSound, midi)` |
| `lib/store/piano_roll_playback_store.dart` (modify) | Default sink uses the roll's sound |
| `lib/features/piano_roll/piano_roll_grid.dart` (modify) | Auditions use the roll's sound |
| `lib/features/piano_roll/piano_roll_screen_v2.dart` (modify) | Sound picker in Roll Settings |
| `test/support/hum_signal.dart` (create) | Synthetic hum signal helpers |
| `docs/piano_roll.md`, `README.md` (modify) | Documentation |

Commands run from the repo root `/Users/francescolacriola/dev/ws/muzician`. Unrelated uncommitted changes exist in the tree (`lib/profile_writer_playback.dart`, `macos/Podfile*`, `macos/Runner.xcodeproj`, `test/profile_writer_playback_fixture_test.dart`): **never `git add -A`**; add only the files each task lists.

---

### Task 1: Synthetic signal helper and `analyzeHumWindow`

**Files:**
- Create: `test/support/hum_signal.dart`
- Modify: `lib/schema/rules/mono_pitch_rules.dart` (append after `estimateDominantFrequencyFromSamples`)
- Test: `test/schema/rules/mono_pitch_rules_test.dart`

- [ ] **Step 1: Create the helper**

```dart
import 'dart:math';
import 'dart:typed_data';

/// One hum-like note: fundamental plus a weaker 2nd harmonic, with a short
/// attack/release so onsets are not clicks.
class HumNote {
  final double frequencyHz;
  final int startMs;
  final int endMs;
  final double amplitude;
  const HumNote(
    this.frequencyHz,
    this.startMs,
    this.endMs, {
    this.amplitude = 0.3,
  });
}

/// Renders [notes] plus uniform noise of peak [noiseAmplitude] as mono floats.
Float64List renderHum(
  List<HumNote> notes, {
  required int totalMs,
  int sampleRate = 16000,
  double noiseAmplitude = 0,
  int seed = 7,
}) {
  final random = Random(seed);
  final out = Float64List(totalMs * sampleRate ~/ 1000);
  for (var i = 0; i < out.length; i++) {
    out[i] = (random.nextDouble() * 2 - 1) * noiseAmplitude;
  }
  for (final note in notes) {
    final from = note.startMs * sampleRate ~/ 1000;
    final to = min(out.length, note.endMs * sampleRate ~/ 1000);
    const ramp = 160; // 10 ms at 16 kHz
    for (var i = from; i < to; i++) {
      final t = (i - from) / sampleRate;
      final edge = min(min((i - from) / ramp, (to - i) / ramp), 1.0);
      final v =
          sin(2 * pi * note.frequencyHz * t) +
          0.5 * sin(2 * pi * note.frequencyHz * 2 * t);
      out[i] += v / 1.5 * note.amplitude * edge;
    }
  }
  return out;
}

Uint8List toPcm16(Float64List samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(
      i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

double midiToHz(int midi) => 440.0 * pow(2, (midi - 69) / 12);
```

- [ ] **Step 2: Write the failing test** (add inside `group('mono pitch rules', ...)`, plus `import '../../support/hum_signal.dart';` at the top)

```dart
    test('analyzeHumWindow reports pitch for a tone and silence below the gate', () {
      final tone = renderHum([HumNote(midiToHz(60), 0, 100)], totalMs: 100);
      final voiced = rules.analyzeHumWindow(
        tone.sublist(0, 1024),
        sampleRate: 16000,
        timestampMs: 0,
        gate: 0.02,
      );
      expect(voiced.midiNote, 60);
      expect(voiced.isSilence, isFalse);
      expect(voiced.confidence, greaterThan(0.6));

      final quiet = rules.analyzeHumWindow(
        tone.sublist(0, 1024).map((s) => s * 0.01).toList(),
        sampleRate: 16000,
        timestampMs: 32,
        gate: 0.02,
      );
      expect(quiet.isSilence, isTrue);
      expect(quiet.midiNote, isNull);
      expect(quiet.timestampMs, 32);
    });
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/schema/rules/mono_pitch_rules_test.dart`
Expected: FAIL, `analyzeHumWindow` isn't defined.

- [ ] **Step 4: Implement**

```dart
/// Analyses one window into a [PitchFrame]. Peak amplitude below [gate] is
/// silence and skips pitch estimation.
PitchFrame analyzeHumWindow(
  List<double> window, {
  required int sampleRate,
  required int timestampMs,
  required double gate,
}) {
  var peak = 0.0;
  for (final sample in window) {
    final v = sample.abs();
    if (v > peak) peak = v;
  }
  if (peak < gate) {
    return PitchFrame(
      timestampMs: timestampMs,
      frequencyHz: 0,
      midiNote: null,
      centsOffset: 0,
      amplitude: peak,
      confidence: 0,
      isSilence: true,
    );
  }
  final estimate = estimateDominantFrequencyFromSamples(
    window,
    sampleRate: sampleRate,
  );
  final midi = estimate == null ? null : frequencyToMidi(estimate.frequencyHz);
  return PitchFrame(
    timestampMs: timestampMs,
    frequencyHz: estimate?.frequencyHz ?? 0,
    midiNote: midi,
    centsOffset: 0,
    amplitude: peak,
    confidence: estimate?.confidence ?? 0,
    isSilence: midi == null,
  );
}
```

- [ ] **Step 5: Run to verify pass**, same command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/support/hum_signal.dart lib/schema/rules/mono_pitch_rules.dart test/schema/rules/mono_pitch_rules_test.dart
git commit -m "feat(hum): add analyzeHumWindow and synthetic hum test signals" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Adaptive noise floor

**Files:**
- Modify: `lib/schema/rules/mono_pitch_rules.dart`
- Test: `test/schema/rules/mono_pitch_rules_test.dart`

- [ ] **Step 1: Failing tests**

```dart
    group('NoiseFloorTracker', () {
      test('starts at the minimum gate', () {
        expect(rules.NoiseFloorTracker().gate, rules.minHumAmplitude);
      });

      test('raises the gate from unpitched noise and caps it', () {
        final tracker = rules.NoiseFloorTracker();
        for (var i = 0; i < 400; i++) {
          tracker.update(0.05, pitched: false);
        }
        expect(tracker.gate, greaterThan(0.1));
        expect(tracker.gate, lessThanOrEqualTo(rules.maxHumGate));
      });

      test('does not learn from pitched frames', () {
        final tracker = rules.NoiseFloorTracker();
        for (var i = 0; i < 400; i++) {
          tracker.update(0.5, pitched: true);
        }
        expect(tracker.gate, rules.minHumAmplitude);
      });

      test('falls immediately when the room goes quiet', () {
        final tracker = rules.NoiseFloorTracker();
        for (var i = 0; i < 400; i++) {
          tracker.update(0.05, pitched: false);
        }
        tracker.update(0.0, pitched: false);
        expect(tracker.gate, rules.minHumAmplitude);
      });
    });
```

- [ ] **Step 2: Run to verify failure** (`flutter test test/schema/rules/mono_pitch_rules_test.dart`): FAIL, undefined `NoiseFloorTracker` / `maxHumGate`.

- [ ] **Step 3: Implement** (next to the constants and class)

```dart
const maxHumGate = 0.12;

/// Tracks the ambient noise floor from frames that carry no stable pitch, so
/// the silence gate rises in noisy rooms but never learns from the hum itself.
class NoiseFloorTracker {
  NoiseFloorTracker({this.riseRate = 0.02, this.multiplier = 2.5});

  final double riseRate;
  final double multiplier;
  double _floor = 0;

  double get gate => (_floor * multiplier).clamp(minHumAmplitude, maxHumGate);

  void update(double amplitude, {required bool pitched}) {
    if (pitched) return;
    if (amplitude <= _floor) {
      _floor = amplitude;
    } else {
      _floor += (amplitude - _floor) * riseRate;
    }
  }
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/mono_pitch_rules.dart test/schema/rules/mono_pitch_rules_test.dart
git commit -m "feat(hum): add adaptive noise floor tracker" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Pitch smoothing (octave and blip guard)

**Files:**
- Modify: `lib/schema/rules/mono_pitch_rules.dart`
- Test: `test/schema/rules/mono_pitch_rules_test.dart`

- [ ] **Step 1: Failing tests**

```dart
    group('smoothPitchFrames', () {
      PitchFrame voiced(int ts, double hz) => PitchFrame(
        timestampMs: ts,
        frequencyHz: hz,
        midiNote: rules.frequencyToMidi(hz),
        centsOffset: 0,
        amplitude: 0.5,
        confidence: 0.9,
        isSilence: false,
      );

      test('replaces an isolated octave error with the neighbourhood median', () {
        final frames = [
          voiced(0, 440),
          voiced(16, 440),
          voiced(32, 880),
          voiced(48, 440),
          voiced(64, 440),
        ];
        final smoothed = rules.smoothPitchFrames(frames);
        expect(smoothed.map((f) => f.midiNote), everyElement(69));
      });

      test('keeps a real, sustained pitch change', () {
        final frames = [
          for (var i = 0; i < 5; i++) voiced(i * 16, 440),
          for (var i = 5; i < 10; i++) voiced(i * 16, 523.25),
        ];
        final smoothed = rules.smoothPitchFrames(frames);
        expect(smoothed[0].midiNote, 69);
        expect(smoothed[9].midiNote, 72);
      });

      test('leaves frames with fewer than three voiced neighbours alone', () {
        final frames = [voiced(0, 440), voiced(16, 880)];
        final smoothed = rules.smoothPitchFrames(frames);
        expect(smoothed[1].midiNote, 81);
      });
    });
```

- [ ] **Step 2: Run, expect FAIL** (undefined).

- [ ] **Step 3: Implement**

```dart
/// 5-frame median over the frequency of voiced frames. Removes isolated octave
/// errors and one-frame glitches without delaying real pitch changes.
List<PitchFrame> smoothPitchFrames(List<PitchFrame> frames) {
  bool isVoiced(PitchFrame f) =>
      !f.isSilence && f.midiNote != null && f.frequencyHz > 0;
  final out = List<PitchFrame>.of(frames);
  for (var i = 0; i < frames.length; i++) {
    if (!isVoiced(frames[i])) continue;
    final neighbourhood = <double>[];
    for (var j = i - 2; j <= i + 2; j++) {
      if (j < 0 || j >= frames.length) continue;
      if (isVoiced(frames[j])) neighbourhood.add(frames[j].frequencyHz);
    }
    if (neighbourhood.length < 3) continue;
    neighbourhood.sort();
    final median = neighbourhood[neighbourhood.length ~/ 2];
    final midi = frequencyToMidi(median);
    if (midi == null) continue;
    final f = frames[i];
    out[i] = PitchFrame(
      timestampMs: f.timestampMs,
      frequencyHz: median,
      midiNote: midi,
      centsOffset: f.centsOffset,
      amplitude: f.amplitude,
      confidence: f.confidence,
      isSilence: false,
    );
  }
  return out;
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/mono_pitch_rules.dart test/schema/rules/mono_pitch_rules_test.dart
git commit -m "feat(hum): smooth frame pitch with a 5-frame median" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Segmenter: back-dated switches, re-attack splits, smoothing

**Files:**
- Modify: `lib/schema/rules/mono_pitch_rules.dart` (`HumSensitivityTuning`, `segmentStableNotes`)
- Test: `test/schema/rules/mono_pitch_rules_test.dart`

- [ ] **Step 1: Failing tests** (reuse a top-level `voiced`/`silent` helper; add them above `main()` if not in scope)

```dart
PitchFrame _v(int ts, double hz, {double amp = 0.5}) => PitchFrame(
  timestampMs: ts,
  frequencyHz: hz,
  midiNote: rules.frequencyToMidi(hz),
  centsOffset: 0,
  amplitude: amp,
  confidence: 0.95,
  isSilence: false,
);

PitchFrame _s(int ts) => PitchFrame(
  timestampMs: ts,
  frequencyHz: 0,
  midiNote: null,
  centsOffset: 0,
  amplitude: 0,
  confidence: 0,
  isSilence: true,
);
```

```dart
    group('segmentStableNotes accuracy', () {
      test('a committed pitch change starts at its first frame', () {
        // 16 ms frames: A4 for 400 ms then C5; strict commits after 2 frames.
        final frames = [
          for (var ts = 0; ts < 400; ts += 16) _v(ts, 440),
          for (var ts = 400; ts < 800; ts += 16) _v(ts, 523.25),
        ];
        final notes = rules.segmentStableNotes(frames);
        expect(notes.map((n) => n.midiNote), [69, 72]);
        expect(notes[1].startMs, 400);
        expect(notes[0].endMs, lessThanOrEqualTo(400));
      });

      test('a silent gap between same-pitch notes splits them', () {
        final frames = [
          for (var ts = 0; ts < 300; ts += 16) _v(ts, 440),
          for (var ts = 300; ts < 480; ts += 16) _s(ts),
          for (var ts = 480; ts < 800; ts += 16) _v(ts, 440),
        ];
        final notes = rules.segmentStableNotes(frames);
        expect(notes, hasLength(2));
        expect(notes[1].startMs, 480);
      });

      test('a dropout shorter than the re-attack gap is bridged', () {
        final frames = [
          for (var ts = 0; ts < 300; ts += 16) _v(ts, 440),
          for (var ts = 300; ts < 332; ts += 16) _s(ts),
          for (var ts = 332; ts < 700; ts += 16) _v(ts, 440),
        ];
        expect(rules.segmentStableNotes(frames), hasLength(1));
      });

      test('forgiving never splits on gaps', () {
        final frames = [
          for (var ts = 0; ts < 300; ts += 16) _v(ts, 440),
          for (var ts = 300; ts < 440; ts += 16) _s(ts),
          for (var ts = 440; ts < 800; ts += 16) _v(ts, 440),
        ];
        final notes = rules.segmentStableNotes(
          frames,
          sensitivity: rules.HumSensitivity.forgiving,
        );
        expect(notes, hasLength(1));
      });

      test('an isolated octave glitch does not create notes', () {
        final frames = [
          for (var ts = 0; ts < 400; ts += 16) _v(ts, ts == 192 ? 880 : 440),
        ];
        final notes = rules.segmentStableNotes(frames);
        expect(notes, hasLength(1));
        expect(notes.single.midiNote, 69);
      });
    });
```

- [ ] **Step 2: Run, expect FAIL** (back-dating and gap split tests; the existing tests must still pass).

- [ ] **Step 3: Add `reattackGapMs` to the tuning**

Replace the `HumSensitivityTuning` class body/presets with:

```dart
class HumSensitivityTuning {
  final int switchFrames;
  final int deadbandCents;
  final int minNoteMs;

  /// Unvoiced gap (ms, between the last and next voiced frame, excluding one
  /// frame span) at which two same-pitch notes are split instead of bridged.
  final int reattackGapMs;
  const HumSensitivityTuning({
    required this.switchFrames,
    required this.deadbandCents,
    required this.minNoteMs,
    required this.reattackGapMs,
  });

  static const _strict = HumSensitivityTuning(
    switchFrames: 2,
    deadbandCents: 0,
    minNoteMs: 80,
    reattackGapMs: 70,
  );
  static const _balanced = HumSensitivityTuning(
    switchFrames: 4,
    deadbandCents: 35,
    minNoteMs: 120,
    reattackGapMs: 100,
  );
  static const _forgiving = HumSensitivityTuning(
    switchFrames: 7,
    deadbandCents: 60,
    minNoteMs: 180,
    reattackGapMs: 1 << 30,
  );

  static HumSensitivityTuning of(HumSensitivity sensitivity) =>
      switch (sensitivity) {
        HumSensitivity.strict => _strict,
        HumSensitivity.balanced => _balanced,
        HumSensitivity.forgiving => _forgiving,
      };
}
```

- [ ] **Step 4: Replace `segmentStableNotes`** with:

```dart
List<DetectedMonoNote> segmentStableNotes(
  List<PitchFrame> frames, {
  HumSensitivity sensitivity = HumSensitivity.strict,
}) {
  if (frames.isEmpty) return const [];

  final tuning = HumSensitivityTuning.of(sensitivity);
  final smoothed = smoothPitchFrames(frames);
  final frameSpanMs = _estimateMedianFrameSpanMs(smoothed);

  final notes = <DetectedMonoNote>[];
  int? activeMidi;
  int? startMs;
  double confidenceTotal = 0;
  int confidenceCount = 0;
  // Last frame that matched the active pitch; ends the note.
  int lastActiveMs = smoothed.first.timestampMs;
  // Last voiced frame of any pitch; measures silent gaps.
  int lastVoicedMs = smoothed.first.timestampMs;
  int? pendingMidi;
  int? pendingStartMs;
  int pendingFrames = 0;

  void emit() {
    final midi = activeMidi;
    final start = startMs;
    if (midi == null || start == null) return;
    final rawDuration = lastActiveMs - start;
    final duration = rawDuration <= 0 ? frameSpanMs : rawDuration;
    if (duration < tuning.minNoteMs) return;
    notes.add(
      DetectedMonoNote(
        startMs: start,
        endMs: start + duration,
        midiNote: midi,
        confidence: confidenceCount == 0
            ? 0
            : confidenceTotal / confidenceCount,
      ),
    );
  }

  void startNote(int midi, int atMs) {
    activeMidi = midi;
    startMs = atMs;
    lastActiveMs = atMs;
    confidenceTotal = 0;
    confidenceCount = 0;
    pendingMidi = null;
    pendingStartMs = null;
    pendingFrames = 0;
  }

  for (final frame in smoothed) {
    final isVoiced =
        !frame.isSilence &&
        frame.midiNote != null &&
        frame.confidence >= minStableConfidence;
    if (isVoiced) {
      final midi = frame.midiNote!;
      final gapMs = frame.timestampMs - lastVoicedMs - frameSpanMs;
      if (activeMidi != null && gapMs >= tuning.reattackGapMs) {
        emit();
        startNote(midi, frame.timestampMs);
      }
      final active = activeMidi;
      final withinDeadband =
          active != null &&
          midi != active &&
          tuning.deadbandCents > 0 &&
          frame.frequencyHz > 0 &&
          _absCentsFromMidi(frame.frequencyHz, active) <= tuning.deadbandCents;
      if (active == null) {
        startNote(midi, frame.timestampMs);
      } else if (midi != active && !withinDeadband) {
        if (pendingMidi == midi) {
          pendingFrames += 1;
        } else {
          pendingMidi = midi;
          pendingStartMs = frame.timestampMs;
          pendingFrames = 1;
        }
        if (pendingFrames >= tuning.switchFrames) {
          emit();
          startNote(midi, pendingStartMs ?? frame.timestampMs);
          lastActiveMs = frame.timestampMs;
        }
      } else {
        pendingMidi = null;
        pendingStartMs = null;
        pendingFrames = 0;
        lastActiveMs = frame.timestampMs;
      }
      lastVoicedMs = frame.timestampMs;
      confidenceTotal += frame.confidence;
      confidenceCount += 1;
      continue;
    }

    if (activeMidi != null &&
        frame.timestampMs - lastVoicedMs > maxMergeGapMs) {
      emit();
      activeMidi = null;
      startMs = null;
      confidenceTotal = 0;
      confidenceCount = 0;
      pendingMidi = null;
      pendingStartMs = null;
      pendingFrames = 0;
    }
  }

  if (activeMidi != null) {
    emit();
  }

  return notes;
}
```

- [ ] **Step 5: Run the whole file** (`flutter test test/schema/rules/mono_pitch_rules_test.dart`) and `flutter test test/store/hum_to_midi_store_test.dart`. Expected: PASS. If an *old* test fails because a switch now starts earlier, update its expected start to the first frame of the new pitch (that is the intended fix) and say so in the commit message; do not loosen any other assertion.

- [ ] **Step 6: Commit**

```bash
git add lib/schema/rules/mono_pitch_rules.dart test/schema/rules/mono_pitch_rules_test.dart
git commit -m "fix(hum): back-date pitch switches, split on re-attack, smooth pitch" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: `HumPcmFramer` and end-to-end synthetic test

**Files:**
- Create: `lib/utils/hum_pcm_framer.dart`
- Modify: `lib/utils/mic_pitch_session.dart`
- Test: `test/utils/hum_pcm_framer_test.dart`

- [ ] **Step 1: Failing end-to-end tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/schema/rules/mono_pitch_rules.dart' as rules;
import 'package:muzician/utils/hum_pcm_framer.dart';

import '../support/hum_signal.dart';

List<PitchFrame> _frames(
  List<HumNote> notes, {
  required int totalMs,
  double noise = 0,
  int chunkBytes = 1000,
}) {
  final pcm = toPcm16(renderHum(notes, totalMs: totalMs, noiseAmplitude: noise));
  final framer = HumPcmFramer();
  final frames = <PitchFrame>[];
  // Odd chunk size also exercises byte carry-over.
  for (var i = 0; i < pcm.length; i += chunkBytes) {
    final end = i + chunkBytes > pcm.length ? pcm.length : i + chunkBytes;
    frames.addAll(framer.addPcm16(pcm.sublist(i, end)));
  }
  return frames;
}

void main() {
  test('emits a frame every 16 ms with window-start timestamps', () {
    final frames = _frames([HumNote(midiToHz(60), 0, 500)], totalMs: 500);
    expect(frames.first.timestampMs, 0);
    expect(frames[1].timestampMs, 16);
  });

  test('C4 E4 G4 with gaps becomes three notes with accurate onsets', () {
    final notes = [
      HumNote(midiToHz(60), 200, 700),
      HumNote(midiToHz(64), 800, 1300),
      HumNote(midiToHz(67), 1400, 1900),
    ];
    final frames = _frames(notes, totalMs: 2200, chunkBytes: 999);
    final detected = rules.segmentStableNotes(
      frames,
      sensitivity: rules.HumSensitivity.balanced,
    );
    expect(detected.map((n) => n.midiNote), [60, 64, 67]);
    for (var i = 0; i < 3; i++) {
      expect((detected[i].startMs - notes[i].startMs).abs(), lessThan(80));
    }
  });

  test('moderate room noise creates no extra notes', () {
    final notes = [
      HumNote(midiToHz(60), 600, 1100),
      HumNote(midiToHz(64), 1200, 1700),
    ];
    final frames = _frames(notes, totalMs: 2000, noise: 0.04);
    final detected = rules.segmentStableNotes(
      frames,
      sensitivity: rules.HumSensitivity.balanced,
    );
    expect(detected.map((n) => n.midiNote), [60, 64]);
  });

  test('repeated same-pitch notes with a short rest stay separate', () {
    final notes = [
      HumNote(midiToHz(60), 100, 500),
      HumNote(midiToHz(60), 640, 1040),
    ];
    final frames = _frames(notes, totalMs: 1200);
    final detected = rules.segmentStableNotes(
      frames,
      sensitivity: rules.HumSensitivity.balanced,
    );
    expect(detected, hasLength(2));
  });
}
```

- [ ] **Step 2: Run** `flutter test test/utils/hum_pcm_framer_test.dart`. Expected: FAIL (file `hum_pcm_framer.dart` missing).

- [ ] **Step 3: Implement `lib/utils/hum_pcm_framer.dart`**

```dart
import 'dart:typed_data';

import '../models/hum_to_midi.dart';
import '../schema/rules/mono_pitch_rules.dart' as rules;

/// Turns a PCM16 little-endian mono byte stream into [PitchFrame]s using a
/// sliding window. Pure Dart so it is testable without a microphone.
class HumPcmFramer {
  HumPcmFramer({
    this.sampleRate = 16000,
    this.windowSamples = 1024,
    this.hopSamples = 256,
  }) : _ring = Float64List(windowSamples);

  final int sampleRate;
  final int windowSamples;
  final int hopSamples;

  final Float64List _ring;
  final rules.NoiseFloorTracker _noiseFloor = rules.NoiseFloorTracker();
  int _fill = 0;
  int _processedSamples = 0;
  int? _carryByte;

  List<PitchFrame> addPcm16(Uint8List bytes) {
    final frames = <PitchFrame>[];
    var data = bytes;
    final carry = _carryByte;
    if (carry != null && bytes.isNotEmpty) {
      data = Uint8List(bytes.length + 1)
        ..[0] = carry
        ..setRange(1, bytes.length + 1, bytes);
      _carryByte = null;
    }
    final sampleCount = data.lengthInBytes ~/ 2;
    if (data.lengthInBytes.isOdd) _carryByte = data[data.lengthInBytes - 1];
    final view = ByteData.sublistView(data);
    for (var i = 0; i < sampleCount; i++) {
      _ring[_fill++] = view.getInt16(i * 2, Endian.little) / 32768.0;
      if (_fill < windowSamples) continue;
      frames.add(_analyseWindow());
      _ring.setRange(0, windowSamples - hopSamples, _ring, hopSamples);
      _fill = windowSamples - hopSamples;
      _processedSamples += hopSamples;
    }
    return frames;
  }

  PitchFrame _analyseWindow() {
    final frame = rules.analyzeHumWindow(
      _ring,
      sampleRate: sampleRate,
      timestampMs: (_processedSamples * 1000) ~/ sampleRate,
      gate: _noiseFloor.gate,
    );
    _noiseFloor.update(
      frame.amplitude,
      pitched:
          frame.midiNote != null && frame.confidence >= rules.minStableConfidence,
    );
    return frame;
  }
}
```

- [ ] **Step 4: Run.** Expected: PASS. If an onset or noise assertion fails, inspect the frames (print `timestampMs`, `midiNote`, `confidence`, `amplitude`) and fix the algorithm or the helper signal; only widen the 80 ms onset tolerance if the measured error is explained by the 64 ms analysis window (window-start timestamps), and record the measured value in the commit message.

- [ ] **Step 5: Use the framer in `RecordMicPitchSession`.** Replace the file body from the constants through `start()` and delete `_peakAbs`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../models/hum_to_midi.dart';
import 'hum_pcm_framer.dart';

abstract class MicPitchSession {
  Future<bool> hasPermission();
  Future<Stream<PitchFrame>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordMicPitchSession implements MicPitchSession {
  RecordMicPitchSession({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  // The web recorder resamples to the requested rate, so this holds everywhere.
  static const _sampleRate = 16000;

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _pcmSub;
  StreamController<PitchFrame>? _controller;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<PitchFrame>> start() async {
    final pcmStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    final controller = StreamController<PitchFrame>();
    _controller = controller;
    final framer = HumPcmFramer(sampleRate: _sampleRate);

    _pcmSub = pcmStream.listen(
      (bytes) {
        for (final frame in framer.addPcm16(bytes)) {
          if (!controller.isClosed) controller.add(frame);
        }
      },
      onError: controller.addError,
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: false,
    );

    return controller.stream;
  }
```

Keep `stop()` and `dispose()` exactly as they are. (Remove the `mono_pitch_rules` import; it is no longer used here.)

- [ ] **Step 6: Run** `flutter analyze lib/utils` and `flutter test test/utils/hum_pcm_framer_test.dart test/store/hum_to_midi_store_test.dart`. Expected: no issues, PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/utils/hum_pcm_framer.dart lib/utils/mic_pitch_session.dart test/utils/hum_pcm_framer_test.dart
git commit -m "feat(hum): frame PCM with a 16 ms hop and adaptive noise gate" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Hum on web and desktop

**Files:**
- Modify: `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- Modify: `lib/store/hum_to_midi_store.dart`
- Modify: `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`, `macos/Runner/Info.plist`
- Test: `test/features/piano_roll/piano_roll_screen_v2_test.dart:388-430`, `test/store/hum_to_midi_store_test.dart`

- [ ] **Step 1: Failing store test** (add to `hum_to_midi_store_test.dart`; follow how the file builds its container with `micPitchSessionProvider.overrideWithValue`)

```dart
class _ThrowingMicPitchSession implements MicPitchSession {
  @override
  Future<bool> hasPermission() async => throw UnsupportedError('no mic');
  @override
  Future<Stream<PitchFrame>> start() async => throw UnsupportedError('no mic');
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

test('startRecording reports an error when the microphone is unavailable', () async {
  final container = ProviderContainer(
    overrides: [
      micPitchSessionProvider.overrideWithValue(_ThrowingMicPitchSession()),
    ],
  );
  addTearDown(container.dispose);

  await container.read(humToMidiProvider.notifier).startRecording();

  final state = container.read(humToMidiProvider);
  expect(state.status, HumToMidiStatus.error);
  expect(state.errorMessage, 'Microphone unavailable');
});
```

- [ ] **Step 2: Run** `flutter test test/store/hum_to_midi_store_test.dart`. Expected: FAIL (exception escapes).

- [ ] **Step 3: Implement.** In `startRecording()` replace the permission check and `start()` call with:

```dart
    final Stream<PitchFrame> stream;
    try {
      if (!await session.hasPermission()) {
        state = state.copyWith(
          status: HumToMidiStatus.error,
          errorMessage: () => 'Microphone permission denied',
        );
        return;
      }
      stream = await session.start();
    } on Object {
      state = state.copyWith(
        status: HumToMidiStatus.error,
        errorMessage: () => 'Microphone unavailable',
      );
      return;
    }
```

(the following `final startedAtMs = ...` and `_framesSub = stream.listen(...)` stay as they are).

- [ ] **Step 4: Remove the web gate** in `piano_roll_hum_recorder.dart`: delete the `isWeb` field/constructor parameter (`const PianoRollHumRecorderPanel({super.key});`), the `kIsWeb` import, and the whole `if (widget.isWeb) { return const PianoRollHumRecorderCard(...) }` block.

- [ ] **Step 5: Update widget tests** in `piano_roll_screen_v2_test.dart`: delete the test `'hum recorder shows web message when isWeb is true'`, and in `'hum recorder shows record button when isWeb is false'` rename it to `'hum recorder shows the record button'` and change `PianoRollHumRecorderPanel(isWeb: false)` to `PianoRollHumRecorderPanel()`.

- [ ] **Step 6: macOS microphone.** Add to both `.entitlements` files, inside `<dict>`:

```xml
	<key>com.apple.security.device.audio-input</key>
	<true/>
```

and to `macos/Runner/Info.plist` inside the top `<dict>` (copy the wording of the iOS string in `ios/Runner/Info.plist:69`):

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Muzician listens to your humming to turn it into notes.</string>
```

Verify: `grep -c "audio-input" macos/Runner/*.entitlements` → `1` for each file; `grep -c NSMicrophoneUsageDescription macos/Runner/Info.plist` → `1`.

- [ ] **Step 7: Run** `flutter analyze` and `flutter test test/features/piano_roll test/store/hum_to_midi_store_test.dart`. Expected: no issues, PASS.

- [ ] **Step 8: Manual check on web** (`flutter run -d chrome`, then Roll → Hum → Record, allow the permission; getUserMedia needs localhost or HTTPS) and on macOS (`flutter run -d macos`). Confirm the live note label moves while humming and a take imports notes. Report anything that fails; do not claim success without having run it.

- [ ] **Step 9: Commit**

```bash
git add lib/features/piano_roll/piano_roll_hum_recorder.dart lib/store/hum_to_midi_store.dart macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements macos/Runner/Info.plist test/features/piano_roll/piano_roll_screen_v2_test.dart test/store/hum_to_midi_store_test.dart
git commit -m "feat(hum): enable Hum to MIDI on web and desktop" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: `PianoRollSound` in state, snapshot and store

**Files:**
- Modify: `lib/models/piano_roll.dart`, `lib/models/save_system.dart`, `lib/store/piano_roll_store.dart`, `lib/store/save_system_store.dart:674`, `lib/features/piano_roll/piano_roll_save_panel.dart`
- Test: `test/store/piano_roll_store_test.dart`, `test/models/` (find the existing `PianoRollSnapshot` test with `grep -rln PianoRollSnapshot test`, otherwise create `test/models/piano_roll_snapshot_sound_test.dart`)

- [ ] **Step 1: Failing tests**

```dart
test('PianoRollSnapshot round-trips sound and defaults old saves to piano', () {
  final snap = PianoRollSnapshot(
    tempo: 120,
    numerator: 4,
    denominator: 4,
    totalMeasures: 4,
    notes: const [],
    pitchRangeStart: 48,
    pitchRangeEnd: 84,
    snapTicks: 1,
    highlightedNotes: const [],
    sound: PianoRollSound.organ,
  );
  final json = snap.toJson();
  expect(json['sound'], 'organ');
  expect(PianoRollSnapshot.fromJson(json).sound, PianoRollSound.organ);

  json.remove('sound');
  expect(PianoRollSnapshot.fromJson(json).sound, PianoRollSound.piano);
  expect(
    PianoRollSnapshot.fromJson({...json, 'sound': 'nonsense'}).sound,
    PianoRollSound.piano,
  );
});
```

and in `piano_roll_store_test.dart` (use its existing container helper):

```dart
test('setSound updates state and loadSnapshot restores it', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final notifier = container.read(pianoRollProvider.notifier);

  notifier.setSound(PianoRollSound.bell);
  expect(container.read(pianoRollProvider).sound, PianoRollSound.bell);

  notifier.loadSnapshot(
    PianoRollSnapshot(
      tempo: 120,
      numerator: 4,
      denominator: 4,
      totalMeasures: 4,
      notes: const [],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 1,
      highlightedNotes: const [],
      sound: PianoRollSound.synthLead,
    ),
  );
  expect(container.read(pianoRollProvider).sound, PianoRollSound.synthLead);

  notifier.reset();
  expect(container.read(pianoRollProvider).sound, PianoRollSound.piano);
});
```

- [ ] **Step 2: Run both files**, expect FAIL (compile errors: `PianoRollSound`, `sound`, `setSound`).

- [ ] **Step 3: Model.** In `lib/models/piano_roll.dart` add above `PianoRollState`:

```dart
/// Playback timbre of a piano roll. Stored by [name]; unknown names fall back
/// to [piano] so old or newer saves always load.
enum PianoRollSound {
  piano('Piano'),
  cleanGuitar('Clean guitar'),
  distortedGuitar('Distorted guitar'),
  organ('Organ'),
  synthLead('Synth lead'),
  bell('Bell');

  const PianoRollSound(this.label);
  final String label;

  static PianoRollSound fromName(String? raw) => PianoRollSound.values
      .firstWhere((s) => s.name == raw, orElse: () => PianoRollSound.piano);
}
```

In `PianoRollState` add `final PianoRollSound sound;`, constructor param `this.sound = PianoRollSound.piano,`, `copyWith` param `PianoRollSound? sound,` and `sound: sound ?? this.sound,` in the returned state.

- [ ] **Step 4: Snapshot.** In `PianoRollSnapshot` add `final PianoRollSound sound;`, constructor `this.sound = PianoRollSound.piano,`, `'sound': sound.name,` in `toJson`, and `sound: PianoRollSound.fromName(json['sound'] as String?),` in `fromJson`. Ensure `save_system.dart` can see `PianoRollSound` (it already imports piano roll types; add `import 'piano_roll.dart';` only if missing).

- [ ] **Step 5: Store.** In `piano_roll_store.dart` add next to `setSnapTicks`:

```dart
  void setSound(PianoRollSound sound) => state = state.copyWith(sound: sound);
```

and `sound: snap.sound,` in the `PianoRollState(...)` built by `loadSnapshot`. `reset()` already returns the piano default.

- [ ] **Step 6: Carry the sound through the other two snapshot builders.** `save_system_store.dart` (the `snap is PianoRollSnapshot` branch): add `sound: snap.sound,`. `piano_roll_save_panel.dart` `_captureSnapshot`: add `sound: prState.sound,`.

- [ ] **Step 7: Run** `flutter test test/store test/models test/features/save_system` and `flutter analyze`. Expected: PASS, no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/models/piano_roll.dart lib/models/save_system.dart lib/store/piano_roll_store.dart lib/store/save_system_store.dart lib/features/piano_roll/piano_roll_save_panel.dart test
git commit -m "feat(piano-roll): add per-roll sound to state and saves" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

(Run `git status` first and add only the test files you created or changed under `test`.)

---

### Task 8: Organ, synth lead and bell timbres

**Files:**
- Create: `lib/utils/timbre_synth.dart`
- Modify: `lib/utils/note_player.dart` (add `previewTimbre`)
- Test: `test/utils/timbre_synth_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/utils/timbre_synth.dart';

void main() {
  for (final sound in [
    PianoRollSound.organ,
    PianoRollSound.synthLead,
    PianoRollSound.bell,
  ]) {
    test('${sound.name} renders a bounded, audible, fading note', () {
      final samples = TimbreSynth.render(sound, 60);
      expect(samples.length, TimbreSynth.sampleRate * 700 ~/ 1000);
      final peak = samples.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m);
      expect(peak, inInclusiveRange(4000, 32767));
      final tail = samples.sublist(samples.length - 200);
      expect(tail.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m), lessThan(peak ~/ 4));
    });
  }

  test('rendering differs between timbres and pitches', () {
    expect(
      TimbreSynth.render(PianoRollSound.organ, 60),
      isNot(equals(TimbreSynth.render(PianoRollSound.bell, 60))),
    );
    expect(
      TimbreSynth.render(PianoRollSound.organ, 60),
      isNot(equals(TimbreSynth.render(PianoRollSound.organ, 64))),
    );
  });

  test('piano and guitar sounds are not handled by the synth', () {
    expect(() => TimbreSynth.render(PianoRollSound.piano, 60), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run, expect FAIL** (missing file).

- [ ] **Step 3: Implement `lib/utils/timbre_synth.dart`**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/piano_roll.dart';

/// Pure-Dart renderers for the non-piano, non-guitar Piano Roll timbres.
class TimbreSynth {
  TimbreSynth._();

  static const sampleRate = 44100;
  static const _durationMs = 700;

  /// Bump when a renderer changes so cached audio is not reused.
  static const cacheVersion = 1;

  static Object cacheKey(PianoRollSound sound, int midi) =>
      'timbre_v${cacheVersion}_${sound.name}_$midi';

  static Int16List render(PianoRollSound sound, int midi) {
    final freq = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    final n = sampleRate * _durationMs ~/ 1000;
    final samples = Int16List(n);
    final voice = switch (sound) {
      PianoRollSound.organ => _organ,
      PianoRollSound.synthLead => _synthLead,
      PianoRollSound.bell => _bell,
      _ => throw ArgumentError.value(sound, 'sound', 'not a synth timbre'),
    };
    final release = sampleRate * 40 ~/ 1000;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final fade = n - i < release ? (n - i) / release : 1.0;
      samples[i] = (voice(freq, t) * fade * 20000).round().clamp(-32767, 32767);
    }
    return samples;
  }

  static double _sin(double f, double t) => math.sin(2 * math.pi * f * t);

  static double _organ(double f, double t) {
    final attack = math.min(t / 0.01, 1.0);
    final decay = 0.8 + 0.2 * math.exp(-t * 2);
    final v = _sin(f, t) * 0.5 +
        _sin(f * 2, t) * 0.3 +
        _sin(f * 3, t) * 0.15 +
        _sin(f * 4, t) * 0.08;
    return v * attack * decay;
  }

  static double _synthLead(double f, double t) {
    final attack = math.min(t / 0.005, 1.0);
    final vibrato = 1 + 0.004 * _sin(5.5, t);
    // Band-limited saw: first eight partials.
    var v = 0.0;
    for (var k = 1; k <= 8; k++) {
      v += _sin(f * k * vibrato, t) / k;
    }
    return v * 0.5 * attack * math.exp(-t * 1.2);
  }

  static double _bell(double f, double t) {
    // Inharmonic partials with faster decay on the upper ones.
    const partials = [(1.0, 1.0, 3.0), (2.76, 0.6, 5.0), (5.4, 0.35, 8.0), (8.93, 0.2, 12.0)];
    var v = 0.0;
    for (final (ratio, gain, decay) in partials) {
      v += _sin(f * ratio, t) * gain * math.exp(-t * decay);
    }
    return v * 0.6;
  }
}
```

- [ ] **Step 4: Run, expect PASS.** If the `peak` bound fails for one timbre, adjust that timbre's gain, not the test bounds.

- [ ] **Step 5: Add `previewTimbre` to `NotePlayer`** (after `previewGuitarStrum`; add `import '../models/piano_roll.dart';` and `import 'timbre_synth.dart';` at the top of `note_player.dart`):

```dart
  /// Previews [midiNote] with the Piano Roll [sound].
  void previewTimbre(
    PianoRollSound sound,
    int midiNote, {
    double volume = 0.8,
    double pan = 0.0,
  }) {
    switch (sound) {
      case PianoRollSound.piano:
        previewNote(midiNote, volume: volume, pan: pan);
      case PianoRollSound.cleanGuitar:
        previewGuitarNote(
          midiNote,
          tone: GuitarTone.clean,
          volume: volume,
          pan: pan,
        );
      case PianoRollSound.distortedGuitar:
        previewGuitarNote(
          midiNote,
          tone: GuitarTone.distorted,
          volume: volume,
          pan: pan,
        );
      case PianoRollSound.organ:
      case PianoRollSound.synthLead:
      case PianoRollSound.bell:
        _previewNote(
          midiNote,
          volume: volume,
          pan: pan,
          cacheKey: TimbreSynth.cacheKey(sound, midiNote),
          render: () => _encodeWav(TimbreSynth.render(sound, midiNote)),
        );
    }
  }
```

- [ ] **Step 6: Run** `flutter analyze lib/utils` and `flutter test test/utils`. Expected: no issues, PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/utils/timbre_synth.dart lib/utils/note_player.dart test/utils/timbre_synth_test.dart
git commit -m "feat(piano-roll): add organ, synth lead and bell timbres" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Playback and grid auditions use the roll's sound

**Files:**
- Modify: `lib/store/piano_roll_playback_store.dart:30-36`, `lib/features/piano_roll/piano_roll_grid.dart` (3 `previewNote` calls near lines 707, 1092, 1135)
- Test: `test/utils/note_player_sequenced_test.dart` is for sequenced notes only; for the sink add the test below to `test/store/piano_roll_playback_store_test.dart`

- [ ] **Step 1: Failing test** (the default sink is a `Provider`, so verify selection logic through a small pure function)

Add to `piano_roll_playback_store.dart`'s public API a testable dispatcher and test it:

```dart
test('default sink plays through the sound read at call time', () async {
  final played = <(PianoRollSound, int, double)>[];
  final container = ProviderContainer(
    overrides: [
      pianoRollTimbrePlayerProvider.overrideWithValue(
        (sound, midi, volume) => played.add((sound, midi, volume)),
      ),
    ],
  );
  addTearDown(container.dispose);

  final sink = container.read(pianoRollPlaybackSinkProvider);
  await sink([60, 64], 0.5);
  container.read(pianoRollProvider.notifier).setSound(PianoRollSound.bell);
  await sink([67], 0.5);

  expect(played, [
    (PianoRollSound.piano, 60, 0.5),
    (PianoRollSound.piano, 64, 0.5),
    (PianoRollSound.bell, 67, 0.5),
  ]);
});
```

- [ ] **Step 2: Run** `flutter test test/store/piano_roll_playback_store_test.dart`. Expected: FAIL (`pianoRollTimbrePlayerProvider` undefined).

- [ ] **Step 3: Implement.** In `piano_roll_playback_store.dart` (add `import '../models/piano_roll.dart';`) replace the default sink:

```dart
/// Plays one note with a Piano Roll sound. Overridden in tests.
typedef PianoRollTimbrePlayer =
    void Function(PianoRollSound sound, int midiNote, double volume);

final pianoRollTimbrePlayerProvider = Provider<PianoRollTimbrePlayer>((ref) {
  return (sound, midiNote, volume) =>
      NotePlayer.instance.previewTimbre(sound, midiNote, volume: volume);
});

/// Default sink: reads the roll's sound at call time, so changing it applies
/// to the next note even while playing.
final pianoRollPlaybackSinkProvider = Provider<PianoRollPlaybackSink>((ref) {
  final play = ref.read(pianoRollTimbrePlayerProvider);
  return (List<int> midiNotes, double volume) async {
    final sound = ref.read(pianoRollProvider).sound;
    for (final midi in midiNotes) {
      play(sound, midi, volume);
    }
  };
});
```

(keep the existing doc comment above the sink.)

- [ ] **Step 4: Grid auditions.** In `piano_roll_grid.dart` replace each of the three `NotePlayer.instance.previewNote(X, volume: ref.read(settingsProvider).noteVolume)` calls with:

```dart
    NotePlayer.instance.previewTimbre(
      ref.read(pianoRollProvider).sound,
      X,
      volume: ref.read(settingsProvider).noteVolume,
    );
```

where `X` is `coord.midi` (lines ~707 and ~1135) or `hit.midiNote` (line ~1092). Keep each call's surrounding indentation.

- [ ] **Step 5: Run** `flutter analyze` and `flutter test test/store/piano_roll_playback_store_test.dart test/features/piano_roll`. Expected: PASS (existing tests override `pianoRollPlaybackSinkProvider` directly and are unaffected).

- [ ] **Step 6: Commit**

```bash
git add lib/store/piano_roll_playback_store.dart lib/features/piano_roll/piano_roll_grid.dart test/store/piano_roll_playback_store_test.dart
git commit -m "feat(piano-roll): play and audition notes with the roll's sound" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 10: Sound picker in Roll Settings

**Files:**
- Modify: `lib/features/piano_roll/piano_roll_screen_v2.dart` (`_SettingsSheet`, ~line 667)
- Test: `test/features/piano_roll/piano_roll_sound_picker_test.dart`

- [ ] **Step 1: Failing widget test** (mirror the provider/theme setup used in `piano_roll_screen_v2_test.dart`; `_SettingsSheet` is private, so pump the screen and open the sheet via its `'Roll Settings'` tooltip, as the existing tests do for other sheets)

```dart
testWidgets('Roll Settings lists every sound and selecting one updates the roll', (
  tester,
) async {
  // pump PianoRollScreenV2 with the same wrapper helper as piano_roll_screen_v2_test.dart
  await tester.tap(find.byTooltip('Roll Settings').first);
  await tester.pumpAndSettle();

  for (final sound in PianoRollSound.values) {
    expect(find.text(sound.label), findsOneWidget);
  }

  await tester.tap(find.text('Organ'));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(PianoRollScreenV2)),
  );
  expect(container.read(pianoRollProvider).sound, PianoRollSound.organ);
});
```

(Copy the exact screen name, wrapper and viewport setup from the nearest existing test in `piano_roll_screen_v2_test.dart`; do not invent a new harness.)

- [ ] **Step 2: Run, expect FAIL** (no sound labels in the sheet).

- [ ] **Step 3: Implement.** In `_SettingsSheet.build` add, after the metronome description `Text`, a `Consumer`-free section (the sheet is already a `ConsumerWidget`):

```dart
        const SizedBox(height: 16),
        Text(
          'Sound',
          style: TextStyle(
            color: StudioPalette.of(context).textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sound in PianoRollSound.values)
              ChoiceChip(
                label: Text(sound.label),
                selected: ref.watch(
                  pianoRollProvider.select((s) => s.sound == sound),
                ),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  ref.read(pianoRollProvider.notifier).setSound(sound);
                  NotePlayer.instance.previewTimbre(
                    sound,
                    60,
                    volume: settings.noteVolume,
                  );
                },
              ),
          ],
        ),
```

Check `StudioPalette` field names (`textPrimary` may differ): `grep -n "textMuted\|textPrimary" lib/ui/**/*palette*.dart` and use the existing primary-text token. Add imports for `NotePlayer` and `PianoRollSound` if missing. Update the sheet title doc comment to say "metronome and sound".

- [ ] **Step 4: Run the new test, then** `flutter analyze` and `flutter test test/features/piano_roll`. Expected: PASS.

- [ ] **Step 5: Verify layout** on a compact (390×844) and a wide (1280×800) viewport (`flutter run -d chrome` with the browser resized, or a widget test with `tester.view.physicalSize`): chips wrap, have ≥44 px height, and no overflow at 2× text scale.

- [ ] **Step 6: Commit**

```bash
git add lib/features/piano_roll/piano_roll_screen_v2.dart test/features/piano_roll/piano_roll_sound_picker_test.dart
git commit -m "feat(piano-roll): add sound picker to Roll Settings" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 11: Documentation and final verification

**Files:**
- Modify: `docs/piano_roll.md`, `README.md`, `AGENTS.md` (only if guidance changes)

- [ ] **Step 1: `docs/piano_roll.md`.**
  - Line 8 summary and ~line 84 provider table: replace "mobile-only" Hum wording with "Hum-to-MIDI recording on mobile, web and desktop".
  - Replace the `## Hum to MIDI & Web Support` intro and the capability table: Hum capture moves to the "Supported on web" column; add the note "Browsers require HTTPS or `localhost` and ask for microphone permission".
  - Update the pipeline table (stage 1: 16 kHz, 1024-sample window, **256-sample hop**, ~62 frames/s, adaptive noise gate via `NoiseFloorTracker`; add a stage "Pitch smoothing" with `smoothPitchFrames`; stage 3 mentions back-dated pitch switches and re-attack splits).
  - Add `maxHumGate` (0.12) to the tunable table and `reattackGapMs` (70 / 100 / disabled) to the preset table.
  - Update the `PianoRollHumRecorderPanel` section (~line 608): no web-only card; add the "Microphone unavailable" error.
  - Add a `## Sound` section: six sounds, picked in Roll Settings, saved in `PianoRollSnapshot.sound`, old saves load as Piano, applies to playback and note auditions.
  - Update lines ~448-454 and ~720 which say hum is mobile-only.

- [ ] **Step 2: `README.md`** line 31: change "mobile **Hum recorder** controls" to "**Hum recorder** (mobile, web, desktop) and per-roll sound" and adjust any "mobile-only" mention (`grep -n -i "mobile" README.md`).

- [ ] **Step 3: Review `AGENTS.md`.** No persistent rule changes are expected; do not edit unless a rule became false.

- [ ] **Step 4: Full verification**

```bash
dart format lib test
flutter analyze
flutter test
flutter build web --release
```

Expected: formatter only touches files you changed (review `git diff --stat`), analyze reports no issues, all tests pass, web build succeeds.

- [ ] **Step 5: Commit**

```bash
git add docs/piano_roll.md README.md
git commit -m "docs: describe web/desktop Hum, accuracy pipeline and roll sound" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Self-Review

**Spec coverage:** noise gate → T2/T5; octave guard & smoothing → T3 (spec delta noted); segmentation (bridge/merge/split, back-dating) → T4; latency (hop 256, back-dating) → T4/T5; real sample rate → resolved as a delta (worklet resamples); web gate/entitlements → T6 (Windows runner exists); sound enum, state, snapshot back-compat → T7; timbres → T8; sink/grid → T9; picker → T10; tests/docs → T1-T11.

**Placeholders:** none; T7 step 1 and T10 step 1 instruct copying an existing test harness because the exact helper names live in test files, and name the file to copy from.

**Type consistency:** `PianoRollSound` (`piano, cleanGuitar, distortedGuitar, organ, synthLead, bell`, `.label`, `fromName`), `setSound`, `previewTimbre(sound, midi, {volume, pan})`, `TimbreSynth.render/cacheKey/sampleRate`, `NoiseFloorTracker.gate/update(pitched:)`, `analyzeHumWindow(window, sampleRate:, timestampMs:, gate:)`, `HumPcmFramer.addPcm16`, `HumSensitivityTuning.reattackGapMs`, `pianoRollTimbrePlayerProvider` are used identically across tasks.
