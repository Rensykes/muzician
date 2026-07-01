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
  final String _subdir;
  final Uuid _uuid;
  Directory? _rootCache;

  SongAudioRepository._({Directory? root, String? subdir, Uuid? uuid})
    : _rootOverride = root,
      _subdir = subdir ?? 'song_audio',
      _uuid = uuid ?? const Uuid();

  factory SongAudioRepository.production({String? subdir}) =>
      SongAudioRepository._(subdir: subdir);

  /// Test factory: bypasses `path_provider` by pinning the root directory.
  factory SongAudioRepository.testWith({
    required Directory rootDirectory,
    String? subdir,
  }) => SongAudioRepository._(root: rootDirectory, subdir: subdir);

  Future<Directory> _root() async {
    final override = _rootOverride;
    if (override != null) {
      final dir = Directory(p.join(override.path, _subdir));
      if (!dir.existsSync()) await dir.create(recursive: true);
      return dir;
    }
    final cached = _rootCache;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
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
    final samples = extractInt16Samples(wavBytes);
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

  /// Copies an external audio file into the repository.
  ///
  /// For WAV files, the duration is parsed from the header and peaks are
  /// computed.  For MP3 / M4A files, the caller must provide the duration
  /// via [explicitDurationMs] (probed through `audioplayers`), and peaks are
  /// left empty in v1 (waveform renders as a flat band until a later spec
  /// adds decompressed peak computation).
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
      final samples = extractInt16Samples(bytes);
      peaks = computePeaksFromInt16(samples);
    } else {
      durationMs = explicitDurationMs ?? 0;
      sampleRate = 44100; // unknown without a decoder
      channels = 2; // safe default
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

  Future<void> delete(String assetId) async {
    final root = await _root();
    const candidates = <String>['wav', 'mp3', 'm4a'];
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

  Int16List extractInt16Samples(Uint8List wav) {
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
    return SongAudioRepository.production();
  }
  return SongAudioRepository.production();
});

/// Repository for Songwriter audio, isolated in its own `songwriter_audio/`
/// subfolder so its orphan reconcile never touches the Song feature's files.
final songwriterAudioRepositoryProvider = Provider<SongAudioRepository>((ref) {
  return SongAudioRepository.production(subdir: 'songwriter_audio');
});
