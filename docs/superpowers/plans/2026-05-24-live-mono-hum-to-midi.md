# Live Mono Hum-to-MIDI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mobile-only live mono hum-to-MIDI flow that records microphone input, detects stable monophonic notes, lightly quantizes them, and appends them to the piano roll.

**Architecture:** Add a shared microphone session adapter plus pure Dart pitch and segmentation rules, keep recording lifecycle in a dedicated Riverpod store, and let the piano roll remain the single source of truth for editable note data. The piano roll UI only starts and stops the session and previews live note state; finalized notes are imported in one batch after stop.

**Tech Stack:** Flutter, Riverpod `NotifierProvider`, `flutter_test`, `record: ^6.2.1`, Android `RECORD_AUDIO` permission, iOS `NSMicrophoneUsageDescription`

---

## File Structure

### Create

- `lib/models/hum_to_midi.dart`
  Stores immutable status, frame, segmented note, and import-note models for the hum session.
- `lib/schema/rules/mono_pitch_rules.dart`
  Pure Dart pitch mapping, note segmentation, note-label, and timestamp-to-tick quantization helpers.
- `lib/store/hum_to_midi_store.dart`
  Riverpod recording lifecycle store plus dependency injection for the mic session.
- `lib/utils/mic_pitch_session.dart`
  Mic session interface plus `record`-backed mobile implementation that emits `PitchFrame` values.
- `lib/features/piano_roll/piano_roll_hum_recorder.dart`
  Compact piano roll recorder panel with live note monitor and start/stop actions.
- `test/schema/rules/mono_pitch_rules_test.dart`
  Unit tests for pitch mapping, segmentation, and quantization.
- `test/store/piano_roll_store_test.dart`
  Store tests for batch import and timeline expansion.
- `test/store/hum_to_midi_store_test.dart`
  Store tests using a fake mic session.
- `test/features/piano_roll/piano_roll_hum_recorder_test.dart`
  Widget tests for the recorder panel presentation.

### Modify

- `pubspec.yaml`
  Add `record`.
- `android/app/build.gradle.kts`
  Raise Android `minSdk` to `23` for PCM stream capture.
- `android/app/src/main/AndroidManifest.xml`
  Add `RECORD_AUDIO` permission.
- `ios/Runner/Info.plist`
  Add microphone usage description.
- `lib/store/piano_roll_store.dart`
  Add batch import and timeline expansion helpers.
- `lib/features/piano_roll/piano_roll_feature.dart`
  Export the new recorder widget.
- `lib/main.dart`
  Mount the recorder panel in the piano roll screen.
- `docs/piano_roll.md`
  Document the new hum-to-MIDI workflow after implementation.

## Task 1: Add Hum Models And Pure Mono Pitch Rules

**Files:**
- Create: `lib/models/hum_to_midi.dart`
- Create: `lib/schema/rules/mono_pitch_rules.dart`
- Test: `test/schema/rules/mono_pitch_rules_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/schema/rules/mono_pitch_rules.dart' as rules;

void main() {
  group('mono pitch rules', () {
    test('maps 440 Hz to MIDI 69', () {
      expect(rules.frequencyToMidi(440.0), 69);
      expect(rules.frequencyToMidi(40.0), isNull);
      expect(rules.midiToNoteLabel(69), 'A4');
    });

    test('segments one stable note and ignores a short silence gap', () {
      const frames = <PitchFrame>[
        PitchFrame(timestampMs: 0, frequencyHz: 440, midiNote: 69, centsOffset: 0, amplitude: 0.8, confidence: 0.97, isSilence: false),
        PitchFrame(timestampMs: 60, frequencyHz: 440, midiNote: 69, centsOffset: 0, amplitude: 0.8, confidence: 0.97, isSilence: false),
        PitchFrame(timestampMs: 120, frequencyHz: 0, midiNote: null, centsOffset: 0, amplitude: 0.02, confidence: 0, isSilence: true),
        PitchFrame(timestampMs: 180, frequencyHz: 441, midiNote: 69, centsOffset: 3, amplitude: 0.8, confidence: 0.96, isSilence: false),
        PitchFrame(timestampMs: 240, frequencyHz: 441, midiNote: 69, centsOffset: 3, amplitude: 0.8, confidence: 0.96, isSilence: false),
      ];

      final notes = rules.segmentStableNotes(frames);

      expect(notes, hasLength(1));
      expect(notes.single.midiNote, 69);
      expect(notes.single.startMs, 0);
      expect(notes.single.endMs, 240);
    });

    test('quantizes timestamps into piano roll ticks', () {
      const notes = [
        DetectedMonoNote(startMs: 0, endMs: 260, midiNote: 69, confidence: 0.95),
      ];

      final imported = rules.quantizeNotesToTicks(
        notes: notes,
        anchorTick: 8,
        tempo: 120,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        snapTicks: 2,
      );

      expect(imported.single.startTick, 8);
      expect(imported.single.durationTicks, greaterThanOrEqualTo(2));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/schema/rules/mono_pitch_rules_test.dart`

Expected: FAIL with import errors because `hum_to_midi.dart` and `mono_pitch_rules.dart` do not exist yet.

- [ ] **Step 3: Write the minimal models and rules**

```dart
// lib/models/hum_to_midi.dart
enum HumToMidiStatus { idle, requestingPermission, recording, processing, completed, error }

class PitchFrame {
  final int timestampMs;
  final double frequencyHz;
  final int? midiNote;
  final double centsOffset;
  final double amplitude;
  final double confidence;
  final bool isSilence;

  const PitchFrame({
    required this.timestampMs,
    required this.frequencyHz,
    required this.midiNote,
    required this.centsOffset,
    required this.amplitude,
    required this.confidence,
    required this.isSilence,
  });
}

class DetectedMonoNote {
  final int startMs;
  final int endMs;
  final int midiNote;
  final double confidence;

  const DetectedMonoNote({
    required this.startMs,
    required this.endMs,
    required this.midiNote,
    required this.confidence,
  });
}

class QuantizedHumNote {
  final int midiNote;
  final int startTick;
  final int durationTicks;

  const QuantizedHumNote({
    required this.midiNote,
    required this.startTick,
    required this.durationTicks,
  });
}
```

```dart
// lib/schema/rules/mono_pitch_rules.dart
import 'dart:math';
import 'dart:typed_data';

import '../../models/hum_to_midi.dart';
import '../../models/piano_roll.dart';
import 'piano_roll_rules.dart' as piano_roll_rules;

const minHumFrequencyHz = 80.0;
const maxHumFrequencyHz = 1000.0;
const minStableConfidence = 0.85;
const minStableNoteMs = 120;
const maxMergeGapMs = 120;
const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

int? frequencyToMidi(double frequencyHz) {
  if (frequencyHz < minHumFrequencyHz || frequencyHz > maxHumFrequencyHz) {
    return null;
  }
  final midi = 69 + 12 * log(frequencyHz / 440.0) / ln2;
  return midi.round();
}

String midiToNoteLabel(int midiNote) {
  final octave = (midiNote ~/ 12) - 1;
  return '${_noteNames[midiNote % 12]}$octave';
}

double estimateNormalizedAmplitude(Uint8List bytes) {
  if (bytes.isEmpty) return 0;
  final data = ByteData.sublistView(bytes);
  var maxAbs = 0.0;
  for (var i = 0; i < bytes.lengthInBytes; i += 2) {
    final sample = data.getInt16(i, Endian.little).abs() / 32768.0;
    if (sample > maxAbs) maxAbs = sample;
  }
  return maxAbs;
}

double? estimateDominantFrequency(Uint8List bytes, {required int sampleRate}) {
  if (bytes.lengthInBytes < 4) return null;
  final data = ByteData.sublistView(bytes);
  final samples = <double>[
    for (var i = 0; i < bytes.lengthInBytes; i += 2)
      data.getInt16(i, Endian.little) / 32768.0,
  ];
  final minLag = sampleRate ~/ maxHumFrequencyHz;
  final maxLag = sampleRate ~/ minHumFrequencyHz;
  if (samples.length <= maxLag) return null;

  final difference = List<double>.filled(maxLag + 1, 0);
  for (var lag = minLag; lag <= maxLag; lag++) {
    var sum = 0.0;
    for (var i = 0; i + lag < samples.length; i++) {
      final delta = samples[i] - samples[i + lag];
      sum += delta * delta;
    }
    difference[lag] = sum;
  }

  final cmndf = List<double>.filled(maxLag + 1, 1);
  var runningTotal = 0.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    runningTotal += difference[lag];
    cmndf[lag] = runningTotal == 0 ? 1 : difference[lag] * lag / runningTotal;
  }

  for (var lag = minLag; lag <= maxLag; lag++) {
    if (cmndf[lag] < 0.15) {
      return sampleRate / lag;
    }
  }

  return null;
}

List<DetectedMonoNote> segmentStableNotes(List<PitchFrame> frames) {
  if (frames.isEmpty) return const [];
  final notes = <DetectedMonoNote>[];
  int? activeMidi;
  int? startMs;
  double confidenceTotal = 0;
  int confidenceCount = 0;
  int lastVoicedMs = frames.first.timestampMs;

  for (final frame in frames) {
    final isVoiced =
        !frame.isSilence &&
        frame.midiNote != null &&
        frame.confidence >= minStableConfidence;
    if (isVoiced) {
      if (activeMidi == null) {
        activeMidi = frame.midiNote;
        startMs = frame.timestampMs;
      } else if (frame.midiNote != activeMidi) {
        final endMs = lastVoicedMs;
        if (startMs != null && endMs - startMs >= minStableNoteMs) {
          notes.add(
            DetectedMonoNote(
              startMs: startMs,
              endMs: endMs,
              midiNote: activeMidi,
              confidence: confidenceCount == 0 ? 0 : confidenceTotal / confidenceCount,
            ),
          );
        }
        activeMidi = frame.midiNote;
        startMs = frame.timestampMs;
        confidenceTotal = 0;
        confidenceCount = 0;
      }
      lastVoicedMs = frame.timestampMs;
      confidenceTotal += frame.confidence;
      confidenceCount += 1;
      continue;
    }

    if (activeMidi != null && frame.timestampMs - lastVoicedMs > maxMergeGapMs) {
      if (startMs != null && lastVoicedMs - startMs >= minStableNoteMs) {
        notes.add(
          DetectedMonoNote(
            startMs: startMs,
            endMs: lastVoicedMs,
            midiNote: activeMidi,
            confidence: confidenceCount == 0 ? 0 : confidenceTotal / confidenceCount,
          ),
        );
      }
      activeMidi = null;
      startMs = null;
      confidenceTotal = 0;
      confidenceCount = 0;
    }
  }

  if (activeMidi != null && startMs != null && lastVoicedMs - startMs >= minStableNoteMs) {
    notes.add(
      DetectedMonoNote(
        startMs: startMs,
        endMs: lastVoicedMs,
        midiNote: activeMidi,
        confidence: confidenceCount == 0 ? 0 : confidenceTotal / confidenceCount,
      ),
    );
  }

  return notes;
}

List<QuantizedHumNote> quantizeNotesToTicks({
  required List<DetectedMonoNote> notes,
  required int anchorTick,
  required int tempo,
  required TimeSignature timeSignature,
  required int snapTicks,
}) {
  final msPerTick = 60000 / tempo / piano_roll_rules.ticksPerQuarter;
  return notes.map((note) {
    final rawStartTick = anchorTick + (note.startMs / msPerTick);
    final rawEndTick = anchorTick + (note.endMs / msPerTick);
    final roundedStart = rawStartTick.round();
    final roundedEnd = max(roundedStart + 1, rawEndTick.round());
    final snappedStart =
        snapTicks > 1 && (roundedStart % snapTicks).abs() <= max(1, snapTicks ~/ 2)
            ? (roundedStart / snapTicks).round() * snapTicks
            : roundedStart;
    return QuantizedHumNote(
      midiNote: note.midiNote,
      startTick: snappedStart,
      durationTicks: max(1, roundedEnd - snappedStart),
    );
  }).toList();
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/schema/rules/mono_pitch_rules_test.dart`

Expected: PASS with 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/models/hum_to_midi.dart lib/schema/rules/mono_pitch_rules.dart test/schema/rules/mono_pitch_rules_test.dart
git commit -m "feat: add mono hum pitch rules"
```

## Task 2: Add Piano Roll Batch Import And Timeline Expansion

**Files:**
- Modify: `lib/store/piano_roll_store.dart`
- Test: `test/store/piano_roll_store_test.dart`

- [ ] **Step 1: Write the failing store test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/store/piano_roll_store.dart';

void main() {
  test('suggestedImportAnchorTick prefers the selected column', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.selectColumn(6);

    expect(notifier.suggestedImportAnchorTick(), 6);
  });

  test('suggestedImportAnchorTick falls back to the next measure boundary', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setTimeSignature(const TimeSignature(beatsPerMeasure: 4, beatUnit: 4));
    notifier.addNote(69, 9, 2);

    expect(notifier.suggestedImportAnchorTick(), 16);
  });

  test('appendImportedNotes expands the roll and selects imported notes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(pianoRollProvider.notifier);
    notifier.setTotalMeasures(1);

    final result = notifier.appendImportedNotes(const [
      QuantizedHumNote(midiNote: 69, startTick: 14, durationTicks: 4),
      QuantizedHumNote(midiNote: 71, startTick: 18, durationTicks: 3),
    ]);

    final state = container.read(pianoRollProvider);
    expect(result.createdCount, 2);
    expect(result.truncated, isFalse);
    expect(state.config.totalMeasures, 2);
    expect(state.notes.map((n) => n.midiNote), [69, 71]);
    expect(state.selectedNoteIds, hasLength(2));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/store/piano_roll_store_test.dart`

Expected: FAIL with `NoSuchMethodError` or compile failure because `appendImportedNotes` does not exist.

- [ ] **Step 3: Write the minimal importer**

```dart
// lib/store/piano_roll_store.dart
import '../models/hum_to_midi.dart';

int suggestedImportAnchorTick() {
  final selectedTick = state.selectedColumnTick;
  if (selectedTick != null) return selectedTick;
  if (state.notes.isEmpty) return 0;
  final measureTicks = rules.ticksPerMeasure(state.config.timeSignature);
  final latestEndTick = state.notes
      .map((note) => note.startTick + note.durationTicks)
      .reduce(max);
  return ((latestEndTick + measureTicks - 1) ~/ measureTicks) * measureTicks;
}

void _ensureTimelineCoversEndTick(int endTickExclusive) {
  final measureTicks = rules.ticksPerMeasure(state.config.timeSignature);
  final requiredMeasures = max(1, (endTickExclusive + measureTicks - 1) ~/ measureTicks);
  if (requiredMeasures > state.config.totalMeasures) {
    setTotalMeasures(requiredMeasures);
  }
}

({int createdCount, bool truncated}) appendImportedNotes(
  List<QuantizedHumNote> imported,
) {
  if (imported.isEmpty) return (createdCount: 0, truncated: false);
  final clamped = imported
      .where((note) => note.durationTicks > 0)
      .map(
        (note) => QuantizedHumNote(
          midiNote: note.midiNote.clamp(state.pitchRangeStart, state.pitchRangeEnd),
          startTick: note.startTick,
          durationTicks: note.durationTicks,
        ),
      )
      .toList();
  if (clamped.isEmpty) return (createdCount: 0, truncated: false);

  final furthestEndTick = clamped
      .map((note) => note.startTick + note.durationTicks)
      .reduce(max);
  _ensureTimelineCoversEndTick(furthestEndTick);
  final maxTick = rules.totalTicks(
    state.config.timeSignature,
    state.config.totalMeasures,
  );
  var truncated = false;

  final created = clamped.map(
    (note) {
      final boundedStart = note.startTick.clamp(0, maxTick - 1);
      final boundedDuration = min(note.durationTicks, maxTick - boundedStart);
      if (boundedStart != note.startTick || boundedDuration != note.durationTicks) {
        truncated = true;
      }
      return PianoRollNote(
        id: _makeId(),
        midiNote: note.midiNote,
        pitchClass: rules.midiToPitchClass(note.midiNote),
        noteWithOctave: rules.midiToNoteWithOctave(note.midiNote),
        startTick: boundedStart,
        durationTicks: max(1, boundedDuration),
      );
    },
  ).toList();

  state = state.copyWith(
    notes: [...state.notes, ...created],
    selectedNoteIds: created.map((note) => note.id).toSet(),
  );
  return (createdCount: created.length, truncated: truncated);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/store/piano_roll_store_test.dart`

Expected: PASS with the importer test green.

- [ ] **Step 5: Commit**

```bash
git add lib/store/piano_roll_store.dart test/store/piano_roll_store_test.dart
git commit -m "feat: add piano roll hum note import"
```

## Task 3: Add The Hum Session Store With A Fakeable Mic Session Interface

**Files:**
- Modify: `lib/models/hum_to_midi.dart`
- Create: `lib/store/hum_to_midi_store.dart`
- Create: `lib/utils/mic_pitch_session.dart`
- Test: `test/store/hum_to_midi_store_test.dart`

- [ ] **Step 1: Write the failing store tests**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/store/hum_to_midi_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/utils/mic_pitch_session.dart';

class _FakeMicPitchSession implements MicPitchSession {
  final _controller = StreamController<PitchFrame>.broadcast();
  bool permissionGranted = true;
  bool startCalled = false;
  bool stopCalled = false;

  void emit(PitchFrame frame) => _controller.add(frame);

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<Stream<PitchFrame>> start() async {
    startCalled = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  test('startRecording enters recording when permission is granted', () async {
    final fake = _FakeMicPitchSession();
    final container = ProviderContainer(
      overrides: [micPitchSessionProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(humToMidiProvider.notifier).startRecording();

    final state = container.read(humToMidiProvider);
    expect(fake.startCalled, isTrue);
    expect(state.status, HumToMidiStatus.recording);
  });

  test('stopRecording imports finalized notes into the piano roll', () async {
    final fake = _FakeMicPitchSession();
    final container = ProviderContainer(
      overrides: [micPitchSessionProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(humToMidiProvider.notifier).startRecording();
    fake.emit(const PitchFrame(timestampMs: 0, frequencyHz: 440, midiNote: 69, centsOffset: 0, amplitude: 0.9, confidence: 0.97, isSilence: false));
    fake.emit(const PitchFrame(timestampMs: 180, frequencyHz: 440, midiNote: 69, centsOffset: 0, amplitude: 0.9, confidence: 0.97, isSilence: false));
    await Future<void>.delayed(Duration.zero);

    await container.read(humToMidiProvider.notifier).stopRecording();

    final humState = container.read(humToMidiProvider);
    final pianoRollState = container.read(pianoRollProvider);
    expect(fake.stopCalled, isTrue);
    expect(humState.status, HumToMidiStatus.completed);
    expect(pianoRollState.notes.single.midiNote, 69);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/store/hum_to_midi_store_test.dart`

Expected: FAIL because `MicPitchSession`, `humToMidiProvider`, and `HumToMidiState` are missing.

- [ ] **Step 3: Write the minimal interface and store**

```dart
// lib/utils/mic_pitch_session.dart
import '../models/hum_to_midi.dart';

abstract class MicPitchSession {
  Future<bool> hasPermission();
  Future<Stream<PitchFrame>> start();
  Future<void> stop();
  Future<void> dispose();
}
```

```dart
// lib/models/hum_to_midi.dart
class HumToMidiState {
  final HumToMidiStatus status;
  final List<PitchFrame> frames;
  final int? liveMidiNote;
  final int? startedAtMs;
  final String? feedbackMessage;
  final String? errorMessage;

  const HumToMidiState({
    this.status = HumToMidiStatus.idle,
    this.frames = const <PitchFrame>[],
    this.liveMidiNote,
    this.startedAtMs,
    this.feedbackMessage,
    this.errorMessage,
  });

  HumToMidiState copyWith({
    HumToMidiStatus? status,
    List<PitchFrame>? frames,
    int? Function()? liveMidiNote,
    int? Function()? startedAtMs,
    String? Function()? feedbackMessage,
    String? Function()? errorMessage,
  }) {
    return HumToMidiState(
      status: status ?? this.status,
      frames: frames ?? this.frames,
      liveMidiNote: liveMidiNote != null ? liveMidiNote() : this.liveMidiNote,
      startedAtMs: startedAtMs != null ? startedAtMs() : this.startedAtMs,
      feedbackMessage: feedbackMessage != null ? feedbackMessage() : this.feedbackMessage,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}
```

```dart
// lib/store/hum_to_midi_store.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hum_to_midi.dart';
import '../schema/rules/mono_pitch_rules.dart' as rules;
import '../store/piano_roll_store.dart';
import '../utils/mic_pitch_session.dart';

final micPitchSessionProvider = Provider<MicPitchSession>((_) {
  throw UnimplementedError('Override or provide a concrete mic session');
});

class HumToMidiNotifier extends Notifier<HumToMidiState> {
  StreamSubscription<PitchFrame>? _framesSub;

  @override
  HumToMidiState build() => const HumToMidiState();

  Future<void> startRecording() async {
    final session = ref.read(micPitchSessionProvider);
    state = state.copyWith(
      status: HumToMidiStatus.requestingPermission,
      errorMessage: () => null,
      feedbackMessage: () => null,
      frames: const <PitchFrame>[],
      liveMidiNote: () => null,
      startedAtMs: () => null,
    );
    if (!await session.hasPermission()) {
      state = state.copyWith(
        status: HumToMidiStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }
    final stream = await session.start();
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    _framesSub = stream.listen((frame) {
      state = state.copyWith(
        status: HumToMidiStatus.recording,
        frames: [...state.frames, frame],
        liveMidiNote: () => frame.midiNote,
      );
    });
    state = state.copyWith(
      status: HumToMidiStatus.recording,
      startedAtMs: () => startedAtMs,
    );
  }

  Future<void> stopRecording() async {
    final session = ref.read(micPitchSessionProvider);
    state = state.copyWith(status: HumToMidiStatus.processing);
    await _framesSub?.cancel();
    await session.stop();
    final segmented = rules.segmentStableNotes(state.frames);
    final pianoRoll = ref.read(pianoRollProvider);
    final anchorTick =
        ref.read(pianoRollProvider.notifier).suggestedImportAnchorTick();
    final imported = rules.quantizeNotesToTicks(
      notes: segmented,
      anchorTick: anchorTick,
      tempo: pianoRoll.config.tempo,
      timeSignature: pianoRoll.config.timeSignature,
      snapTicks: pianoRoll.snapTicks,
    );
    final importResult =
        ref.read(pianoRollProvider.notifier).appendImportedNotes(imported);
    final feedbackMessage = imported.isEmpty
        ? 'No stable note detected'
        : importResult.truncated
        ? 'Take clipped to fit the piano roll'
        : null;
    state = state.copyWith(
      status: HumToMidiStatus.completed,
      frames: const <PitchFrame>[],
      liveMidiNote: () => null,
      startedAtMs: () => null,
      feedbackMessage: () => feedbackMessage,
    );
  }
}

final humToMidiProvider =
    NotifierProvider<HumToMidiNotifier, HumToMidiState>(HumToMidiNotifier.new);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/store/hum_to_midi_store_test.dart`

Expected: PASS with both store tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/models/hum_to_midi.dart lib/store/hum_to_midi_store.dart lib/utils/mic_pitch_session.dart test/store/hum_to_midi_store_test.dart
git commit -m "feat: add hum to midi recording store"
```

## Task 4: Add The Mobile Record Adapter And Platform Permissions

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `lib/utils/mic_pitch_session.dart`

- [ ] **Step 1: Add the dependency and platform permissions**

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  music_notes: ^0.11.0
  shared_preferences: ^2.3.4
  uuid: ^4.5.1
  go_router: ^14.8.1
  audioplayers: ^6.6.0
  path_provider: ^2.1.5
  record: ^6.2.1
```

```kotlin
// android/app/build.gradle.kts
defaultConfig {
    applicationId = "io.bytebakehouse.muzician"
    minSdk = 23
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <application
        android:label="muzician"
        android:name="${applicationName}"
        android:icon="@mipmap/launcher_icon">
```

```xml
<!-- ios/Runner/Info.plist -->
<key>NSMicrophoneUsageDescription</key>
<string>Allow microphone access to turn your humming into piano roll notes.</string>
```

- [ ] **Step 2: Install dependencies**

Run: `flutter pub get`

Expected: PASS with `record` resolved into `.dart_tool/package_config.json`.

- [ ] **Step 3: Replace the throwing provider with a `record` implementation**

```dart
// lib/utils/mic_pitch_session.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../models/hum_to_midi.dart';
import '../schema/rules/mono_pitch_rules.dart' as rules;

class RecordMicPitchSession implements MicPitchSession {
  RecordMicPitchSession({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<PitchFrame>> start() async {
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    return stream.map((bytes) {
      final frequency = rules.estimateDominantFrequency(bytes, sampleRate: 16000);
      final midiNote = frequency == null ? null : rules.frequencyToMidi(frequency);
      return PitchFrame(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        frequencyHz: frequency ?? 0,
        midiNote: midiNote,
        centsOffset: 0,
        amplitude: rules.estimateNormalizedAmplitude(bytes),
        confidence: midiNote == null ? 0 : 1,
        isSilence: midiNote == null,
      );
    });
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
```

```dart
// lib/store/hum_to_midi_store.dart
final micPitchSessionProvider = Provider<MicPitchSession>(
  (_) => RecordMicPitchSession(),
);
```

- [ ] **Step 4: Verify the adapter compiles**

Run: `flutter analyze lib/utils/mic_pitch_session.dart lib/store/hum_to_midi_store.dart`

Expected: PASS with no analyzer errors in the adapter or store.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist lib/utils/mic_pitch_session.dart lib/store/hum_to_midi_store.dart
git commit -m "feat: add mobile hum recording adapter"
```

## Task 5: Add The Piano Roll Recorder Panel And Screen Wiring

**Files:**
- Create: `lib/features/piano_roll/piano_roll_hum_recorder.dart`
- Modify: `lib/features/piano_roll/piano_roll_feature.dart`
- Modify: `lib/main.dart`
- Test: `test/features/piano_roll/piano_roll_hum_recorder_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_hum_recorder.dart';
import 'package:muzician/models/hum_to_midi.dart';

void main() {
  testWidgets('shows the live note and stop button while recording', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PianoRollHumRecorderCard(
            status: HumToMidiStatus.recording,
            liveNoteLabel: 'A4',
            statusLabel: 'Stable',
            elapsedLabel: '00:03',
            onStart: null,
            onStop: null,
          ),
        ),
      ),
    );

    expect(find.text('Hum to MIDI'), findsOneWidget);
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('Stable'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart`

Expected: FAIL because `PianoRollHumRecorderCard` does not exist.

- [ ] **Step 3: Write the widget and mount it in the piano roll screen**

```dart
// lib/features/piano_roll/piano_roll_hum_recorder.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/hum_to_midi.dart';
import '../../store/hum_to_midi_store.dart';
import '../../theme/muzician_theme.dart';
import '../../schema/rules/mono_pitch_rules.dart' as rules;

class PianoRollHumRecorderPanel extends ConsumerStatefulWidget {
  const PianoRollHumRecorderPanel({super.key});

  @override
  ConsumerState<PianoRollHumRecorderPanel> createState() =>
      _PianoRollHumRecorderPanelState();
}

class _PianoRollHumRecorderPanelState
    extends ConsumerState<PianoRollHumRecorderPanel> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final state = ref.watch(humToMidiProvider);
    if (state.status == HumToMidiStatus.recording && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (state.status != HumToMidiStatus.recording) {
      _ticker?.cancel();
      _ticker = null;
    }

    final elapsed = state.startedAtMs == null
        ? Duration.zero
        : Duration(
            milliseconds:
                DateTime.now().millisecondsSinceEpoch - state.startedAtMs!,
          );
    final elapsedLabel =
        '${elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return PianoRollHumRecorderCard(
      status: state.status,
      liveNoteLabel: state.liveMidiNote == null ? 'No pitch' : rules.midiToNoteLabel(state.liveMidiNote!),
      statusLabel: switch (state.status) {
        HumToMidiStatus.recording => state.liveMidiNote == null ? 'No pitch' : 'Stable',
        HumToMidiStatus.processing => 'Processing',
        HumToMidiStatus.error => state.errorMessage ?? 'Error',
        HumToMidiStatus.completed => state.feedbackMessage ?? 'Imported',
        _ => 'Ready',
      },
      elapsedLabel: state.status == HumToMidiStatus.recording ? elapsedLabel : 'Idle',
      onStart: state.status == HumToMidiStatus.idle
          ? () => ref.read(humToMidiProvider.notifier).startRecording()
          : null,
      onStop: state.status == HumToMidiStatus.recording
          ? () => ref.read(humToMidiProvider.notifier).stopRecording()
          : null,
    );
  }
}

class PianoRollHumRecorderCard extends StatelessWidget {
  final HumToMidiStatus status;
  final String liveNoteLabel;
  final String statusLabel;
  final String elapsedLabel;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  const PianoRollHumRecorderCard({
    super.key,
    required this.status,
    required this.liveNoteLabel,
    required this.statusLabel,
    required this.elapsedLabel,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isRecording = status == HumToMidiStatus.recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hum to MIDI', style: TextStyle(color: MuzicianTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(liveNoteLabel, style: const TextStyle(color: MuzicianTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(statusLabel, style: const TextStyle(color: MuzicianTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Text(elapsedLabel, style: const TextStyle(color: MuzicianTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: isRecording ? onStop : onStart,
              child: Text(isRecording ? 'Stop' : 'Record'),
            ),
          ],
        ),
      ],
    );
  }
}
```

```dart
// lib/features/piano_roll/piano_roll_feature.dart
export 'piano_roll_hum_recorder.dart';
```

```dart
// lib/main.dart
children: [
  _PianoRollPanelAccessBar(
    activePanel: _activePanel,
    onToggle: _togglePanel,
  ),
  const _Card(child: PianoRollHumRecorderPanel()),
  AnimatedSize(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeInOut,
    child: _activePanelWidget(),
  ),
```

- [ ] **Step 4: Run the widget test to verify it passes**

Run: `flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart`

Expected: PASS with the recorder card test green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/piano_roll/piano_roll_hum_recorder.dart lib/features/piano_roll/piano_roll_feature.dart lib/main.dart test/features/piano_roll/piano_roll_hum_recorder_test.dart
git commit -m "feat: add piano roll hum recorder panel"
```

## Task 6: Document, Run Full Verification, And Sanity Check On Device

**Files:**
- Modify: `docs/piano_roll.md`

- [ ] **Step 1: Update the piano roll docs**

```md
## Live Hum to MIDI

The piano roll now includes a mobile-only `Hum to MIDI` recorder. It captures mono microphone input, estimates one stable pitch at a time, lightly quantizes timing after stop, and appends the finalized notes to the current piano roll instead of replacing existing content.
```

- [ ] **Step 2: Run the focused automated checks**

Run:

```bash
flutter test test/schema/rules/mono_pitch_rules_test.dart
flutter test test/store/piano_roll_store_test.dart
flutter test test/store/hum_to_midi_store_test.dart
flutter test test/features/piano_roll/piano_roll_hum_recorder_test.dart
flutter analyze
```

Expected: PASS for all four test commands and `flutter analyze`.

- [ ] **Step 3: Run a mobile smoke test**

Run:

```bash
flutter run -d <ios-or-android-device>
```

Expected manual results:

- starting recording prompts for microphone permission once
- humming a steady `A4` shows a stable live note label
- stopping creates editable piano roll notes
- existing piano roll notes remain in place
- a longer take expands the measure count when needed

- [ ] **Step 4: Capture the final diff for review**

```bash
git status --short
git diff --stat
```

Expected: only the planned hum-to-MIDI files and doc updates are present.

- [ ] **Step 5: Commit**

```bash
git add docs/piano_roll.md
git commit -m "docs: describe piano roll hum to midi flow"
```
