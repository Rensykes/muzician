# Song Audio Tracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `audio` track type to the Song workspace that hosts clips coming from microphone recordings or imported WAV/MP3/M4A files, rendered as waveform blocks on the existing timeline.

**Architecture:** Four-layer extension of the existing Song stack. Domain layer gets a new `AudioAsset` + `AudioClipPattern` pair (1:1 with each clip, no reuse). A new `SongAudioRepository` owns audio files on disk under `appDocs/song_audio/`. A `SongAudioRecorderNotifier` runs the overdub state machine (count-in → recording → preview → commit). The existing `SongPlaybackNotifier` gets a third sink that schedules `AudioPlayer` instances for audio clips during playback. UI extends the existing bottom-sheet picker with two new actions and adds a waveform painter for clip bodies.

**Tech Stack:** Flutter 3.x, Riverpod, `record` (already present), `audioplayers` (already present), `path_provider` (already present), new deps `file_picker` and `permission_handler`. Tests via `flutter_test` matching existing `test/` patterns.

**Spec:** `docs/superpowers/specs/2026-05-29-song-audio-tracks-design.md`

---

## File Structure

```
lib/
  models/
    song_project.dart                       (MODIFY) enums + AudioAsset/AudioClipPattern + SongProject fields
  schema/rules/
    song_audio_rules.dart                   (NEW)    audioClipLengthTicks + WAV header parser + peak compute helpers
  store/
    song_audio_repository.dart              (NEW)    file-system facade + integrity/orphan scan
    song_audio_recorder_store.dart          (NEW)    overdub state machine
    song_project_store.dart                 (MODIFY) addAudioClip/removeAudioClip, default name, orphan cleanup branch
    song_playback_store.dart                (MODIFY) audioClipSinkProvider + clip scheduling
  features/song/
    song_arranger_timeline.dart             (MODIFY) audio clip body branch
    song_audio_clip_body.dart               (NEW)    AudioClipBody widget + AudioWaveformPainter
    song_audio_recorder_sheet.dart          (NEW)    modal: count-in / record / preview / commit
    song_clip_action_bar.dart               (MODIFY) audio clip actions (no Make Unique)
    song_track_header.dart                  (MODIFY) "+ Audio Track" button + audio-type label
    song_import_picker_sheet.dart           (MODIFY) inject "Record audio" / "Import audio" entries
    song_screen.dart                        (MODIFY) register recorder sheet launcher
  utils/
    wav_writer.dart                         (NEW)    PCM int16 → WAV bytes helper used by recorder finalisation
docs/
  song_workspace.md                         (MODIFY) document audio tracks in v1.1
pubspec.yaml                                (MODIFY) add file_picker, permission_handler
test/
  schema/rules/song_audio_rules_test.dart   (NEW)
  store/song_audio_repository_test.dart     (NEW)
  store/song_audio_recorder_store_test.dart (NEW)
  store/song_project_store_test.dart        (MODIFY) audio clip add/remove + orphan cleanup
  store/song_playback_store_test.dart       (MODIFY) audio clip scheduling
  features/song/song_audio_clip_body_test.dart (NEW)
  features/song/song_audio_recorder_sheet_test.dart (NEW)
  models/song_project_test.dart             (MODIFY if exists; else NEW) audio JSON round-trip
```

**Boundaries:**
- `models/` is pure data + serialization. No I/O, no Flutter.
- `schema/rules/song_audio_rules.dart` is pure functions only (tick math, WAV header parsing, peak compression). No I/O.
- `store/song_audio_repository.dart` is the only place that touches the filesystem and `record` package.
- `store/song_audio_recorder_store.dart` owns the recorder state machine but delegates I/O to the repository and audio playback to a `Recorder` interface injectable for tests.
- UI never imports `dart:io` or the `record` package directly.

---

## Task 1: Add `AudioAsset` and `AudioClipPattern` domain types

**Files:**
- Modify: `lib/models/song_project.dart`
- Test: `test/models/song_project_test.dart` (create if missing)

- [ ] **Step 1: Write the failing test**

Create `test/models/song_project_test.dart` if it does not yet exist:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  group('AudioAsset', () {
    test('JSON round-trip preserves all fields', () {
      const asset = AudioAsset(
        id: 'asset-1',
        durationMs: 4321,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [0, 64, 128, 192, 255],
        sourceLabel: 'Recording',
      );
      final json = asset.toJson();
      final restored = AudioAsset.fromJson(json);
      expect(restored.id, 'asset-1');
      expect(restored.durationMs, 4321);
      expect(restored.sampleRate, 44100);
      expect(restored.channels, 1);
      expect(restored.format, 'wav');
      expect(restored.peaks, [0, 64, 128, 192, 255]);
      expect(restored.sourceLabel, 'Recording');
    });
  });

  group('AudioClipPattern', () {
    test('JSON round-trip preserves all fields', () {
      const p = AudioClipPattern(id: 'p1', name: 'Take 1', assetId: 'asset-1');
      final json = p.toJson();
      final restored = AudioClipPattern.fromJson(json);
      expect(restored.id, 'p1');
      expect(restored.name, 'Take 1');
      expect(restored.assetId, 'asset-1');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/song_project_test.dart`
Expected: FAIL with `Undefined name 'AudioAsset'` / `Undefined name 'AudioClipPattern'`.

- [ ] **Step 3: Add enum cases and classes to `song_project.dart`**

In `lib/models/song_project.dart` extend the enums and append the two new classes after `DrumPattern`. Replace these two enum declarations:

```dart
enum SongTrackType { note, drum, audio }

enum SongPatternType { note, drum, audio }
```

Append after the `DrumPattern` class:

```dart
// ── AudioAsset ────────────────────────────────────────────────────────────────

class AudioAsset {
  final String id;
  final int durationMs;
  final int sampleRate;
  final int channels;
  final String format; // 'wav' | 'mp3' | 'm4a'
  final List<int> peaks;
  final String sourceLabel;

  const AudioAsset({
    required this.id,
    required this.durationMs,
    required this.sampleRate,
    required this.channels,
    required this.format,
    required this.peaks,
    required this.sourceLabel,
  });

  AudioAsset copyWith({
    String? id,
    int? durationMs,
    int? sampleRate,
    int? channels,
    String? format,
    List<int>? peaks,
    String? sourceLabel,
  }) => AudioAsset(
    id: id ?? this.id,
    durationMs: durationMs ?? this.durationMs,
    sampleRate: sampleRate ?? this.sampleRate,
    channels: channels ?? this.channels,
    format: format ?? this.format,
    peaks: peaks ?? this.peaks,
    sourceLabel: sourceLabel ?? this.sourceLabel,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'durationMs': durationMs,
    'sampleRate': sampleRate,
    'channels': channels,
    'format': format,
    'peaks': peaks,
    'sourceLabel': sourceLabel,
  };

  factory AudioAsset.fromJson(Map<String, dynamic> json) => AudioAsset(
    id: json['id'] as String,
    durationMs: json['durationMs'] as int,
    sampleRate: json['sampleRate'] as int,
    channels: json['channels'] as int,
    format: json['format'] as String,
    peaks: List<int>.from(json['peaks'] as List),
    sourceLabel: json['sourceLabel'] as String,
  );
}

// ── AudioClipPattern ──────────────────────────────────────────────────────────

class AudioClipPattern {
  final String id;
  final String name;
  final String assetId;

  const AudioClipPattern({
    required this.id,
    required this.name,
    required this.assetId,
  });

  AudioClipPattern copyWith({String? id, String? name, String? assetId}) =>
      AudioClipPattern(
        id: id ?? this.id,
        name: name ?? this.name,
        assetId: assetId ?? this.assetId,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'assetId': assetId,
  };

  factory AudioClipPattern.fromJson(Map<String, dynamic> json) =>
      AudioClipPattern(
        id: json['id'] as String,
        name: json['name'] as String,
        assetId: json['assetId'] as String,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/song_project_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/song_project.dart test/models/song_project_test.dart
git commit -m "feat(song): add AudioAsset and AudioClipPattern domain types"
```

---

## Task 2: Extend `SongProject` with audio collections

**Files:**
- Modify: `lib/models/song_project.dart`
- Test: `test/models/song_project_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/models/song_project_test.dart`:

```dart
  group('SongProject with audio', () {
    test('defaults audioAssets and audioPatterns to empty', () {
      final p = SongProject(
        config: SongProjectConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: const [],
        audioPatterns: const [],
      );
      expect(p.audioAssets, isEmpty);
      expect(p.audioPatterns, isEmpty);
    });

    test('legacy JSON without audio fields loads with empty lists', () {
      final json = {
        'config': {
          'tempo': 120,
          'timeSignature': {'beatsPerMeasure': 4, 'beatUnit': 4},
          'totalMeasures': 4,
        },
        'tracks': [],
        'clips': [],
        'notePatterns': [],
        'drumPatterns': [],
      };
      final p = SongProject.fromJson(json);
      expect(p.audioAssets, isEmpty);
      expect(p.audioPatterns, isEmpty);
    });

    test('round-trips audio assets and patterns', () {
      final p = SongProject(
        config: SongProjectConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: const [
          AudioAsset(
            id: 'a1',
            durationMs: 1000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [0, 128, 255],
            sourceLabel: 'Recording',
          ),
        ],
        audioPatterns: const [
          AudioClipPattern(id: 'p1', name: 'Take', assetId: 'a1'),
        ],
      );
      final restored = SongProject.fromJson(p.toJson());
      expect(restored.audioAssets, hasLength(1));
      expect(restored.audioAssets.first.id, 'a1');
      expect(restored.audioPatterns.first.assetId, 'a1');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/song_project_test.dart`
Expected: FAIL with `The named parameter 'audioAssets' isn't defined`.

- [ ] **Step 3: Extend `SongProject`**

Replace the `SongProject` class in `lib/models/song_project.dart`:

```dart
class SongProject {
  final SongProjectConfig config;
  final List<SongTrack> tracks;
  final List<SongClipInstance> clips;
  final List<NotePattern> notePatterns;
  final List<DrumPattern> drumPatterns;
  final List<AudioAsset> audioAssets;
  final List<AudioClipPattern> audioPatterns;

  const SongProject({
    required this.config,
    required this.tracks,
    required this.clips,
    required this.notePatterns,
    required this.drumPatterns,
    this.audioAssets = const [],
    this.audioPatterns = const [],
  });

  SongProject copyWith({
    SongProjectConfig? config,
    List<SongTrack>? tracks,
    List<SongClipInstance>? clips,
    List<NotePattern>? notePatterns,
    List<DrumPattern>? drumPatterns,
    List<AudioAsset>? audioAssets,
    List<AudioClipPattern>? audioPatterns,
  }) => SongProject(
    config: config ?? this.config,
    tracks: tracks ?? this.tracks,
    clips: clips ?? this.clips,
    notePatterns: notePatterns ?? this.notePatterns,
    drumPatterns: drumPatterns ?? this.drumPatterns,
    audioAssets: audioAssets ?? this.audioAssets,
    audioPatterns: audioPatterns ?? this.audioPatterns,
  );

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'clips': clips.map((c) => c.toJson()).toList(),
    'notePatterns': notePatterns.map((p) => p.toJson()).toList(),
    'drumPatterns': drumPatterns.map((p) => p.toJson()).toList(),
    'audioAssets': audioAssets.map((a) => a.toJson()).toList(),
    'audioPatterns': audioPatterns.map((p) => p.toJson()).toList(),
  };

  factory SongProject.fromJson(Map<String, dynamic> json) => SongProject(
    config: SongProjectConfig.fromJson(json['config'] as Map<String, dynamic>),
    tracks: (json['tracks'] as List<dynamic>)
        .map((t) => SongTrack.fromJson(t as Map<String, dynamic>))
        .toList(),
    clips: (json['clips'] as List<dynamic>)
        .map((c) => SongClipInstance.fromJson(c as Map<String, dynamic>))
        .toList(),
    notePatterns: (json['notePatterns'] as List<dynamic>)
        .map((p) => NotePattern.fromJson(p as Map<String, dynamic>))
        .toList(),
    drumPatterns: (json['drumPatterns'] as List<dynamic>)
        .map((p) => DrumPattern.fromJson(p as Map<String, dynamic>))
        .toList(),
    audioAssets: (json['audioAssets'] as List<dynamic>? ?? const [])
        .map((a) => AudioAsset.fromJson(a as Map<String, dynamic>))
        .toList(),
    audioPatterns: (json['audioPatterns'] as List<dynamic>? ?? const [])
        .map((p) => AudioClipPattern.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/song_project_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyzer and fix any switch-exhaustiveness errors**

Run: `flutter analyze`
Expected: a few errors of the form `The type 'SongTrackType' is not exhaustively matched by the switch cases` in `song_project_store.dart` (because we added `audio`). Fix them by:
- In `lib/store/song_project_store.dart`, locate the `addTrack` method and update the `defaultName` switch:

```dart
final defaultName = switch (type) {
  SongTrackType.note => 'Note Track',
  SongTrackType.drum => 'Drum Track',
  SongTrackType.audio => 'Audio Track',
};
```

- In the same file, the `renameTrack` method has a `fallbackName` ternary on track type — replace it with a switch:

```dart
final fallbackName = switch (track.type) {
  SongTrackType.note => 'Note Track',
  SongTrackType.drum => 'Drum Track',
  SongTrackType.audio => 'Audio Track',
};
```

- In `deleteClip`, the switch on `clip.patternType` needs an audio branch. Replace with:

```dart
state = switch (clip.patternType) {
  SongPatternType.note => state.copyWith(
    notePatterns:
        state.notePatterns.where((p) => p.id != clip.patternId).toList(),
  ),
  SongPatternType.drum => state.copyWith(
    drumPatterns:
        state.drumPatterns.where((p) => p.id != clip.patternId).toList(),
  ),
  SongPatternType.audio => state.copyWith(
    audioPatterns:
        state.audioPatterns.where((p) => p.id != clip.patternId).toList(),
  ),
};
```

Run analyzer again: `flutter analyze`. Expected: no `non_exhaustive_switch` errors. Other warnings can remain; do not chase unrelated lint.

- [ ] **Step 6: Commit**

```bash
git add lib/models/song_project.dart lib/store/song_project_store.dart test/models/song_project_test.dart
git commit -m "feat(song): wire audio collections through SongProject"
```

---

## Task 3: Tick math for audio clip length

**Files:**
- Create: `lib/schema/rules/song_audio_rules.dart`
- Test: `test/schema/rules/song_audio_rules_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/schema/rules/song_audio_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_audio_rules.dart';

void main() {
  group('audioClipLengthTicks', () {
    final ts44 = const TimeSignature(beatsPerMeasure: 4, beatUnit: 4);

    test('at 60 BPM, 4 ticks per beat, 1000 ms == 4 ticks', () {
      final cfg = SongProjectConfig(
        tempo: 60,
        timeSignature: ts44,
        totalMeasures: 4,
      );
      final asset = AudioAsset(
        id: 'x',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: const [],
        sourceLabel: '',
      );
      expect(audioClipLengthTicks(asset, cfg), 4);
    });

    test('at 120 BPM, 1000 ms == 8 ticks', () {
      final cfg = SongProjectConfig(
        tempo: 120,
        timeSignature: ts44,
        totalMeasures: 4,
      );
      final asset = AudioAsset(
        id: 'x',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: const [],
        sourceLabel: '',
      );
      expect(audioClipLengthTicks(asset, cfg), 8);
    });

    test('clamps to minimum of 1 tick for very short audio', () {
      final cfg = SongProjectConfig(
        tempo: 120,
        timeSignature: ts44,
        totalMeasures: 4,
      );
      final asset = AudioAsset(
        id: 'x',
        durationMs: 5,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: const [],
        sourceLabel: '',
      );
      expect(audioClipLengthTicks(asset, cfg), greaterThanOrEqualTo(1));
    });
  });

  group('audioClipStartMs', () {
    test('at 60 BPM, tick 4 (4 ticks per beat) is 1000 ms', () {
      final cfg = SongProjectConfig(
        tempo: 60,
        timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 4,
      );
      expect(audioTickToMs(4, cfg), 1000);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/song_audio_rules_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:muzician/schema/rules/song_audio_rules.dart'`.

- [ ] **Step 3: Implement the rules file**

Create `lib/schema/rules/song_audio_rules.dart`:

```dart
/// Pure functions linking audio assets to the project's tick grid.
library;

import 'dart:math' as math;

import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'song_rules.dart' show songTicksPerMeasure;

int _ticksPerBeat(TimeSignature ts) => ts.beatUnit == 8 ? 2 : 4;

/// Returns the grid length, in ticks, that the given asset should occupy at
/// the project's current tempo.  Audio always plays at native rate, so the
/// real duration is the source of truth and this is a derived view.
int audioClipLengthTicks(AudioAsset asset, SongProjectConfig config) {
  final beatsPerSecond = config.tempo / 60.0;
  final ticksPerBeat = _ticksPerBeat(config.timeSignature);
  final ticks =
      (asset.durationMs / 1000.0) * beatsPerSecond * ticksPerBeat;
  return math.max(1, ticks.round());
}

/// Returns the wall-clock time, in milliseconds since transport start, of the
/// given absolute tick at the project's current tempo.
int audioTickToMs(int tick, SongProjectConfig config) {
  final beatsPerSecond = config.tempo / 60.0;
  final ticksPerBeat = _ticksPerBeat(config.timeSignature);
  final beats = tick / ticksPerBeat;
  return (beats / beatsPerSecond * 1000.0).round();
}

/// Ensures the project's total measure count covers the given end tick — same
/// behaviour as the note/drum side, exposed here so the audio paths do not
/// need to import `song_rules` directly.
int requiredMeasuresForEndTick(int endTick, SongProjectConfig config) {
  final perMeasure = songTicksPerMeasure(config.timeSignature);
  return math.max(config.totalMeasures, (endTick / perMeasure).ceil());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/song_audio_rules_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/song_audio_rules.dart test/schema/rules/song_audio_rules_test.dart
git commit -m "feat(song): derive audio clip length and ms from tick grid"
```

---

## Task 4: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the two packages**

Open `pubspec.yaml` and add under `dependencies:` (alphabetical order with existing entries):

```yaml
  file_picker: ^8.1.4
  permission_handler: ^11.3.1
```

- [ ] **Step 2: Resolve packages**

Run: `flutter pub get`
Expected: pub fetches both packages without conflicts. If a conflict surfaces, do not edit other version constraints unilaterally — stop and report.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add file_picker and permission_handler for audio tracks"
```

---

## Task 5: WAV writer + header parser helpers

**Files:**
- Create: `lib/utils/wav_writer.dart`
- Test: `test/utils/wav_writer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/utils/wav_writer_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  group('WAV writer', () {
    test('writeWavPcm16Mono produces a parseable header', () {
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final bytes = writeWavPcm16Mono(samples, sampleRate: 44100);

      // RIFF header marker
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      // WAVE format marker
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

      final header = parseWavHeader(bytes);
      expect(header.sampleRate, 44100);
      expect(header.channels, 1);
      expect(header.bitsPerSample, 16);
      // 44100 samples * 2 bytes = 88200, divided by sampleRate*channels*bytes per sample = 1.0 second
      expect(header.durationMs, 1000);
    });

    test('parseWavHeader rejects non-WAV bytes', () {
      final bogus = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      expect(() => parseWavHeader(bogus), throwsA(isA<FormatException>()));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/wav_writer_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:muzician/utils/wav_writer.dart'`.

- [ ] **Step 3: Implement WAV writer + parser**

Create `lib/utils/wav_writer.dart`:

```dart
/// Minimal WAV PCM 16-bit utilities.  Used by the audio recorder when
/// finalising a take, and by the repository when probing imported files.
library;

import 'dart:typed_data';

class WavHeader {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int durationMs;

  const WavHeader({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.durationMs,
  });
}

/// Wraps mono PCM 16-bit samples in a canonical RIFF/WAVE container.
Uint8List writeWavPcm16Mono(Int16List samples, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final dataSize = samples.length * 2;
  final fileSize = 36 + dataSize;

  final bytes = BytesBuilder();
  bytes.add(_ascii('RIFF'));
  bytes.add(_u32(fileSize));
  bytes.add(_ascii('WAVE'));
  bytes.add(_ascii('fmt '));
  bytes.add(_u32(16));            // PCM fmt chunk size
  bytes.add(_u16(1));             // PCM format
  bytes.add(_u16(channels));
  bytes.add(_u32(sampleRate));
  bytes.add(_u32(byteRate));
  bytes.add(_u16(blockAlign));
  bytes.add(_u16(bitsPerSample));
  bytes.add(_ascii('data'));
  bytes.add(_u32(dataSize));
  bytes.add(samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  ));
  return bytes.toBytes();
}

/// Parses the RIFF/WAVE header at the start of [wav] and returns the audio
/// metadata.  Only PCM is supported (most recordings from `record` are PCM).
WavHeader parseWavHeader(Uint8List wav) {
  if (wav.length < 44) {
    throw const FormatException('WAV too short');
  }
  final bd = ByteData.sublistView(wav);
  if (String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }
  // The 'fmt ' chunk traditionally starts at offset 12.
  if (String.fromCharCodes(wav.sublist(12, 16)) != 'fmt ') {
    throw const FormatException('Missing fmt chunk at canonical offset');
  }
  final channels = bd.getUint16(22, Endian.little);
  final sampleRate = bd.getUint32(24, Endian.little);
  final bitsPerSample = bd.getUint16(34, Endian.little);

  // Find the 'data' chunk to compute the sample count.  The chunk may not be
  // immediately after fmt if there is a LIST/INFO subchunk first.
  var cursor = 36;
  while (cursor + 8 <= wav.length) {
    final tag = String.fromCharCodes(wav.sublist(cursor, cursor + 4));
    final size = bd.getUint32(cursor + 4, Endian.little);
    if (tag == 'data') {
      final bytesPerFrame = channels * (bitsPerSample ~/ 8);
      if (bytesPerFrame == 0 || sampleRate == 0) {
        throw const FormatException('Invalid WAV metadata');
      }
      final frames = size ~/ bytesPerFrame;
      final durationMs = (frames * 1000) ~/ sampleRate;
      return WavHeader(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        durationMs: durationMs,
      );
    }
    cursor += 8 + size;
  }
  throw const FormatException('Missing data chunk');
}

List<int> _ascii(String s) => s.codeUnits;

List<int> _u16(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/wav_writer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/wav_writer.dart test/utils/wav_writer_test.dart
git commit -m "feat: add minimal WAV writer and header parser"
```

---

## Task 6: Peak computation for waveforms

**Files:**
- Modify: `lib/schema/rules/song_audio_rules.dart`
- Test: `test/schema/rules/song_audio_rules_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/schema/rules/song_audio_rules_test.dart`:

```dart
  group('computePeaksFromInt16', () {
    test('downsamples to requested bin count', () {
      // 1000 samples, all max amplitude
      final samples = Int16List.fromList(
        List<int>.filled(1000, 32767),
      );
      final peaks = computePeaksFromInt16(samples, targetBins: 100);
      expect(peaks.length, 100);
      expect(peaks.every((p) => p == 255), isTrue);
    });

    test('silence produces zero peaks', () {
      final samples = Int16List.fromList(List<int>.filled(1000, 0));
      final peaks = computePeaksFromInt16(samples, targetBins: 50);
      expect(peaks.every((p) => p == 0), isTrue);
    });

    test('returns at least 1 bin for non-empty input', () {
      final samples = Int16List.fromList([1000, -1000]);
      final peaks = computePeaksFromInt16(samples, targetBins: 50);
      expect(peaks, isNotEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/song_audio_rules_test.dart`
Expected: FAIL with `Undefined name 'computePeaksFromInt16'`.

- [ ] **Step 3: Add peak computation**

Append to `lib/schema/rules/song_audio_rules.dart`:

```dart
/// Compresses a PCM 16-bit sample buffer down to [targetBins] amplitude bins
/// scaled to 0..255.  Each bin holds the absolute maximum across the samples
/// assigned to it.  Used to render audio clip waveforms on the timeline.
List<int> computePeaksFromInt16(Int16List samples, {int targetBins = 400}) {
  if (samples.isEmpty) return const [];
  final bins = math.min(targetBins, samples.length);
  final step = samples.length / bins;
  final out = List<int>.filled(bins, 0);
  for (var i = 0; i < bins; i++) {
    final from = (i * step).floor();
    final to = math.min(samples.length, ((i + 1) * step).floor());
    var peak = 0;
    for (var s = from; s < to; s++) {
      final v = samples[s].abs();
      if (v > peak) peak = v;
    }
    out[i] = (peak * 255 / 32767).round().clamp(0, 255);
  }
  return out;
}
```

Add the matching import at the top of `song_audio_rules.dart` (after the existing `dart:math` import):

```dart
import 'dart:typed_data';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/song_audio_rules_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/song_audio_rules.dart test/schema/rules/song_audio_rules_test.dart
git commit -m "feat(song): compute normalised peaks from PCM int16 samples"
```

---

## Task 7: `SongAudioRepository` write/read/delete (mobile/desktop)

**Files:**
- Create: `lib/store/song_audio_repository.dart`
- Test: `test/store/song_audio_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/store/song_audio_repository_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  group('SongAudioRepository (file backend)', () {
    late Directory tmp;
    late SongAudioRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('song_audio_test_');
      repo = SongAudioRepository.testWith(rootDirectory: tmp);
    });

    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('writeRecording stores file and returns populated AudioAsset', () async {
      final samples = Int16List.fromList(
        List<int>.generate(44100, (i) => (i % 200) - 100),
      );
      final wav = writeWavPcm16Mono(samples, sampleRate: 44100);

      final asset = await repo.writeRecording(wav);

      expect(asset.format, 'wav');
      expect(asset.sampleRate, 44100);
      expect(asset.channels, 1);
      expect(asset.durationMs, closeTo(1000, 5));
      expect(asset.peaks, isNotEmpty);
      expect(asset.sourceLabel, 'Recording');

      final stored = await repo.resolvePath(asset.id, asset.format);
      expect(stored.existsSync(), isTrue);
      expect(stored.lengthSync(), wav.length);
    });

    test('delete removes the file and is idempotent for missing assets', () async {
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final asset = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );
      await repo.delete(asset.id);
      final stored = await repo.resolvePath(asset.id, asset.format);
      expect(stored.existsSync(), isFalse);
      await repo.delete(asset.id); // second call must not throw
    });

    test('reconcileOrphans deletes files not referenced by the project', () async {
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final keep = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );
      final orphan = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );

      final result = await repo.reconcileOrphans(
        referencedAssetIds: {keep.id},
      );

      expect(result.deletedAssetIds, contains(orphan.id));
      expect(result.deletedAssetIds, isNot(contains(keep.id)));
      final keepFile = await repo.resolvePath(keep.id, keep.format);
      expect(keepFile.existsSync(), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_repository_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:muzician/store/song_audio_repository.dart'`.

- [ ] **Step 3: Implement the repository**

Create `lib/store/song_audio_repository.dart`:

```dart
/// Filesystem-backed repository for audio clip files.
///
/// All disk I/O for song audio lives here.  Other layers refer to assets by
/// id; this class is the only place that converts an id into a real `File`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/song_project.dart';
import '../schema/rules/song_audio_rules.dart';
import '../utils/wav_writer.dart';

class ReconcileResult {
  final List<String> deletedAssetIds;
  const ReconcileResult(this.deletedAssetIds);
}

class SongAudioRepository {
  final Directory? _rootOverride;
  final Uuid _uuid;
  Directory? _rootCache;

  SongAudioRepository._({Directory? root, Uuid? uuid})
      : _rootOverride = root,
        _uuid = uuid ?? const Uuid();

  factory SongAudioRepository.production() => SongAudioRepository._();

  /// Test factory: bypasses `path_provider` by pinning the root directory.
  factory SongAudioRepository.testWith({required Directory rootDirectory}) =>
      SongAudioRepository._(root: rootDirectory);

  Future<Directory> _root() async {
    if (_rootOverride != null) {
      if (!_rootOverride.existsSync()) await _rootOverride.create(recursive: true);
      return _rootOverride;
    }
    if (_rootCache != null) return _rootCache!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'song_audio'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    _rootCache = dir;
    return dir;
  }

  Future<File> resolvePath(String assetId, String format) async {
    final root = await _root();
    return File(p.join(root.path, '$assetId.$format'));
  }

  Future<AudioAsset> writeRecording(Uint8List wavBytes) async {
    final id = _uuid.v4();
    final file = await resolvePath(id, 'wav');
    await file.writeAsBytes(wavBytes, flush: true);

    final header = parseWavHeader(wavBytes);
    final samples = _extractInt16Samples(wavBytes);
    final peaks = computePeaksFromInt16(samples);

    return AudioAsset(
      id: id,
      durationMs: header.durationMs,
      sampleRate: header.sampleRate,
      channels: header.channels,
      format: 'wav',
      peaks: peaks,
      sourceLabel: 'Recording',
    );
  }

  Future<void> delete(String assetId) async {
    final root = await _root();
    final candidates = <String>['wav', 'mp3', 'm4a'];
    for (final fmt in candidates) {
      final file = File(p.join(root.path, '$assetId.$fmt'));
      if (file.existsSync()) {
        try {
          await file.delete();
        } on FileSystemException {
          // tolerate races / missing
        }
      }
    }
  }

  Future<ReconcileResult> reconcileOrphans({
    required Set<String> referencedAssetIds,
  }) async {
    final root = await _root();
    final files = root.listSync().whereType<File>();
    final deleted = <String>[];
    for (final f in files) {
      final base = p.basenameWithoutExtension(f.path);
      if (!referencedAssetIds.contains(base)) {
        try {
          await f.delete();
          deleted.add(base);
        } on FileSystemException {
          // ignore
        }
      }
    }
    return ReconcileResult(deleted);
  }

  Int16List _extractInt16Samples(Uint8List wav) {
    // Skip up to and including the data chunk header to land on the sample body.
    final bd = ByteData.sublistView(wav);
    var cursor = 12; // after 'RIFF<size>WAVE'
    while (cursor + 8 <= wav.length) {
      final tag = String.fromCharCodes(wav.sublist(cursor, cursor + 4));
      final size = bd.getUint32(cursor + 4, Endian.little);
      if (tag == 'data') {
        final start = cursor + 8;
        final end = start + size;
        final view = wav.buffer.asInt16List(
          wav.offsetInBytes + start,
          (end - start) ~/ 2,
        );
        return Int16List.fromList(view);
      }
      cursor += 8 + size;
    }
    return Int16List(0);
  }
}

final songAudioRepositoryProvider = Provider<SongAudioRepository>((ref) {
  if (kIsWeb) {
    return SongAudioRepository.production(); // overridden by web variant later
  }
  return SongAudioRepository.production();
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_audio_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_audio_repository.dart test/store/song_audio_repository_test.dart
git commit -m "feat(song): filesystem-backed audio asset repository"
```

---

## Task 8: Import path for external audio files

**Files:**
- Modify: `lib/store/song_audio_repository.dart`
- Modify: `test/store/song_audio_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/store/song_audio_repository_test.dart`:

```dart
  group('SongAudioRepository.importExternalFile', () {
    late Directory tmp;
    late SongAudioRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('song_audio_test_');
      repo = SongAudioRepository.testWith(rootDirectory: tmp);
    });

    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('imports a WAV file and parses its header', () async {
      final samples = Int16List.fromList(List<int>.filled(22050, 5000));
      final wav = writeWavPcm16Mono(samples, sampleRate: 44100);
      final src = File('${tmp.path}/source.wav');
      await src.writeAsBytes(wav, flush: true);

      final asset = await repo.importExternalFile(
        sourcePath: src.path,
        sourceLabel: 'source.wav',
        explicitDurationMs: null,
      );

      expect(asset.format, 'wav');
      expect(asset.sourceLabel, 'source.wav');
      expect(asset.durationMs, closeTo(500, 5));
      final stored = await repo.resolvePath(asset.id, asset.format);
      expect(stored.existsSync(), isTrue);
    });

    test('imports an MP3 by trusting the explicit duration probe', () async {
      // Synthesise a tiny pseudo-MP3 by writing a sentinel byte sequence;
      // we are not decoding it, only verifying the repository copies the
      // file and uses the provided duration metadata.
      final src = File('${tmp.path}/loop.mp3');
      await src.writeAsBytes(
        Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xFF)),
        flush: true,
      );

      final asset = await repo.importExternalFile(
        sourcePath: src.path,
        sourceLabel: 'loop.mp3',
        explicitDurationMs: 2500,
      );

      expect(asset.format, 'mp3');
      expect(asset.durationMs, 2500);
      expect(asset.peaks, isEmpty); // we cannot decode mp3 here
      final stored = await repo.resolvePath(asset.id, asset.format);
      expect(stored.existsSync(), isTrue);
    });

    test('rejects unsupported file extensions', () async {
      final src = File('${tmp.path}/note.txt');
      await src.writeAsString('hello', flush: true);
      expect(
        () => repo.importExternalFile(
          sourcePath: src.path,
          sourceLabel: 'note.txt',
          explicitDurationMs: null,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_repository_test.dart`
Expected: FAIL with `The method 'importExternalFile' isn't defined`.

- [ ] **Step 3: Implement `importExternalFile`**

Append the following method to `SongAudioRepository` in `lib/store/song_audio_repository.dart`:

```dart
  /// Copies an external audio file into the repository.
  ///
  /// For WAV files, the duration is parsed from the header and peaks are
  /// computed.  For MP3 / M4A files, the caller must provide the duration
  /// via [explicitDurationMs] (probed by the caller through `audioplayers`),
  /// and peaks are left empty in v1 (waveform will render as a flat band
  /// until a later spec adds decompressed peak computation).
  Future<AudioAsset> importExternalFile({
    required String sourcePath,
    required String sourceLabel,
    required int? explicitDurationMs,
  }) async {
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    if (!const {'wav', 'mp3', 'm4a'}.contains(ext)) {
      throw UnsupportedError('Unsupported audio extension: $ext');
    }

    final id = _uuid.v4();
    final dest = await resolvePath(id, ext);
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    await dest.writeAsBytes(bytes, flush: true);

    int durationMs;
    int sampleRate;
    int channels;
    List<int> peaks;

    if (ext == 'wav') {
      final header = parseWavHeader(bytes);
      durationMs = header.durationMs;
      sampleRate = header.sampleRate;
      channels = header.channels;
      final samples = _extractInt16Samples(bytes);
      peaks = computePeaksFromInt16(samples);
    } else {
      durationMs = explicitDurationMs ?? 0;
      sampleRate = 44100; // unknown without a decoder
      channels = 2;       // safe default; UI does not depend on this
      peaks = const [];
    }

    return AudioAsset(
      id: id,
      durationMs: durationMs,
      sampleRate: sampleRate,
      channels: channels,
      format: ext,
      peaks: peaks,
      sourceLabel: sourceLabel,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_audio_repository_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_audio_repository.dart test/store/song_audio_repository_test.dart
git commit -m "feat(song): import external WAV/MP3/M4A files into the audio repository"
```

---

## Task 9: Project store — add/remove audio clips

**Files:**
- Modify: `lib/store/song_project_store.dart`
- Test: `test/store/song_project_store_test.dart`

- [ ] **Step 1: Write the failing test**

Append a new group to `test/store/song_project_store_test.dart`:

```dart
  group('SongProjectNotifier audio clips', () {
    test('addAudioClip places a clip, pattern, and asset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);

      final trackId = notifier.addTrack(SongTrackType.audio);
      const asset = AudioAsset(
        id: 'asset-1',
        durationMs: 2000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30],
        sourceLabel: 'Recording',
      );

      final clipId = notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: asset,
        clipName: 'Take 1',
      );

      final p = container.read(songProjectProvider);
      expect(p.audioAssets, hasLength(1));
      expect(p.audioPatterns, hasLength(1));
      expect(p.clips, hasLength(1));
      expect(p.clips.first.patternType, SongPatternType.audio);
      expect(p.clips.first.id, clipId);
      expect(p.audioPatterns.first.assetId, 'asset-1');
      expect(p.audioPatterns.first.name, 'Take 1');
    });

    test('removeAudioClip cascades pattern + asset deletion', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);

      final trackId = notifier.addTrack(SongTrackType.audio);
      const asset = AudioAsset(
        id: 'asset-1',
        durationMs: 2000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30],
        sourceLabel: 'Recording',
      );
      final clipId = notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: asset,
      );

      notifier.removeAudioClip(clipId);

      final p = container.read(songProjectProvider);
      expect(p.clips, isEmpty);
      expect(p.audioPatterns, isEmpty);
      expect(p.audioAssets, isEmpty);
    });

    test('deleteTrack on audio track removes its clips + assets', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);
      final trackId = notifier.addTrack(SongTrackType.audio);
      notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: const AudioAsset(
          id: 'a1',
          durationMs: 1000,
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [0],
          sourceLabel: '',
        ),
      );
      notifier.deleteTrack(trackId);
      final p = container.read(songProjectProvider);
      expect(p.tracks, isEmpty);
      expect(p.clips, isEmpty);
      expect(p.audioPatterns, isEmpty);
      expect(p.audioAssets, isEmpty);
    });

    test('renameAudioClip updates only the targeted pattern name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(songProjectProvider.notifier);
      final trackId = notifier.addTrack(SongTrackType.audio);
      final clipId = notifier.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: const AudioAsset(
          id: 'a1',
          durationMs: 1000,
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [0],
          sourceLabel: '',
        ),
        clipName: 'First',
      );

      notifier.renameAudioClip(clipId, 'Renamed');

      final p = container.read(songProjectProvider);
      expect(p.audioPatterns.first.name, 'Renamed');
    });
  });
```

Ensure the test file imports `AudioAsset` and friends:

```dart
import 'package:muzician/models/song_project.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_project_store_test.dart`
Expected: FAIL with `The method 'addAudioClip' isn't defined`.

- [ ] **Step 3: Implement the new methods**

Append the following helpers to `SongProjectNotifier` in `lib/store/song_project_store.dart`, placed just before `loadProject`:

```dart
  // ── Audio Clip Mutations ────────────────────────────────────────────────────

  String addAudioClip({
    required String trackId,
    required int startTick,
    required AudioAsset asset,
    String? clipName,
  }) {
    final patternId = _id('ap');
    final pattern = AudioClipPattern(
      id: patternId,
      name: clipName ?? asset.sourceLabel.isNotEmpty
          ? clipName ?? asset.sourceLabel
          : 'Audio',
      assetId: asset.id,
    );
    final clipId = _id('sci');
    final clip = SongClipInstance(
      id: clipId,
      trackId: trackId,
      patternId: patternId,
      patternType: SongPatternType.audio,
      startTick: startTick,
    );

    state = state.copyWith(
      audioAssets: [...state.audioAssets, asset],
      audioPatterns: [...state.audioPatterns, pattern],
      clips: [...state.clips, clip],
    );

    final lengthTicks = audioClipLengthTicks(asset, state.config);
    state = rules.ensureProjectCoversEndTick(state, startTick + lengthTicks);
    return clipId;
  }

  void removeAudioClip(String clipId) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    if (clip.patternType != SongPatternType.audio) return;
    final pattern = state.audioPatterns.firstWhere(
      (p) => p.id == clip.patternId,
    );

    state = state.copyWith(
      clips: state.clips.where((c) => c.id != clipId).toList(),
      audioPatterns: state.audioPatterns
          .where((p) => p.id != pattern.id)
          .toList(),
      audioAssets: state.audioAssets
          .where((a) => a.id != pattern.assetId)
          .toList(),
    );
  }

  void renameAudioClip(String clipId, String name) {
    final clip = state.clips.firstWhere((c) => c.id == clipId);
    if (clip.patternType != SongPatternType.audio) return;
    final trimmed = name.trim();
    final effective = trimmed.isEmpty ? 'Audio' : trimmed;
    state = state.copyWith(
      audioPatterns: state.audioPatterns
          .map(
            (p) => p.id == clip.patternId ? p.copyWith(name: effective) : p,
          )
          .toList(),
    );
  }
```

Add the import at the top of `song_project_store.dart`:

```dart
import '../schema/rules/song_audio_rules.dart' show audioClipLengthTicks;
```

Update `deleteTrack` so audio clips on the deleted track also drop their assets/patterns. Replace its body with:

```dart
  void deleteTrack(String trackId) {
    final removedClips = state.clips.where((c) => c.trackId == trackId).toList();
    final keptClips = state.clips.where((c) => c.trackId != trackId).toList();
    final removedAudioPatternIds = removedClips
        .where((c) => c.patternType == SongPatternType.audio)
        .map((c) => c.patternId)
        .toSet();
    final removedAudioAssetIds = state.audioPatterns
        .where((p) => removedAudioPatternIds.contains(p.id))
        .map((p) => p.assetId)
        .toSet();

    state = state.copyWith(
      tracks: state.tracks.where((t) => t.id != trackId).toList(),
      clips: keptClips,
      audioPatterns: state.audioPatterns
          .where((p) => !removedAudioPatternIds.contains(p.id))
          .toList(),
      audioAssets: state.audioAssets
          .where((a) => !removedAudioAssetIds.contains(a.id))
          .toList(),
    );

    _removeOrphanedPatterns();
  }
```

`patternLengthForClip` in `song_rules.dart` does not handle audio yet — add a branch there. In `lib/schema/rules/song_rules.dart`, replace `patternLengthForClip`:

```dart
int? patternLengthForClip(SongProject project, SongClipInstance clip) {
  switch (clip.patternType) {
    case SongPatternType.note:
      return project.notePatterns
          .where((p) => p.id == clip.patternId)
          .firstOrNull
          ?.lengthTicks;
    case SongPatternType.drum:
      return project.drumPatterns
          .where((p) => p.id == clip.patternId)
          .firstOrNull
          ?.lengthTicks;
    case SongPatternType.audio:
      final pattern = project.audioPatterns
          .where((p) => p.id == clip.patternId)
          .firstOrNull;
      if (pattern == null) return null;
      final asset = project.audioAssets
          .where((a) => a.id == pattern.assetId)
          .firstOrNull;
      if (asset == null) return null;
      return audioClipLengthTicks(asset, project.config);
  }
}
```

Add the import at the top of `song_rules.dart`:

```dart
import 'song_audio_rules.dart' show audioClipLengthTicks;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_project_store_test.dart`
Expected: PASS (new group, no regressions).

Run the full unit suite to catch any regressions:

Run: `flutter test`
Expected: all green; if the analyzer flags new switch warnings, address them by adding the audio branch.

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_project_store.dart lib/schema/rules/song_rules.dart test/store/song_project_store_test.dart
git commit -m "feat(song): add/remove/rename audio clips in SongProjectNotifier"
```

---

## Task 10: Recorder state machine — types and idle scaffold

**Files:**
- Create: `lib/store/song_audio_recorder_store.dart`
- Test: `test/store/song_audio_recorder_store_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/store/song_audio_recorder_store_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/song_audio_recorder_store.dart';

void main() {
  test('SongAudioRecorderNotifier starts in idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(songAudioRecorderProvider);
    expect(state.status, SongAudioRecorderStatus.idle);
    expect(state.pendingAsset, isNull);
    expect(state.targetTrackId, isNull);
    expect(state.startTick, isNull);
    expect(state.elapsedMs, 0);
    expect(state.errorMessage, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the state + notifier scaffold**

Create `lib/store/song_audio_recorder_store.dart`:

```dart
/// State machine for the song audio overdub flow: count-in → recording →
/// preview → commit/discard.  All side effects (mic, files) are injected via
/// providers so tests can swap them.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';

enum SongAudioRecorderStatus {
  idle,
  countIn,
  recording,
  finalising,
  preview,
  error,
}

class SongAudioRecorderState {
  final SongAudioRecorderStatus status;
  final String? targetTrackId;
  final int? startTick;
  final int elapsedMs;
  final AudioAsset? pendingAsset;
  final String? errorMessage;

  const SongAudioRecorderState({
    this.status = SongAudioRecorderStatus.idle,
    this.targetTrackId,
    this.startTick,
    this.elapsedMs = 0,
    this.pendingAsset,
    this.errorMessage,
  });

  SongAudioRecorderState copyWith({
    SongAudioRecorderStatus? status,
    String? Function()? targetTrackId,
    int? Function()? startTick,
    int? elapsedMs,
    AudioAsset? Function()? pendingAsset,
    String? Function()? errorMessage,
  }) => SongAudioRecorderState(
    status: status ?? this.status,
    targetTrackId:
        targetTrackId != null ? targetTrackId() : this.targetTrackId,
    startTick: startTick != null ? startTick() : this.startTick,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    pendingAsset:
        pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage:
        errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

class SongAudioRecorderNotifier extends Notifier<SongAudioRecorderState> {
  @override
  SongAudioRecorderState build() => const SongAudioRecorderState();
}

final songAudioRecorderProvider =
    NotifierProvider<SongAudioRecorderNotifier, SongAudioRecorderState>(
  SongAudioRecorderNotifier.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_audio_recorder_store.dart test/store/song_audio_recorder_store_test.dart
git commit -m "feat(song): scaffold audio recorder state machine"
```

---

## Task 11: Recorder — recorder driver interface + start/stop transitions

**Files:**
- Modify: `lib/store/song_audio_recorder_store.dart`
- Modify: `test/store/song_audio_recorder_store_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/store/song_audio_recorder_store_test.dart`:

```dart
import 'dart:typed_data';

import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_recorder_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';
import 'dart:io';

class _FakeRecorderDriver implements SongAudioRecorderDriver {
  bool started = false;
  bool stopped = false;
  Uint8List? lastBytes;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<Uint8List> stop() async {
    stopped = true;
    final samples = Int16List.fromList(List<int>.filled(44100, 4000));
    lastBytes = writeWavPcm16Mono(samples, sampleRate: 44100);
    return lastBytes!;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('SongAudioRecorderNotifier starts in idle', () { /* … existing test … */ });

  test('start transitions idle → countIn → recording', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(driver),
      songAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp),
      ),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(
      trackId: 'track-1',
      startTick: 16,
      countInMs: 0, // skip count-in for the test
    );

    expect(driver.started, isTrue);
    final state = container.read(songAudioRecorderProvider);
    expect(state.status, SongAudioRecorderStatus.recording);
    expect(state.targetTrackId, 'track-1');
    expect(state.startTick, 16);
  });

  test('stop transitions recording → finalising → preview with asset', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(driver),
      songAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp),
      ),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(
      trackId: 'track-1',
      startTick: 0,
      countInMs: 0,
    );
    await notifier.stop();

    expect(driver.stopped, isTrue);
    final state = container.read(songAudioRecorderProvider);
    expect(state.status, SongAudioRecorderStatus.preview);
    expect(state.pendingAsset, isNotNull);
    expect(state.pendingAsset!.format, 'wav');
    expect(state.pendingAsset!.durationMs, closeTo(1000, 10));
  });
}
```

(Keep only one `main` function — merge the new tests under the existing one.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: FAIL with `Target of URI doesn't exist` for `SongAudioRecorderDriver`.

- [ ] **Step 3: Add driver interface and implement transitions**

Replace `lib/store/song_audio_recorder_store.dart` with:

```dart
/// State machine for the song audio overdub flow: count-in → recording →
/// preview → commit/discard.  All side effects (mic, files) are injected via
/// providers so tests can swap them.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';
import 'song_audio_repository.dart';

enum SongAudioRecorderStatus {
  idle,
  countIn,
  recording,
  finalising,
  preview,
  error,
}

class SongAudioRecorderState {
  final SongAudioRecorderStatus status;
  final String? targetTrackId;
  final int? startTick;
  final int elapsedMs;
  final AudioAsset? pendingAsset;
  final String? errorMessage;

  const SongAudioRecorderState({
    this.status = SongAudioRecorderStatus.idle,
    this.targetTrackId,
    this.startTick,
    this.elapsedMs = 0,
    this.pendingAsset,
    this.errorMessage,
  });

  SongAudioRecorderState copyWith({
    SongAudioRecorderStatus? status,
    String? Function()? targetTrackId,
    int? Function()? startTick,
    int? elapsedMs,
    AudioAsset? Function()? pendingAsset,
    String? Function()? errorMessage,
  }) => SongAudioRecorderState(
    status: status ?? this.status,
    targetTrackId:
        targetTrackId != null ? targetTrackId() : this.targetTrackId,
    startTick: startTick != null ? startTick() : this.startTick,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    pendingAsset:
        pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage:
        errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

/// Abstraction over the real `record` package so tests can inject a fake.
abstract class SongAudioRecorderDriver {
  Future<bool> ensurePermission();
  Future<void> start();
  Future<Uint8List> stop();
  Future<void> dispose();
}

final songAudioRecorderDriverProvider =
    Provider<SongAudioRecorderDriver>((ref) {
  throw UnimplementedError(
    'Override songAudioRecorderDriverProvider in real launches and tests',
  );
});

class SongAudioRecorderNotifier extends Notifier<SongAudioRecorderState> {
  @override
  SongAudioRecorderState build() => const SongAudioRecorderState();

  Future<void> start({
    required String trackId,
    required int startTick,
    int countInMs = 0,
  }) async {
    if (state.status != SongAudioRecorderStatus.idle &&
        state.status != SongAudioRecorderStatus.error) {
      return;
    }
    final driver = ref.read(songAudioRecorderDriverProvider);
    final permitted = await driver.ensurePermission();
    if (!permitted) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }

    state = SongAudioRecorderState(
      status: SongAudioRecorderStatus.countIn,
      targetTrackId: trackId,
      startTick: startTick,
    );
    if (countInMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: countInMs));
    }

    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    await driver.start();
  }

  Future<void> stop() async {
    if (state.status != SongAudioRecorderStatus.recording) return;
    state = state.copyWith(status: SongAudioRecorderStatus.finalising);
    final driver = ref.read(songAudioRecorderDriverProvider);
    try {
      final bytes = await driver.stop();
      final repo = ref.read(songAudioRepositoryProvider);
      final asset = await repo.writeRecording(bytes);
      state = state.copyWith(
        status: SongAudioRecorderStatus.preview,
        pendingAsset: () => asset,
        elapsedMs: asset.durationMs,
      );
    } catch (e) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    }
  }

  /// Discards the pending take and returns the recorder to idle.
  Future<void> discard() async {
    final asset = state.pendingAsset;
    if (asset != null) {
      final repo = ref.read(songAudioRepositoryProvider);
      await repo.delete(asset.id);
    }
    state = const SongAudioRecorderState();
  }

  /// Releases the pending asset for the caller to commit it to the project,
  /// then returns the recorder to idle.  Caller is responsible for calling
  /// `songProjectProvider.notifier.addAudioClip` with the returned asset.
  AudioAsset? consumePendingAsset() {
    final asset = state.pendingAsset;
    state = const SongAudioRecorderState();
    return asset;
  }

  Future<void> reset() async {
    state = const SongAudioRecorderState();
  }
}

final songAudioRecorderProvider =
    NotifierProvider<SongAudioRecorderNotifier, SongAudioRecorderState>(
  SongAudioRecorderNotifier.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_audio_recorder_store.dart test/store/song_audio_recorder_store_test.dart
git commit -m "feat(song): drive audio recorder through count-in/record/stop transitions"
```

---

## Task 12: Recorder — discard and consume tests

**Files:**
- Modify: `test/store/song_audio_recorder_store_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to the existing `main()`:

```dart
  test('discard deletes the stored file and returns to idle', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SongAudioRepository.testWith(rootDirectory: tmp);
    final container = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(driver),
      songAudioRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: 't', startTick: 0, countInMs: 0);
    await notifier.stop();
    final asset = container.read(songAudioRecorderProvider).pendingAsset!;

    await notifier.discard();

    expect(
      container.read(songAudioRecorderProvider).status,
      SongAudioRecorderStatus.idle,
    );
    final file = await repo.resolvePath(asset.id, asset.format);
    expect(file.existsSync(), isFalse);
  });

  test('consumePendingAsset returns asset and resets to idle', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(driver),
      songAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp),
      ),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: 't', startTick: 0, countInMs: 0);
    await notifier.stop();

    final asset = notifier.consumePendingAsset();
    expect(asset, isNotNull);
    expect(
      container.read(songAudioRecorderProvider).status,
      SongAudioRecorderStatus.idle,
    );
  });
```

- [ ] **Step 2: Run test to verify it passes**

The notifier methods already exist (added in Task 11). Run:

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 3: Commit**

```bash
git add test/store/song_audio_recorder_store_test.dart
git commit -m "test(song): cover discard and consume in audio recorder"
```

---

## Task 13: Real recorder driver implementation

**Files:**
- Create: `lib/store/song_audio_recorder_driver_impl.dart`

- [ ] **Step 1: Implement the driver backed by `record` + `permission_handler`**

Create `lib/store/song_audio_recorder_driver_impl.dart`:

```dart
/// Production implementation of [SongAudioRecorderDriver] backed by the
/// `record` and `permission_handler` packages.  Always records mono WAV 16-bit
/// at 44.1 kHz so the in-app peak/waveform pipeline can decode the bytes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'song_audio_recorder_store.dart';

class RecordPackageDriver implements SongAudioRecorderDriver {
  final AudioRecorder _recorder = AudioRecorder();
  File? _currentFile;

  @override
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<void> start() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'song_audio_tmp'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(
      p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.wav'),
    );
    _currentFile = file;
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 44100,
        bitRate: 16 * 44100,
      ),
      path: file.path,
    );
  }

  @override
  Future<Uint8List> stop() async {
    await _recorder.stop();
    final file = _currentFile;
    if (file == null || !file.existsSync()) {
      throw StateError('No recording file produced');
    }
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } on FileSystemException {
      // ignore
    }
    _currentFile = null;
    return bytes;
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {
      // already disposed
    }
  }
}
```

- [ ] **Step 2: Smoke-build the file**

Run: `flutter analyze lib/store/song_audio_recorder_driver_impl.dart`
Expected: no errors. If `record` package types differ from the snippet, fix in place against the installed API.

- [ ] **Step 3: Commit**

```bash
git add lib/store/song_audio_recorder_driver_impl.dart
git commit -m "feat(song): production recorder driver backed by record package"
```

---

## Task 14: Audio playback — pure scheduling helpers

**Files:**
- Modify: `lib/schema/rules/song_audio_rules.dart`
- Modify: `test/schema/rules/song_audio_rules_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/schema/rules/song_audio_rules_test.dart`:

```dart
  group('schedulableAudioClips', () {
    test('returns only audio-track clips on non-muted tracks', () {
      final project = SongProject(
        config: SongProjectConfig(
          tempo: 120,
          timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [
          SongTrack(id: 't1', name: 'A', type: SongTrackType.audio, order: 0),
          SongTrack(
            id: 't2',
            name: 'Muted',
            type: SongTrackType.audio,
            order: 1,
            isMuted: true,
          ),
        ],
        clips: const [
          SongClipInstance(
            id: 'c1',
            trackId: 't1',
            patternId: 'p1',
            patternType: SongPatternType.audio,
            startTick: 0,
          ),
          SongClipInstance(
            id: 'c2',
            trackId: 't2',
            patternId: 'p2',
            patternType: SongPatternType.audio,
            startTick: 0,
          ),
        ],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: const [
          AudioAsset(
            id: 'a1',
            durationMs: 1000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [],
            sourceLabel: '',
          ),
          AudioAsset(
            id: 'a2',
            durationMs: 1000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [],
            sourceLabel: '',
          ),
        ],
        audioPatterns: const [
          AudioClipPattern(id: 'p1', name: '', assetId: 'a1'),
          AudioClipPattern(id: 'p2', name: '', assetId: 'a2'),
        ],
      );

      final scheduled = schedulableAudioClips(project);
      expect(scheduled, hasLength(1));
      expect(scheduled.first.clip.id, 'c1');
      expect(scheduled.first.startMs, 0);
      expect(scheduled.first.endMs, 1000);
    });

    test('solo on one track hides the other', () {
      final project = SongProject(
        config: SongProjectConfig(
          tempo: 60,
          timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [
          SongTrack(
            id: 't1',
            name: 'A',
            type: SongTrackType.audio,
            order: 0,
            isSolo: true,
          ),
          SongTrack(
            id: 't2',
            name: 'B',
            type: SongTrackType.audio,
            order: 1,
          ),
        ],
        clips: const [
          SongClipInstance(
            id: 'c1',
            trackId: 't1',
            patternId: 'p1',
            patternType: SongPatternType.audio,
            startTick: 0,
          ),
          SongClipInstance(
            id: 'c2',
            trackId: 't2',
            patternId: 'p2',
            patternType: SongPatternType.audio,
            startTick: 0,
          ),
        ],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: const [
          AudioAsset(
            id: 'a1',
            durationMs: 1000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [],
            sourceLabel: '',
          ),
          AudioAsset(
            id: 'a2',
            durationMs: 1000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [],
            sourceLabel: '',
          ),
        ],
        audioPatterns: const [
          AudioClipPattern(id: 'p1', name: '', assetId: 'a1'),
          AudioClipPattern(id: 'p2', name: '', assetId: 'a2'),
        ],
      );

      final scheduled = schedulableAudioClips(project);
      expect(scheduled, hasLength(1));
      expect(scheduled.first.clip.id, 'c1');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/schema/rules/song_audio_rules_test.dart`
Expected: FAIL with `Undefined name 'schedulableAudioClips'`.

- [ ] **Step 3: Add scheduling helper**

Append to `lib/schema/rules/song_audio_rules.dart`:

```dart
class ScheduledAudioClip {
  final SongClipInstance clip;
  final AudioClipPattern pattern;
  final AudioAsset asset;
  final int startMs;
  final int endMs;

  const ScheduledAudioClip({
    required this.clip,
    required this.pattern,
    required this.asset,
    required this.startMs,
    required this.endMs,
  });
}

/// Returns every audio clip that should play given the project's current
/// mute/solo state, with its absolute start and end times in milliseconds.
List<ScheduledAudioClip> schedulableAudioClips(SongProject project) {
  final hasSolo = project.tracks.any((t) => t.isSolo);
  final audible = <String>{
    for (final t in project.tracks)
      if (t.type == SongTrackType.audio &&
          (hasSolo ? t.isSolo : !t.isMuted))
        t.id,
  };
  final patternById = {for (final p in project.audioPatterns) p.id: p};
  final assetById = {for (final a in project.audioAssets) a.id: a};

  final out = <ScheduledAudioClip>[];
  for (final clip in project.clips) {
    if (clip.patternType != SongPatternType.audio) continue;
    if (!audible.contains(clip.trackId)) continue;
    final pattern = patternById[clip.patternId];
    if (pattern == null) continue;
    final asset = assetById[pattern.assetId];
    if (asset == null) continue;
    final startMs = audioTickToMs(clip.startTick, project.config);
    out.add(
      ScheduledAudioClip(
        clip: clip,
        pattern: pattern,
        asset: asset,
        startMs: startMs,
        endMs: startMs + asset.durationMs,
      ),
    );
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/schema/rules/song_audio_rules_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/schema/rules/song_audio_rules.dart test/schema/rules/song_audio_rules_test.dart
git commit -m "feat(song): pure schedulable audio clip computation"
```

---

## Task 15: Audio playback sink wired into `SongPlaybackNotifier`

**Files:**
- Modify: `lib/store/song_playback_store.dart`
- Modify: `test/store/song_playback_store_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/store/song_playback_store_test.dart`:

```dart
  group('SongPlaybackNotifier audio clips', () {
    test('schedules audio clip starts/stops as the transport ticks', () async {
      final container = ProviderContainer(overrides: [
        songAudioClipSinkProvider.overrideWithValue(
          _RecordingAudioSink(),
        ),
      ]);
      addTearDown(container.dispose);

      final project = container.read(songProjectProvider.notifier);
      final trackId = project.addTrack(SongTrackType.audio);
      project.addAudioClip(
        trackId: trackId,
        startTick: 0,
        asset: const AudioAsset(
          id: 'a-fast',
          durationMs: 60, // short so the test does not hang
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [],
          sourceLabel: '',
        ),
      );

      final sink =
          container.read(songAudioClipSinkProvider) as _RecordingAudioSink;
      await container.read(songPlaybackProvider.notifier).startPlayback();

      expect(sink.startCalls, isNotEmpty);
      expect(sink.stopCalls, isNotEmpty);
      expect(sink.startCalls.first.assetId, 'a-fast');
    });
  });
}

class _AudioCall {
  final String assetId;
  const _AudioCall(this.assetId);
}

class _RecordingAudioSink implements SongAudioClipSink {
  final List<_AudioCall> startCalls = [];
  final List<_AudioCall> stopCalls = [];

  @override
  Future<void> startClip({required AudioAsset asset, required int offsetMs}) async {
    startCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    stopCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopAll() async {}
}
```

Add to the imports at the top of the test file:

```dart
import 'package:muzician/models/song_project.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_playback_store_test.dart`
Expected: FAIL with `Undefined name 'songAudioClipSinkProvider'` / `SongAudioClipSink`.

- [ ] **Step 3: Implement the sink interface + scheduling**

In `lib/store/song_playback_store.dart`:

Add new imports:

```dart
import '../schema/rules/song_audio_rules.dart';
```

Add the sink interface and provider above `SongPlaybackNotifier`:

```dart
abstract class SongAudioClipSink {
  Future<void> startClip({required AudioAsset asset, required int offsetMs});
  Future<void> stopClip({required AudioAsset asset});
  Future<void> stopAll();
}

class _NoopAudioSink implements SongAudioClipSink {
  const _NoopAudioSink();
  @override
  Future<void> startClip({required AudioAsset asset, required int offsetMs}) async {}
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async {}
}

final songAudioClipSinkProvider =
    Provider<SongAudioClipSink>((ref) => const _NoopAudioSink());
```

Update `SongPlaybackNotifier.startPlayback` to also drive audio clips. At the top, after reading `noteSink` / `drumSink`, add:

```dart
    final audioSink = ref.read(songAudioClipSinkProvider);
    final scheduled = schedulableAudioClips(project)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final pendingStops = <_PendingAudioStop>[];
```

Add the helper class at the bottom of the file (outside the notifier):

```dart
class _PendingAudioStop {
  final AudioAsset asset;
  final int stopAtMs;
  _PendingAudioStop(this.asset, this.stopAtMs);
}
```

Inside the tick loop, **after** the line that fires note/drum events at the current tick (the `while` block), before the next iteration, add:

```dart
          final nowMs =
              ((tick - start) * tickDuration.inMicroseconds / 1000).round();
          while (scheduled.isNotEmpty && scheduled.first.startMs <= nowMs) {
            final clip = scheduled.removeAt(0);
            final offset = nowMs - clip.startMs;
            unawaited(
              audioSink.startClip(
                asset: clip.asset,
                offsetMs: offset.clamp(0, clip.asset.durationMs),
              ),
            );
            pendingStops.add(
              _PendingAudioStop(clip.asset, clip.endMs),
            );
          }
          pendingStops.removeWhere((pending) {
            if (pending.stopAtMs <= nowMs) {
              unawaited(audioSink.stopClip(asset: pending.asset));
              return true;
            }
            return false;
          });
```

In `stopPlayback`, before resetting state, schedule a stopAll:

```dart
  void stopPlayback() {
    _playbackVersion++;
    unawaited(ref.read(songAudioClipSinkProvider).stopAll());
    state = const SongPlaybackState();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_playback_store_test.dart`
Expected: PASS (including the new group).

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_playback_store.dart test/store/song_playback_store_test.dart
git commit -m "feat(song): schedule audio clips via injectable sink"
```

---

## Task 16: Production `audioplayers` sink

**Files:**
- Create: `lib/store/song_audio_player_sink.dart`

- [ ] **Step 1: Implement the sink**

Create `lib/store/song_audio_player_sink.dart`:

```dart
/// Production [SongAudioClipSink] backed by one `AudioPlayer` per active clip.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart';

class AudioPlayersClipSink implements SongAudioClipSink {
  final SongAudioRepository repository;
  final Map<String, AudioPlayer> _players = {};

  AudioPlayersClipSink(this.repository);

  @override
  Future<void> startClip({required AudioAsset asset, required int offsetMs}) async {
    final file = await repository.resolvePath(asset.id, asset.format);
    if (!file.existsSync()) return;
    final player = _players.putIfAbsent(asset.id, AudioPlayer.new);
    await player.stop();
    await player.setSource(DeviceFileSource(file.path));
    await player.seek(Duration(milliseconds: offsetMs));
    await player.resume();
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    final player = _players[asset.id];
    if (player == null) return;
    await player.stop();
  }

  @override
  Future<void> stopAll() async {
    for (final player in _players.values) {
      await player.stop();
    }
  }
}

/// Override for production launches that swaps the no-op sink with the real
/// one.  Tests keep using the no-op default unless they override this provider.
final productionSongAudioClipSinkProvider =
    Provider<SongAudioClipSink>((ref) {
  return AudioPlayersClipSink(ref.read(songAudioRepositoryProvider));
});
```

- [ ] **Step 2: Smoke-build the file**

Run: `flutter analyze lib/store/song_audio_player_sink.dart`
Expected: no errors. If `audioplayers` API differs, adapt to the installed version.

- [ ] **Step 3: Commit**

```bash
git add lib/store/song_audio_player_sink.dart
git commit -m "feat(song): production audioplayers-backed clip sink"
```

---

## Task 17: Bottom sheet adds Record/Import entries for audio tracks

**Files:**
- Modify: `lib/features/song/song_import_picker_sheet.dart`
- Create: `lib/features/song/song_audio_picker_sheet.dart`
- Test: `test/features/song/song_audio_picker_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/song/song_audio_picker_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_picker_sheet.dart';

void main() {
  testWidgets('shows Record audio and Import audio entries', (tester) async {
    var recordTapped = false;
    var importTapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongAudioPickerSheet(
              trackId: 't1',
              startTick: 0,
              recordSupported: true,
              onRecord: () => recordTapped = true,
              onImport: () => importTapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Record audio'), findsOneWidget);
    expect(find.text('Import audio file'), findsOneWidget);

    await tester.tap(find.text('Record audio'));
    await tester.tap(find.text('Import audio file'));
    expect(recordTapped, isTrue);
    expect(importTapped, isTrue);
  });

  testWidgets('hides Record entry when not supported (web)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongAudioPickerSheet(
              trackId: 't1',
              startTick: 0,
              recordSupported: false,
              onRecord: () {},
              onImport: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Record audio'), findsNothing);
    expect(find.text('Import audio file'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/song/song_audio_picker_sheet_test.dart`
Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the sheet**

Create `lib/features/song/song_audio_picker_sheet.dart`:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/muzician_theme.dart';

class SongAudioPickerSheet extends ConsumerWidget {
  final String trackId;
  final int startTick;
  final bool recordSupported;
  final VoidCallback onRecord;
  final VoidCallback onImport;

  const SongAudioPickerSheet({
    super.key,
    required this.trackId,
    required this.startTick,
    required this.onRecord,
    required this.onImport,
    bool? recordSupported,
  }) : recordSupported = recordSupported ?? !kIsWeb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (recordSupported)
              ListTile(
                leading: const Icon(Icons.mic, color: MuzicianTheme.textPrimary),
                title: const Text(
                  'Record audio',
                  style: TextStyle(color: MuzicianTheme.textPrimary),
                ),
                subtitle: const Text(
                  'Overdub with count-in, preview, and place',
                  style: TextStyle(color: MuzicianTheme.textSecondary),
                ),
                onTap: onRecord,
              ),
            ListTile(
              leading: const Icon(
                Icons.file_open,
                color: MuzicianTheme.textPrimary,
              ),
              title: const Text(
                'Import audio file',
                style: TextStyle(color: MuzicianTheme.textPrimary),
              ),
              subtitle: const Text(
                'WAV, MP3, or M4A',
                style: TextStyle(color: MuzicianTheme.textSecondary),
              ),
              onTap: onImport,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/song/song_audio_picker_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/song/song_audio_picker_sheet.dart test/features/song/song_audio_picker_sheet_test.dart
git commit -m "feat(song): bottom sheet for Record / Import audio actions"
```

---

## Task 18: Waveform painter

**Files:**
- Create: `lib/features/song/song_audio_clip_body.dart`
- Test: `test/features/song/song_audio_clip_body_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/song/song_audio_clip_body_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_clip_body.dart';

void main() {
  testWidgets('renders clip name and duration label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: AudioClipBody(
              name: 'Take 1',
              durationMs: 12345,
              format: 'wav',
              peaks: const [0, 64, 128, 192, 255],
              isBroken: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Take 1'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('WAV'), findsOneWidget);
  });

  testWidgets('shows broken indicator when isBroken', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: AudioClipBody(
              name: 'Missing',
              durationMs: 1000,
              format: 'wav',
              peaks: const [],
              isBroken: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('audio-clip-broken')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/song/song_audio_clip_body_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the widget + painter**

Create `lib/features/song/song_audio_clip_body.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

class AudioClipBody extends StatelessWidget {
  final String name;
  final int durationMs;
  final String format;
  final List<int> peaks;
  final bool isBroken;

  const AudioClipBody({
    super.key,
    required this.name,
    required this.durationMs,
    required this.format,
    required this.peaks,
    required this.isBroken,
  });

  String _durationLabel() {
    final total = (durationMs / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: AudioWaveformPainter(
                peaks: peaks,
                accent: const Color(0xFF3FA9F5),
                background: const Color(0xFF13314A),
              ),
            ),
          ),
          if (isBroken)
            Positioned.fill(
              key: const ValueKey('audio-clip-broken'),
              child: CustomPaint(
                painter: _BrokenStripePainter(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _durationLabel(),
                  style: const TextStyle(
                    color: MuzicianTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    format.toUpperCase(),
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AudioWaveformPainter extends CustomPainter {
  final List<int> peaks;
  final Color accent;
  final Color background;

  const AudioWaveformPainter({
    required this.peaks,
    required this.accent,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (peaks.isEmpty) return;
    final centerY = size.height / 2;
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (var x = 0; x < size.width.floor(); x++) {
      final binIndex = ((x / size.width) * peaks.length).floor();
      final peak = peaks[binIndex.clamp(0, peaks.length - 1)];
      final h = (peak / 255.0) * size.height * 0.9;
      canvas.drawLine(
        Offset(x.toDouble(), centerY - h / 2),
        Offset(x.toDouble(), centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter old) =>
      old.peaks != peaks || old.accent != accent || old.background != background;
}

class _BrokenStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xCCB23A3A)
      ..strokeWidth = 2.0;
    for (var x = -size.height.toInt(); x < size.width; x += 12) {
      canvas.drawLine(
        Offset(x.toDouble(), 0),
        Offset(x.toDouble() + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/song/song_audio_clip_body_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/song/song_audio_clip_body.dart test/features/song/song_audio_clip_body_test.dart
git commit -m "feat(song): waveform clip body widget"
```

---

## Task 19: Arranger timeline renders audio clips

**Files:**
- Modify: `lib/features/song/song_arranger_timeline.dart`

- [ ] **Step 1: Identify the clip-rendering branch**

Open `lib/features/song/song_arranger_timeline.dart` and locate the clip widget builder. It currently switches on `clip.patternType` between note and drum. Add an `audio` case that returns `AudioClipBody`.

Read the file once to find the switch (search for `patternType`). The exact line number depends on current layout; choose the existing branch that renders a clip widget for a track lane.

- [ ] **Step 2: Add the audio branch**

In the relevant switch block, add:

```dart
case SongPatternType.audio:
  final pattern = project.audioPatterns
      .firstWhere((p) => p.id == clip.patternId, orElse: () => const AudioClipPattern(id: '', name: '', assetId: ''));
  final asset = project.audioAssets
      .firstWhere((a) => a.id == pattern.assetId, orElse: () => const AudioAsset(
        id: '',
        durationMs: 0,
        sampleRate: 0,
        channels: 0,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      ));
  final isBroken = pattern.id.isEmpty || asset.id.isEmpty;
  return AudioClipBody(
    name: pattern.name.isEmpty ? 'Audio' : pattern.name,
    durationMs: asset.durationMs,
    format: asset.format,
    peaks: asset.peaks,
    isBroken: isBroken,
  );
```

Add import at the top:

```dart
import 'song_audio_clip_body.dart';
```

Where the lane uses `patternLengthForClip` to compute clip width, no change is required because Task 9 already taught that helper about audio.

- [ ] **Step 3: Manual smoke run**

Run: `flutter run` (or the project-specific launcher), open the Song tab, add an audio track via the header (Task 21), drop a stub clip via the upcoming Task 22 sheet. Skip if simulator is not available — defer to Task 27 device pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/song/song_arranger_timeline.dart
git commit -m "feat(song): render audio clips in arranger timeline"
```

---

## Task 20: Track header — add audio track button + label

**Files:**
- Modify: `lib/features/song/song_track_header.dart`
- Modify: `lib/features/song/song_screen.dart` (only if the "+ Track" UI lives there)

- [ ] **Step 1: Add the audio track option to the header**

Open `lib/features/song/song_track_header.dart`. Locate where the existing "+ Note Track" and "+ Drum Track" controls are produced (probably a `PopupMenuButton` or row of `IconButton`s) and add a third entry that calls:

```dart
ref.read(songProjectProvider.notifier).addTrack(SongTrackType.audio);
```

Reuse the same icon as the recorder mic (`Icons.mic`). The track header for an existing audio track should show "Audio Track" by default (already handled by Task 2's switch fix).

- [ ] **Step 2: Manual analyzer check**

Run: `flutter analyze`
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/song/song_track_header.dart
git commit -m "feat(song): allow creating audio tracks from track header"
```

---

## Task 21: Wire bottom-sheet entries to recorder + file picker

**Files:**
- Modify: `lib/features/song/song_import_picker_sheet.dart`
- Modify: `lib/features/song/song_arranger_timeline.dart` (entry point that opens the sheet)
- Create: `lib/features/song/song_audio_actions.dart`

- [ ] **Step 1: Implement audio action helpers**

Create `lib/features/song/song_audio_actions.dart`:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../store/song_audio_recorder_store.dart';
import '../../store/song_audio_repository.dart';
import '../../store/song_project_store.dart';
import 'song_audio_recorder_sheet.dart';

/// Opens the file picker, imports the chosen file via the repository, and
/// commits an audio clip to the project at [startTick].
Future<void> importAudioFile(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required int startTick,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['wav', 'mp3', 'm4a'],
  );
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.first;
  final path = file.path;
  if (path == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not access file on this platform')),
    );
    return;
  }
  if ((file.size) > 50 * 1024 * 1024) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audio file is larger than 50 MB')),
    );
    return;
  }

  try {
    final repo = ref.read(songAudioRepositoryProvider);
    final asset = await repo.importExternalFile(
      sourcePath: path,
      sourceLabel: file.name,
      explicitDurationMs: null,
    );
    ref.read(songProjectProvider.notifier).addAudioClip(
          trackId: trackId,
          startTick: startTick,
          asset: asset,
          clipName: file.name.replaceAll(RegExp(r'\.(wav|mp3|m4a)$'), ''),
        );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Import failed: $e')),
    );
  }
}

/// Opens the audio recorder sheet, waits for the user to commit a take, and
/// adds it as a clip on the project.
Future<void> openAudioRecorder(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required int startTick,
}) async {
  final asset = await showModalBottomSheet<AudioAsset?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SongAudioRecorderSheet(
      trackId: trackId,
      startTick: startTick,
    ),
  );
  if (asset == null) return;
  ref.read(songProjectProvider.notifier).addAudioClip(
        trackId: trackId,
        startTick: startTick,
        asset: asset,
      );
}
```

- [ ] **Step 2: Update the lane-tap launcher**

In `lib/features/song/song_arranger_timeline.dart`, find the existing tap-on-lane handler that opens the `SongImportPickerSheet`. Before that handler picks the import sheet, branch on the track type:

```dart
if (track.type == SongTrackType.audio) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SongAudioPickerSheet(
      trackId: track.id,
      startTick: startTick,
      onRecord: () {
        Navigator.pop(context);
        openAudioRecorder(
          context,
          ref,
          trackId: track.id,
          startTick: startTick,
        );
      },
      onImport: () {
        Navigator.pop(context);
        importAudioFile(
          context,
          ref,
          trackId: track.id,
          startTick: startTick,
        );
      },
    ),
  );
  return;
}
```

Add imports at the top:

```dart
import 'song_audio_actions.dart';
import 'song_audio_picker_sheet.dart';
```

- [ ] **Step 3: Analyzer + commit**

Run: `flutter analyze`
Expected: no new errors. The recorder sheet does not yet exist — it is added in Task 22, so the compile may fail there. Continue to Task 22 before committing.

If `flutter analyze` reports `song_audio_recorder_sheet.dart not found`, defer the analyze pass until Task 22 lands.

- [ ] **Step 4: Commit**

```bash
git add lib/features/song/song_audio_actions.dart lib/features/song/song_arranger_timeline.dart
git commit -m "feat(song): route Record/Import audio actions to repository + recorder sheet"
```

---

## Task 22: Recorder sheet UI

**Files:**
- Create: `lib/features/song/song_audio_recorder_sheet.dart`
- Test: `test/features/song/song_audio_recorder_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/song/song_audio_recorder_sheet_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_recorder_sheet.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_recorder_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';

class _FakeDriver implements SongAudioRecorderDriver {
  @override Future<bool> ensurePermission() async => true;
  @override Future<void> start() async {}
  @override Future<Uint8List> stop() async {
    final samples = Int16List.fromList(List<int>.filled(44100, 2000));
    return writeWavPcm16Mono(samples, sampleRate: 44100);
  }
  @override Future<void> dispose() async {}
}

void main() {
  testWidgets('record → stop → confirm returns the committed asset', (tester) async {
    final tmp = await Directory.systemTemp.createTemp('rec_sheet_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    AudioAsset? returned;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
          songAudioRepositoryProvider.overrideWithValue(
            SongAudioRepository.testWith(rootDirectory: tmp),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  returned = await showModalBottomSheet<AudioAsset?>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const SongAudioRecorderSheet(
                      trackId: 't1',
                      startTick: 0,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('audio-rec-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audio-rec-stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('audio-rec-confirm')));
    await tester.pumpAndSettle();

    expect(returned, isNotNull);
    expect(returned!.format, 'wav');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/song/song_audio_recorder_sheet_test.dart`
Expected: FAIL with `Target of URI doesn't exist`.

- [ ] **Step 3: Implement the sheet**

Create `lib/features/song/song_audio_recorder_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../store/song_audio_recorder_store.dart';
import '../../theme/muzician_theme.dart';
import 'song_audio_clip_body.dart';

class SongAudioRecorderSheet extends ConsumerWidget {
  final String trackId;
  final int startTick;

  const SongAudioRecorderSheet({
    super.key,
    required this.trackId,
    required this.startTick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(songAudioRecorderProvider);
    final notifier = ref.read(songAudioRecorderProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _StatusLabel(status: state.status, errorMessage: state.errorMessage),
            const SizedBox(height: 20),
            if (state.status == SongAudioRecorderStatus.preview &&
                state.pendingAsset != null)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: AudioClipBody(
                  name: 'Preview',
                  durationMs: state.pendingAsset!.durationMs,
                  format: state.pendingAsset!.format,
                  peaks: state.pendingAsset!.peaks,
                  isBroken: false,
                ),
              ),
            const SizedBox(height: 24),
            _ActionRow(
              status: state.status,
              onStart: () => notifier.start(
                trackId: trackId,
                startTick: startTick,
                countInMs: 0, // count-in handled by Task 25 if added
              ),
              onStop: () => notifier.stop(),
              onConfirm: () {
                final asset = notifier.consumePendingAsset();
                Navigator.of(context).pop<AudioAsset?>(asset);
              },
              onDiscard: () async {
                await notifier.discard();
                if (!context.mounted) return;
                Navigator.of(context).pop<AudioAsset?>(null);
              },
              onRetry: () => notifier.discard(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final SongAudioRecorderStatus status;
  final String? errorMessage;
  const _StatusLabel({required this.status, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      SongAudioRecorderStatus.idle => 'Ready',
      SongAudioRecorderStatus.countIn => 'Count-in…',
      SongAudioRecorderStatus.recording => 'Recording…',
      SongAudioRecorderStatus.finalising => 'Finalising…',
      SongAudioRecorderStatus.preview => 'Review the take',
      SongAudioRecorderStatus.error => errorMessage ?? 'Error',
    };
    return Text(
      label,
      style: const TextStyle(
        color: MuzicianTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final SongAudioRecorderStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;
  final VoidCallback onRetry;

  const _ActionRow({
    required this.status,
    required this.onStart,
    required this.onStop,
    required this.onConfirm,
    required this.onDiscard,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SongAudioRecorderStatus.idle:
      case SongAudioRecorderStatus.error:
        return FilledButton.icon(
          key: const ValueKey('audio-rec-start'),
          onPressed: onStart,
          icon: const Icon(Icons.mic),
          label: const Text('Record'),
        );
      case SongAudioRecorderStatus.countIn:
      case SongAudioRecorderStatus.recording:
      case SongAudioRecorderStatus.finalising:
        return FilledButton.icon(
          key: const ValueKey('audio-rec-stop'),
          onPressed:
              status == SongAudioRecorderStatus.recording ? onStop : null,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        );
      case SongAudioRecorderStatus.preview:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-discard'),
              onPressed: onDiscard,
              child: const Text('Discard'),
            ),
            TextButton(
              key: const ValueKey('audio-rec-retry'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
            FilledButton(
              key: const ValueKey('audio-rec-confirm'),
              onPressed: onConfirm,
              child: const Text('Confirm'),
            ),
          ],
        );
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/song/song_audio_recorder_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/song/song_audio_recorder_sheet.dart test/features/song/song_audio_recorder_sheet_test.dart
git commit -m "feat(song): recorder sheet with record/stop/preview actions"
```

---

## Task 23: Production driver + sink overrides in app launch

**Files:**
- Modify: `lib/features/song/song_screen.dart`
- Modify: `lib/main.dart` (or wherever `ProviderScope` is created)

- [ ] **Step 1: Find the top-level `ProviderScope`**

Run: `grep -n 'ProviderScope' lib/main.dart`
Expected: the location where the app's `ProviderScope` is constructed.

- [ ] **Step 2: Add overrides**

In the file that creates the root `ProviderScope`, add overrides for the audio recorder driver and the production sink. Example:

```dart
import 'store/song_audio_recorder_driver_impl.dart';
import 'store/song_audio_recorder_store.dart';
import 'store/song_audio_player_sink.dart';
import 'store/song_playback_store.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        songAudioRecorderDriverProvider
            .overrideWith((ref) => RecordPackageDriver()),
        songAudioClipSinkProvider.overrideWith(
          (ref) => ref.watch(productionSongAudioClipSinkProvider),
        ),
      ],
      child: const MuzicianApp(),
    ),
  );
}
```

If `runApp` already passes a `ProviderScope`, merge the overrides into the existing `overrides:` list.

- [ ] **Step 3: Smoke build**

Run: `flutter analyze`
Expected: no errors. Tests must still pass:

Run: `flutter test`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(song): wire production recorder driver and audio clip sink"
```

---

## Task 24: Load-time reconcile of orphan audio files

**Files:**
- Modify: `lib/store/song_project_store.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/store/song_project_store_test.dart`:

```dart
  group('loadProject audio reconcile', () {
    test('removes orphan files for missing audio assets', () async {
      final tmp = await Directory.systemTemp.createTemp('reconcile_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final repo = SongAudioRepository.testWith(rootDirectory: tmp);
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final orphan = await repo.writeRecording(
        writeWavPcm16Mono(samples, sampleRate: 44100),
      );

      final container = ProviderContainer(overrides: [
        songAudioRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(songProjectProvider.notifier);
      notifier.loadProject(
        const SongProject(
          config: SongProjectConfig(
            tempo: 120,
            timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            totalMeasures: 4,
          ),
          tracks: [],
          clips: [],
          notePatterns: [],
          drumPatterns: [],
          audioAssets: [],
          audioPatterns: [],
        ),
      );

      // Allow the post-load microtask to run.
      await Future<void>.delayed(Duration.zero);

      final file = await repo.resolvePath(orphan.id, orphan.format);
      expect(file.existsSync(), isFalse);
    });
  });
```

Imports to add to the test file:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/utils/wav_writer.dart';
import 'package:muzician/models/piano_roll.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_project_store_test.dart`
Expected: FAIL — orphan file still exists.

- [ ] **Step 3: Hook reconcile into `loadProject`**

In `lib/store/song_project_store.dart`, update `loadProject`:

```dart
  Future<void> loadProject(SongProject project) async {
    state = project;
    final repo = ref.read(songAudioRepositoryProvider);
    final referenced = {for (final a in state.audioAssets) a.id};
    await repo.reconcileOrphans(referencedAssetIds: referenced);
  }
```

`loadProject` was previously synchronous. Update its callers if they relied on the synchronous signature; the existing callers do not await it, so an `unawaited` wrapper is acceptable at call sites. Add import:

```dart
import 'song_audio_repository.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/song_project_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_project_store.dart test/store/song_project_store_test.dart
git commit -m "feat(song): reconcile audio asset files on project load"
```

---

## Task 25: Count-in metronome wiring

**Files:**
- Modify: `lib/features/song/song_audio_recorder_sheet.dart`
- Modify: `lib/store/song_audio_recorder_store.dart` (if count-in needs metronome events)

- [ ] **Step 1: Decide on simple v1 count-in**

For v1, the count-in is a fixed wall-clock delay equal to one measure at the project's tempo. The sheet computes it from `songProjectProvider`.

- [ ] **Step 2: Update the sheet to pass `countInMs`**

In `song_audio_recorder_sheet.dart`, replace the `onStart` callback:

```dart
onStart: () {
  final config = ref.read(songProjectProvider).config;
  final ticksPerMeasure =
      songTicksPerMeasure(config.timeSignature);
  final countInMs = audioTickToMs(ticksPerMeasure, config);
  notifier.start(
    trackId: trackId,
    startTick: startTick,
    countInMs: countInMs,
  );
},
```

Imports:

```dart
import '../../schema/rules/song_audio_rules.dart';
import '../../schema/rules/song_rules.dart' show songTicksPerMeasure;
import '../../store/song_project_store.dart';
```

- [ ] **Step 3: Fire metronome ticks during count-in**

In `SongAudioRecorderNotifier.start`, after entering `countIn`, spawn a metronome via the existing `NotePlayer.instance.playDrumLane(DrumLaneId.closedHiHat)` for each beat of the count-in. Replace the existing count-in block with:

```dart
    state = SongAudioRecorderState(
      status: SongAudioRecorderStatus.countIn,
      targetTrackId: trackId,
      startTick: startTick,
    );
    if (countInMs > 0) {
      // emit four metronome blips evenly spaced across the count-in
      final beatSpacing = Duration(milliseconds: (countInMs / 4).round());
      for (var i = 0; i < 4; i++) {
        unawaited(NotePlayer.instance.playDrumLane(DrumLaneId.closedHiHat));
        await Future<void>.delayed(beatSpacing);
        if (state.status != SongAudioRecorderStatus.countIn) return;
      }
    }
```

Add import to the recorder store:

```dart
import '../utils/note_player.dart';
```

If the existing `NotePlayer.playDrumLane` does not return a `Future`, wrap accordingly. Adjust per the actual signature.

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: all green (the existing recorder tests pass `countInMs: 0` so the new branch is skipped).

- [ ] **Step 5: Commit**

```bash
git add lib/features/song/song_audio_recorder_sheet.dart lib/store/song_audio_recorder_store.dart
git commit -m "feat(song): count-in metronome before audio recording"
```

---

## Task 26: Auto-mute target track during recording

**Files:**
- Modify: `lib/store/song_audio_recorder_store.dart`
- Modify: `test/store/song_audio_recorder_store_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/store/song_audio_recorder_store_test.dart`:

```dart
  test('mutes the target track during recording and restores on stop', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_mute_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(overrides: [
      songAudioRecorderDriverProvider.overrideWithValue(driver),
      songAudioRepositoryProvider.overrideWithValue(
        SongAudioRepository.testWith(rootDirectory: tmp),
      ),
    ]);
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    final trackId = project.addTrack(SongTrackType.audio);
    expect(
      container.read(songProjectProvider).tracks.first.isMuted,
      isFalse,
    );

    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: trackId, startTick: 0, countInMs: 0);
    expect(
      container.read(songProjectProvider).tracks.first.isMuted,
      isTrue,
    );

    await notifier.stop();
    expect(
      container.read(songProjectProvider).tracks.first.isMuted,
      isFalse,
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: FAIL — track stays unmuted.

- [ ] **Step 3: Implement auto-mute around recording**

In `SongAudioRecorderNotifier`, store the original mute state on `start` and restore it on `stop`/`discard`. Add field:

```dart
  bool? _originalMuted;
```

In `start`, after the permission check and right before transitioning to `countIn`, capture and mute:

```dart
    final projectNotifier = ref.read(songProjectProvider.notifier);
    final project = ref.read(songProjectProvider);
    final track = project.tracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => throw StateError('Track $trackId not found'),
    );
    _originalMuted = track.isMuted;
    if (!track.isMuted) projectNotifier.toggleMute(trackId);
```

In `stop` (after the asset is committed to preview), restore:

```dart
    final restoredId = state.targetTrackId;
    if (restoredId != null && _originalMuted == false) {
      final p = ref.read(songProjectProvider);
      final t = p.tracks.where((x) => x.id == restoredId).firstOrNull;
      if (t != null && t.isMuted) {
        ref.read(songProjectProvider.notifier).toggleMute(restoredId);
      }
    }
    _originalMuted = null;
```

Apply the same restore block in `discard` and in the `error` branch of `stop`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/store/song_audio_recorder_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/song_audio_recorder_store.dart test/store/song_audio_recorder_store_test.dart
git commit -m "feat(song): auto-mute target audio track while recording"
```

---

## Task 27: Run full suite + device smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `flutter test`
Expected: all tests pass. Investigate any failures locally; do not commit if red.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: no new warnings or errors. Pre-existing lint that is unrelated to this feature may stay; do not commit unrelated fixes.

- [ ] **Step 3: Manual device smoke (iOS or Android)**

Launch the app on a physical device or simulator. Manual checklist:
1. Open the Song tab.
2. Add an Audio track from the track header.
3. Tap an empty area on the audio lane → "Record audio" → speak → Stop → Confirm → clip should appear with a waveform.
4. Tap a different empty spot → "Import audio file" → pick a WAV or MP3 from the device → clip should appear.
5. Hit Play on the song transport → audio clips play in sync with note/drum content; mute/solo behave per track.
6. Delete a clip → file is gone from `song_audio/`.
7. Save project, kill app, reopen, load project → clips and playback still work.

If any step fails, stop and triage before continuing.

- [ ] **Step 4: Commit a marker if changes were needed during smoke**

If no changes were needed, skip this step. Otherwise commit fixes individually as you make them.

---

## Task 28: Update workspace docs

**Files:**
- Modify: `docs/song_workspace.md`

- [ ] **Step 1: Document audio tracks**

Add a new section in `docs/song_workspace.md`:

```markdown
## Audio Tracks (v1.1)

Audio tracks host clips from microphone recordings or imported files.

- **Record**: tap-lane → "Record audio" → 1-measure count-in → mic captures while the song plays → preview waveform → Confirm / Retry / Discard.
- **Import**: tap-lane → "Import audio file" → choose WAV, MP3, or M4A (up to 50 MB).
- **Storage**: audio files live in `appDocs/song_audio/<assetId>.<ext>`. Save files reference assets by id. Cross-device portability is not supported in v1.
- **Tempo**: clip lengths in ticks track project tempo; the real audio duration never changes.
- **Limits**: no trim, no volume/pan, no time-stretch, no monitoring. Mute/solo at the track level only.
- **Web**: recording is disabled; import works but files do not persist across reloads.
- **Broken clips**: if a referenced file is missing on load, the clip renders with a red diagonal stripe and is silent.
```

- [ ] **Step 2: Commit**

```bash
git add docs/song_workspace.md
git commit -m "docs(song): describe audio tracks v1.1"
```

---

## Self-Review

Run this checklist after the plan is complete.

**Spec coverage**
- Decision 1 (audio track type) → Tasks 1, 2, 20
- Decision 2 (separate file storage) → Tasks 4, 7, 8, 16, 24
- Decision 3 (native length) → Tasks 3, 14, 15
- Decision 4 (v1 operations: record/import/place/delete/rename/mute/solo) → Tasks 9, 19, 20, 21
- Decision 5 (entry point: tap-lane sheet) → Tasks 17, 21
- Decision 6 (overdub UX: count-in/preview) → Tasks 11, 12, 22, 25, 26
- Decision 7 (WAV record, multi-format import) → Tasks 5, 7, 8, 13
- Decision 8 (waveform peaks) → Tasks 6, 18
- Decision 9 (no monitoring) → not implemented; just not added (Task 13 driver does not route mic to output)
- Persistence (broken clip rendering, reconcile) → Tasks 18, 24
- New dependencies → Task 4
- Testing strategy → unit tests in Tasks 1–14, widget tests in Tasks 17, 18, 22, device smoke in Task 27

**Placeholders** — none. All code blocks are runnable; "TBD" / "implement later" not present. Test snippets contain real assertions, not stubs.

**Type consistency** — `AudioAsset`, `AudioClipPattern`, `SongTrackType.audio`, `SongPatternType.audio`, `songAudioRepositoryProvider`, `songAudioRecorderProvider`, `SongAudioRecorderDriver`, `songAudioRecorderDriverProvider`, `songAudioClipSinkProvider`, `audioClipLengthTicks`, `audioTickToMs`, `computePeaksFromInt16`, `schedulableAudioClips`, `ScheduledAudioClip`, `AudioClipBody`, `AudioWaveformPainter`, `SongAudioPickerSheet`, `SongAudioRecorderSheet`, `importAudioFile`, `openAudioRecorder` — each is defined once, named consistently across tasks.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-29-song-audio-tracks.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
