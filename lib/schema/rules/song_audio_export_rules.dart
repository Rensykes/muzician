/// Audio validation, preparation, and preflight for Song WAV mixdown.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/song_project.dart';
import '../../utils/wav_writer.dart';
import 'song_render_rules.dart';

typedef SongAudioBytesReader =
    Future<Uint8List?> Function(String assetId, String format);

class SongAudioExportPreflightException implements Exception {
  final List<String> problems;

  const SongAudioExportPreflightException(this.problems);

  @override
  String toString() => problems.join('\n');
}

/// Validates every referenced audio clip, prepares supported PCM16 WAV clips,
/// then mixes them with the Song's note and drum tracks.
///
/// All source assets are read and validated before any output WAV is built.
/// Web callers pass [isWeb] to block Songs with audio clips because this
/// release has no persistent Web audio-asset storage path.
Future<Int16List> renderSongPcmWithAudio(
  SongProject project, {
  required SongAudioBytesReader readAsset,
  int sampleRate = 44100,
  bool isWeb = false,
}) async {
  final audioClips = project.clips
      .where((clip) => clip.patternType == SongPatternType.audio)
      .toList();
  if (isWeb && audioClips.isNotEmpty) {
    throw const SongAudioExportPreflightException([
      'Web WAV export supports note and drum tracks only. Open this Song on '
          'Android, iOS, macOS, Windows, or Linux to export its audio clips.',
    ]);
  }

  final patternsById = {
    for (final pattern in project.audioPatterns) pattern.id: pattern,
  };
  final assetsById = {for (final asset in project.audioAssets) asset.id: asset};
  final rawByAssetId = <String, Uint8List?>{};
  final decodedByAssetId = <String, _DecodedPcmAsset>{};
  final problems = <String>[];
  final samplesByPatternId = <String, Int16List>{};

  for (final clip in audioClips) {
    final pattern = patternsById[clip.patternId];
    final clipName = pattern?.name.trim().isNotEmpty == true
        ? pattern!.name
        : clip.id;
    if (pattern == null) {
      problems.add(
        '“$clipName” has no audio pattern. Repair or remove this clip.',
      );
      continue;
    }
    final asset = assetsById[pattern.assetId];
    if (asset == null) {
      problems.add(
        '“$clipName” is missing its audio asset. Re-import the source file.',
      );
      continue;
    }
    if (asset.format.toLowerCase() != 'wav') {
      problems.add(
        '“$clipName” uses ${asset.format.toUpperCase()} audio. Convert it to '
        'PCM16 WAV and re-import it before exporting.',
      );
      continue;
    }

    _DecodedPcmAsset? decoded = decodedByAssetId[asset.id];
    if (decoded == null) {
      Uint8List? bytes;
      if (rawByAssetId.containsKey(asset.id)) {
        bytes = rawByAssetId[asset.id];
      } else {
        try {
          bytes = await readAsset(asset.id, asset.format);
        } catch (_) {
          bytes = null;
        }
        rawByAssetId[asset.id] = bytes;
      }
      if (bytes == null) {
        problems.add(
          '“$clipName” is missing its audio file. Re-import the source file.',
        );
        continue;
      }
      try {
        final header = parsePcm16Wav(bytes);
        decoded = _DecodedPcmAsset(
          header: header,
          samples: decodePcm16Samples(bytes, header),
        );
        decodedByAssetId[asset.id] = decoded;
      } on FormatException {
        problems.add(
          '“$clipName” is not a supported PCM16 WAV. Use one or two channels '
          'at 8,000–96,000 Hz, then re-import it.',
        );
        continue;
      }
    }

    final frameCount = decoded.header.frameCount;
    final trimStart = (pattern.trimStartMs * decoded.header.sampleRate / 1000)
        .round()
        .clamp(0, frameCount);
    final trimEnd =
        (frameCount -
                (pattern.trimEndMs * decoded.header.sampleRate / 1000).round())
            .clamp(trimStart, frameCount);
    final startSampleIndex = trimStart * decoded.header.channels;
    final endSampleIndex = trimEnd * decoded.header.channels;
    final trimmed = Int16List.fromList(
      decoded.samples.sublist(startSampleIndex, endSampleIndex),
    );
    samplesByPatternId[pattern.id] = downmixAndResamplePcm16(
      trimmed,
      channels: decoded.header.channels,
      sourceRate: decoded.header.sampleRate,
      targetRate: sampleRate,
    );
  }

  if (problems.isNotEmpty) {
    throw SongAudioExportPreflightException(List.unmodifiable(problems));
  }
  return renderSongPcm(
    project,
    sampleRate: sampleRate,
    audioSamplesByPatternId: samplesByPatternId,
  );
}

/// Downmixes interleaved mono/stereo PCM16 frames and linearly resamples them.
Int16List downmixAndResamplePcm16(
  Int16List interleavedSamples, {
  required int channels,
  required int sourceRate,
  int targetRate = 44100,
}) {
  if (channels != 1 && channels != 2) {
    throw ArgumentError.value(channels, 'channels', 'Must be 1 or 2');
  }
  if (sourceRate < 8000 || sourceRate > 96000) {
    throw ArgumentError.value(sourceRate, 'sourceRate', 'Must be 8–96 kHz');
  }
  if (targetRate <= 0 || interleavedSamples.length % channels != 0) {
    throw ArgumentError('Invalid target rate or incomplete PCM16 frame');
  }

  final sourceFrames = interleavedSamples.length ~/ channels;
  if (sourceFrames == 0) return Int16List(0);
  final mono = Float64List(sourceFrames);
  for (var frame = 0; frame < sourceFrames; frame++) {
    final base = frame * channels;
    var sum = 0;
    for (var channel = 0; channel < channels; channel++) {
      sum += interleavedSamples[base + channel];
    }
    mono[frame] = sum / channels;
  }

  if (sourceRate == targetRate) {
    return Int16List.fromList([for (final sample in mono) sample.round()]);
  }

  final targetFrames = (sourceFrames * targetRate / sourceRate).round();
  final output = Int16List(targetFrames);
  for (var targetFrame = 0; targetFrame < targetFrames; targetFrame++) {
    final sourcePosition = targetFrame * sourceRate / targetRate;
    final sourceIndex = sourcePosition.floor().clamp(0, sourceFrames - 1);
    final nextIndex = math.min(sourceIndex + 1, sourceFrames - 1);
    final fraction = (sourcePosition - sourceIndex).clamp(0.0, 1.0);
    final sample =
        mono[sourceIndex] + (mono[nextIndex] - mono[sourceIndex]) * fraction;
    output[targetFrame] = sample.round().clamp(-32768, 32767);
  }
  return output;
}

class _DecodedPcmAsset {
  final Pcm16WavData header;
  final Int16List samples;

  const _DecodedPcmAsset({required this.header, required this.samples});
}
