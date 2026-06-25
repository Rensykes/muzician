/// Orchestrates pitch-preserving stretch re-rendering for audio clips.
library;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../schema/rules/audio_stretch_rules.dart';
import '../schema/rules/songwriter_stretch_rules.dart';
import 'song_audio_repository.dart';
import 'songwriter_store.dart';

/// Clip ids currently being (re)rendered.
final songwriterStretchProcessingProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

class SongwriterStretchController {
  SongwriterStretchController(this.ref);
  final Ref ref;

  /// (Re)renders the stretched derived asset for [clipId] sized to its bar span.
  /// No-op for unplaced clips or clips with no source asset.
  Future<void> rerender(String clipId) async {
    final project = ref.read(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final targetMs = stretchTargetMs(project, clipId);
    if (targetMs == null || targetMs <= 0) return;
    final source = project.audioAssets
        .where((a) => a.id == clip.assetId)
        .firstOrNull;
    if (source == null) return;

    final processing = ref.read(songwriterStretchProcessingProvider.notifier);
    processing.update((s) => {...s, clipId});
    try {
      final repo = ref.read(songwriterAudioRepositoryProvider);
      final all = await repo.readInt16Samples(source.id, source.format);
      final sr = source.sampleRate;
      final from = (clip.trimStartMs * sr ~/ 1000).clamp(0, all.length);
      final rawTo = clip.trimEndMs == 0
          ? all.length
          : (clip.trimEndMs * sr ~/ 1000);
      final to = rawTo.clamp(from, all.length);
      final region = all.sublist(from, to);
      final stretched = await compute(
        runStretch,
        StretchRequest(region, sr, targetMs),
      );
      final asset = await repo.writeStretched(
        samples: stretched,
        sampleRate: sr,
      );
      final prev = clip.stretchedAssetId;
      if (prev != null) await repo.delete(prev);
      ref
          .read(songwriterProvider.notifier)
          .setClipStretchedAsset(
            clipId: clipId,
            stretchedAsset: asset,
            removeAssetId: prev,
          );
    } finally {
      processing.update((s) => {...s}..remove(clipId));
    }
  }
}

final songwriterStretchControllerProvider =
    Provider<SongwriterStretchController>(
      (ref) => SongwriterStretchController(ref),
    );
