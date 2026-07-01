/// Orchestrates pitch-preserving stretch re-rendering for audio clips.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/songwriter.dart';
import '../schema/rules/audio_stretch_rules.dart';
import '../schema/rules/song_audio_rules.dart' show downmixToMono;
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

  /// Clip ids that asked for a re-render while one was already in flight for
  /// them. Drained in [rerender]'s `finally` so a tempo/trim change that lands
  /// mid-render isn't dropped — otherwise the clip stays sized to the stale
  /// target after rapid tempo changes.
  final Set<String> _pendingRerun = <String>{};

  /// (Re)renders the stretched derived asset for [clipId] sized to its bar span.
  /// No-op for unplaced clips or clips with no source asset.
  Future<void> rerender(String clipId) async {
    // One in-flight render per clip — prevents orphaned derived files from
    // concurrent triggers (rapid stepper taps, tempo-watcher overlap). A
    // request that arrives mid-render is remembered and replayed afterward so
    // the final render reflects the latest tempo/trim.
    if (ref.read(songwriterStretchProcessingProvider).contains(clipId)) {
      _pendingRerun.add(clipId);
      return;
    }
    final project = ref.read(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final targetMs = stretchTargetMs(project, clipId);
    if (targetMs == null || targetMs <= 0) return;
    final source = project.audioAssets
        .where((a) => a.id == clip.assetId)
        .firstOrNull;
    if (source == null) return;
    const maxStretchMs = 30000;
    if (source.durationMs > maxStretchMs) {
      return; // too long to stretch in-process
    }

    final processing = ref.read(songwriterStretchProcessingProvider.notifier);
    processing.update((s) => {...s, clipId});
    try {
      final repo = ref.read(songwriterAudioRepositoryProvider);
      final raw = await repo.readInt16Samples(source.id, source.format);
      final sr = source.sampleRate <= 0 ? 44100 : source.sampleRate;
      // Stretch is a mono algorithm; collapse interleaved stereo first so the
      // region math and the pitch-preserving output are correct.
      final all = downmixToMono(raw, source.channels);
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
      final applied = ref
          .read(songwriterProvider.notifier)
          .setClipStretchedAsset(
            clipId: clipId,
            stretchedAsset: asset,
            removeAssetId: prev,
          );
      if (!applied) {
        // The clip (or its placement) was removed while we rendered, so the
        // just-written file is unreferenced — drop it instead of leaking it.
        await repo.delete(asset.id);
      }
    } finally {
      processing.update((s) => {...s}..remove(clipId));
      // Replay a request that arrived mid-render against the latest state.
      if (_pendingRerun.remove(clipId)) {
        unawaited(rerender(clipId));
      }
    }
  }
}

final songwriterStretchControllerProvider =
    Provider<SongwriterStretchController>(
      (ref) => SongwriterStretchController(ref),
    );

/// Watches the project tempo and re-renders every stretch clip when it changes.
/// Mount once (read it from the songwriter screen) so the listener stays alive
/// while the tab is open.
final songwriterStretchTempoWatcherProvider = Provider<void>((ref) {
  ref.listen<int>(songwriterProvider.select((p) => p.config.tempo), (
    prev,
    next,
  ) {
    if (prev == null || prev == next) return;
    final controller = ref.read(songwriterStretchControllerProvider);
    for (final clip in ref.read(songwriterProvider).audioClips) {
      if (clip.fitMode == AudioFitMode.stretch) {
        controller.rerender(clip.id);
      }
    }
  });
});
