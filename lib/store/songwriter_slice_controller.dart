/// Runs onset detection for a Songwriter audio clip off the UI thread.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../schema/rules/songwriter_slice_rules.dart';
import 'song_audio_repository.dart';
import 'songwriter_store.dart';

/// Detected onsets for the clip currently under inspection, plus an in-flight
/// flag for the debounced detection pass.
class SliceDetectionState {
  const SliceDetectionState({this.onsets = const [], this.processing = false});

  /// Onset sample positions within the clip's TRIMMED region.
  final List<int> onsets;

  /// True while a detection pass is reading samples / running `compute`.
  final bool processing;
}

/// Detects transient onsets for a clip's trimmed region off the UI thread.
/// Call [detect] to (re)run; rapid calls (e.g. a sensitivity slider drag) are
/// debounced ~200ms so only the latest request runs.
class SongwriterSliceController extends Notifier<SliceDetectionState> {
  Timer? _debounce;

  @override
  SliceDetectionState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SliceDetectionState();
  }

  /// (Re)run onset detection for [clipId] at [sensitivity] (0..1, higher ->
  /// more onsets). Debounced; the result lands in [state].
  void detect({required String clipId, required double sensitivity}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _run(clipId, sensitivity);
    });
  }

  /// Clear the current onsets (e.g. when leaving slice mode).
  void clear() {
    _debounce?.cancel();
    state = const SliceDetectionState();
  }

  Future<void> _run(String clipId, double sensitivity) async {
    final project = ref.read(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return;
    final asset = project.audioAssets
        .where((a) => a.id == clip.assetId)
        .firstOrNull;
    if (asset == null) return;

    state = const SliceDetectionState(processing: true);
    final repo = ref.read(songwriterAudioRepositoryProvider);
    final full = await repo.readInt16Samples(asset.id, asset.format);
    if (full.isEmpty) {
      state = const SliceDetectionState();
      return;
    }
    final sr = asset.sampleRate <= 0 ? 44100 : asset.sampleRate;
    final startSample = (clip.trimStartMs * sr ~/ 1000).clamp(0, full.length);
    final endRaw = clip.trimEndMs == 0
        ? full.length
        : (clip.trimEndMs * sr ~/ 1000);
    final endSample = endRaw.clamp(startSample, full.length);
    final region = full.sublist(startSample, endSample);

    final onsets = await compute(
      runDetectOnsets,
      DetectOnsetsRequest(region, sr, sensitivity),
    );
    state = SliceDetectionState(onsets: onsets, processing: false);
  }
}

final songwriterSliceControllerProvider =
    NotifierProvider<SongwriterSliceController, SliceDetectionState>(
      SongwriterSliceController.new,
    );
