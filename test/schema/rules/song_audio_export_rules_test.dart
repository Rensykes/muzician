import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart' show TimeSignature;
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_audio_export_rules.dart';

void main() {
  test(
    'mixes trimmed mono PCM16 audio at its tick, trim, and track gain',
    () async {
      final project = _audioProject(
        sampleRate: 44100,
        channels: 1,
        volume: 0.5,
        trimStartMs: 100,
        trimEndMs: 200,
      );
      final source = _makeWav(
        sampleRate: 44100,
        channels: 1,
        frames: 44100,
        sample: 8000,
      );

      final pcm = await renderSongPcmWithAudio(
        project,
        sampleRate: 44100,
        readAsset: (id, format) async => source,
      );

      const onset = 22050; // Tick 4 is 500ms at 120 quarter notes per minute.
      expect(pcm[onset], closeTo(4000, 1));
      expect(pcm[onset + 30869], closeTo(4000, 1));
      expect(pcm[onset + 30870], 0); // 100ms head + 200ms tail removed.
    },
  );

  test(
    'downmixes stereo and resamples 48 kHz without changing clip speed',
    () async {
      final project = _audioProject(sampleRate: 48000, channels: 2);
      final source = _makeWav(
        sampleRate: 48000,
        channels: 2,
        frames: 48000,
        sample: 8000,
        rightSample: 4000,
      );

      final pcm = await renderSongPcmWithAudio(
        project,
        sampleRate: 44100,
        readAsset: (id, format) async => source,
      );

      const onset = 22050;
      expect(pcm[onset], closeTo(6000, 1));
      expect(pcm[onset + 44099], closeTo(6000, 1));
      expect(pcm[onset + 44100], 0);
    },
  );

  test('6/8 tick 8 audio onset is 1000ms on the quarter-note grid', () async {
    final project = _audioProject(
      sampleRate: 8000,
      channels: 1,
      startTick: 8,
      beatsPerMeasure: 6,
      beatUnit: 8,
      totalMeasures: 1,
    );
    final source = _makeWav(sampleRate: 8000, channels: 1, frames: 800);

    final pcm = await renderSongPcmWithAudio(
      project,
      sampleRate: 44100,
      readAsset: (id, format) async => source,
    );

    const onset = 44100;
    expect(pcm.take(onset).every((sample) => sample == 0), isTrue);
    expect(
      pcm.skip(onset).take(4410).every((sample) => sample == 5000),
      isTrue,
    );
    expect(pcm[onset + 4410], 0);
  });

  test('audio follows the shared mute and solo rule', () async {
    final source = _makeWav(sampleRate: 44100, channels: 1, frames: 44100);
    final muted = await renderSongPcmWithAudio(
      _audioProject(sampleRate: 44100, channels: 1, muted: true),
      readAsset: (id, format) async => source,
    );
    expect(muted.every((sample) => sample == 0), isTrue);

    final solo = await renderSongPcmWithAudio(
      _audioProject(sampleRate: 44100, channels: 1, otherTrackSolo: true),
      readAsset: (id, format) async => source,
    );
    expect(solo.every((sample) => sample == 0), isTrue);
  });

  test(
    'Web permits note/drum-only mixdown and blocks any audio clip',
    () async {
      var reads = 0;
      final noAudio = SongProject(
        config: _audioProject(sampleRate: 44100, channels: 1).config,
        tracks: const [],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
      );
      await renderSongPcmWithAudio(
        noAudio,
        isWeb: true,
        readAsset: (id, format) async {
          reads++;
          return null;
        },
      );
      expect(reads, 0);

      await expectLater(
        renderSongPcmWithAudio(
          _audioProject(sampleRate: 44100, channels: 1),
          isWeb: true,
          readAsset: (id, format) async {
            reads++;
            return null;
          },
        ),
        throwsA(
          isA<SongAudioExportPreflightException>().having(
            (error) => error.problems.join(' '),
            'actionable Web explanation',
            contains('Android, iOS, macOS, Windows, or Linux'),
          ),
        ),
      );
      expect(reads, 0);
    },
  );

  test(
    'preflight rejects missing, compressed, malformed, and unsupported WAVs',
    () async {
      final project = _audioProject(sampleRate: 44100, channels: 1);
      final cases = <({SongProject project, Uint8List? bytes, String message})>[
        (project: project, bytes: null, message: 'missing its audio file'),
        (
          project: _audioProject(sampleRate: 44100, channels: 1, format: 'mp3'),
          bytes: null,
          message: 'Convert it to PCM16 WAV',
        ),
        (
          project: project,
          bytes: Uint8List.fromList([1, 2, 3]),
          message: 'not a supported PCM16 WAV',
        ),
        (
          project: project,
          bytes: _makeWav(
            sampleRate: 44100,
            channels: 1,
            frames: 100,
            formatTag: 3,
          ),
          message: 'not a supported PCM16 WAV',
        ),
        (
          project: project,
          bytes: _makeWav(sampleRate: 7999, channels: 1, frames: 100),
          message: 'not a supported PCM16 WAV',
        ),
        (
          project: _audioProject(sampleRate: 44100, channels: 3),
          bytes: _makeWav(sampleRate: 44100, channels: 3, frames: 100),
          message: 'not a supported PCM16 WAV',
        ),
      ];

      for (final item in cases) {
        await expectLater(
          renderSongPcmWithAudio(
            item.project,
            readAsset: (id, format) async => item.bytes,
          ),
          throwsA(
            isA<SongAudioExportPreflightException>().having(
              (error) => error.problems.join(' '),
              'preflight message',
              contains(item.message),
            ),
          ),
        );
      }
    },
  );

  test('downmix and linear resampling preserve average level and duration', () {
    final stereo = Int16List.fromList([8000, 4000, 8000, 4000, 8000, 4000]);
    final mono = downmixAndResamplePcm16(
      stereo,
      channels: 2,
      sourceRate: 48000,
      targetRate: 44100,
    );

    expect(mono.length, 3);
    expect(mono, everyElement(6000));
  });
}

SongProject _audioProject({
  required int sampleRate,
  required int channels,
  String format = 'wav',
  int startTick = 4,
  int trimStartMs = 0,
  int trimEndMs = 0,
  double volume = 1,
  bool muted = false,
  bool otherTrackSolo = false,
  int beatsPerMeasure = 4,
  int beatUnit = 4,
  int totalMeasures = 2,
}) => SongProject(
  config: SongProjectConfig(
    tempo: 120,
    timeSignature: TimeSignature(
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
    ),
    totalMeasures: totalMeasures,
  ),
  tracks: [
    SongTrack(
      id: 'audio-track',
      name: 'Audio',
      type: SongTrackType.audio,
      order: 0,
      volume: volume,
      isMuted: muted,
    ),
    if (otherTrackSolo)
      const SongTrack(
        id: 'solo-track',
        name: 'Solo',
        type: SongTrackType.note,
        order: 1,
        isSolo: true,
      ),
  ],
  clips: [
    SongClipInstance(
      id: 'audio-clip',
      trackId: 'audio-track',
      patternId: 'audio-pattern',
      patternType: SongPatternType.audio,
      startTick: startTick,
    ),
  ],
  notePatterns: const [],
  drumPatterns: const [],
  audioAssets: [
    AudioAsset(
      id: 'audio-asset',
      durationMs: 1000,
      sampleRate: sampleRate,
      channels: channels,
      format: format,
      peaks: [],
      sourceLabel: 'Take',
    ),
  ],
  audioPatterns: [
    AudioClipPattern(
      id: 'audio-pattern',
      name: 'Take',
      assetId: 'audio-asset',
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
    ),
  ],
);

Uint8List _makeWav({
  required int sampleRate,
  required int channels,
  required int frames,
  int sample = 5000,
  int? rightSample,
  int formatTag = 1,
}) {
  final samples = frames * channels;
  final dataBytes = samples * 2;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  view.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, formatTag, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * 2, Endian.little);
  view.setUint16(32, channels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  view.setUint32(40, dataBytes, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    view.setInt16(44 + frame * channels * 2, sample, Endian.little);
    if (channels > 1) {
      view.setInt16(
        44 + frame * channels * 2 + 2,
        rightSample ?? sample,
        Endian.little,
      );
      for (var channel = 2; channel < channels; channel++) {
        view.setInt16(
          44 + (frame * channels + channel) * 2,
          sample,
          Endian.little,
        );
      }
    }
  }
  return bytes;
}
