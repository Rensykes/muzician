/// State machine for the song audio overdub flow: count-in → recording →
/// ready (auto-commits via sheet pop).  All side effects (mic, files,
/// background song transport) are injected via providers so tests can swap
/// them.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';
import '../utils/note_player.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart';
import 'song_project_store.dart';

enum SongAudioRecorderStatus {
  idle,
  countIn,
  recording,
  finalising,
  ready,
  error,
}

class SongAudioRecorderState {
  final SongAudioRecorderStatus status;
  final String? targetTrackId;
  final int? startTick;
  final int elapsedMs;
  final AudioAsset? pendingAsset;
  final String? errorMessage;
  final bool isPreviewing;

  const SongAudioRecorderState({
    this.status = SongAudioRecorderStatus.idle,
    this.targetTrackId,
    this.startTick,
    this.elapsedMs = 0,
    this.pendingAsset,
    this.errorMessage,
    this.isPreviewing = false,
  });

  SongAudioRecorderState copyWith({
    SongAudioRecorderStatus? status,
    String? Function()? targetTrackId,
    int? Function()? startTick,
    int? elapsedMs,
    AudioAsset? Function()? pendingAsset,
    String? Function()? errorMessage,
    bool? isPreviewing,
  }) => SongAudioRecorderState(
    status: status ?? this.status,
    targetTrackId: targetTrackId != null ? targetTrackId() : this.targetTrackId,
    startTick: startTick != null ? startTick() : this.startTick,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    pendingAsset: pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    isPreviewing: isPreviewing ?? this.isPreviewing,
  );
}

/// Abstraction over the real `record` package so tests can inject a fake.
abstract class SongAudioRecorderDriver {
  Future<bool> ensurePermission();

  /// Starts capture. [manageIosAudioSession] forwards to the `record` package's
  /// `IosRecordConfig.manageAudioSession`: pass `false` when another plugin
  /// (here, `audioplayers` for record-time monitoring) already owns the shared
  /// AVAudioSession, so the two don't fight over it and silence the capture.
  Future<void> start({bool manageIosAudioSession = true});
  Future<Uint8List> stop();
  Future<void> dispose();
}

final songAudioRecorderDriverProvider = Provider<SongAudioRecorderDriver>((
  ref,
) {
  throw UnimplementedError(
    'Override songAudioRecorderDriverProvider in real launches and tests',
  );
});

class SongAudioRecorderNotifier extends Notifier<SongAudioRecorderState> {
  bool? _originalMuted;
  int _recordingGeneration = 0;
  int _previewGeneration = 0;

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
    final generation = ++_recordingGeneration;
    final driver = ref.read(songAudioRecorderDriverProvider);
    final permitted = await driver.ensurePermission();
    if (generation != _recordingGeneration) return;
    if (!permitted) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }

    final projectNotifier = ref.read(songProjectProvider.notifier);
    final project = ref.read(songProjectProvider);
    final track = project.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Track not found',
      );
      return;
    }
    _originalMuted = track.isMuted;
    if (!track.isMuted) projectNotifier.toggleMute(trackId);

    state = SongAudioRecorderState(
      status: SongAudioRecorderStatus.countIn,
      targetTrackId: trackId,
      startTick: startTick,
    );
    if (countInMs > 0) {
      // Emit four metronome blips evenly spaced across the count-in.  The
      // first one fires immediately so the user gets a clear "1" downbeat,
      // and we abandon the loop if the state has been cancelled.
      final beatSpacing = Duration(milliseconds: (countInMs / 4).round());
      for (var i = 0; i < 4; i++) {
        if (generation != _recordingGeneration ||
            state.status != SongAudioRecorderStatus.countIn) {
          return;
        }
        NotePlayer.instance.playDrumLane(DrumLaneId.closedHiHat);
        await Future<void>.delayed(beatSpacing);
      }
    }

    if (generation != _recordingGeneration ||
        state.status != SongAudioRecorderStatus.countIn) {
      return;
    }
    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    _startBackgroundPlayback(startTick);
    try {
      await driver.start();
    } catch (e) {
      if (generation != _recordingGeneration) return;
      _stopBackgroundPlayback();
      _restoreTargetTrackMute();
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    }
  }

  Future<void> stop() async {
    if (state.status != SongAudioRecorderStatus.recording) return;
    final generation = _recordingGeneration;
    state = state.copyWith(status: SongAudioRecorderStatus.finalising);
    _stopBackgroundPlayback();
    final driver = ref.read(songAudioRecorderDriverProvider);
    try {
      final bytes = await driver.stop();
      final repo = ref.read(songAudioRepositoryProvider);
      final asset = await repo.writeRecording(bytes);
      if (generation != _recordingGeneration) {
        await repo.delete(asset.id);
        return;
      }
      state = state.copyWith(
        status: SongAudioRecorderStatus.ready,
        pendingAsset: () => asset,
        elapsedMs: asset.durationMs,
      );
    } catch (e) {
      if (generation != _recordingGeneration) return;
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    } finally {
      _restoreTargetTrackMute();
    }
  }

  /// Cancels an active count-in or recording without producing an asset.
  /// Safe to call in any state.
  Future<void> cancel() async {
    ++_recordingGeneration;
    final st = state.status;
    if (st == SongAudioRecorderStatus.idle) return;
    await stopPreview();
    _stopBackgroundPlayback();
    if (st == SongAudioRecorderStatus.recording) {
      final driver = ref.read(songAudioRecorderDriverProvider);
      try {
        await driver.stop();
      } catch (_) {
        // ignore: cancellation should not surface driver errors.
      }
    }
    final asset = state.pendingAsset;
    if (asset != null) {
      final repo = ref.read(songAudioRepositoryProvider);
      try {
        await repo.delete(asset.id);
      } catch (_) {
        // ignore
      }
    }
    _restoreTargetTrackMute();
    state = const SongAudioRecorderState();
  }

  /// Releases the pending asset for the caller to commit it to the project,
  /// then returns the recorder to idle.
  AudioAsset? consumePendingAsset() {
    final asset = state.pendingAsset;
    state = const SongAudioRecorderState();
    return asset;
  }

  /// Stops audition playback and releases the pending take for commitment.
  Future<AudioAsset?> acceptPendingTake() async {
    await stopPreview();
    return consumePendingAsset();
  }

  /// Replaces the pending take with a fresh recording at the same target.
  Future<void> rerecord({int countInMs = 0}) async {
    if (state.status != SongAudioRecorderStatus.ready) return;
    final trackId = state.targetTrackId;
    final startTick = state.startTick;
    if (trackId == null || startTick == null) return;
    await stopPreview();
    final pending = state.pendingAsset;
    if (pending != null) {
      await ref.read(songAudioRepositoryProvider).delete(pending.id);
    }
    state = const SongAudioRecorderState();
    await start(trackId: trackId, startTick: startTick, countInMs: countInMs);
  }

  /// Plays the pending take once through the same audio sink used by Song.
  Future<void> previewPendingTake() async {
    final asset = state.pendingAsset;
    if (state.status != SongAudioRecorderStatus.ready || asset == null) return;
    final generation = ++_previewGeneration;
    final sink = ref.read(songAudioClipSinkProvider);
    try {
      await sink.stopClip(asset: asset);
      await sink.prepare([asset]);
      if (generation != _previewGeneration) return;
      await sink.startClip(asset: asset, offsetMs: 0);
      if (generation != _previewGeneration) {
        await sink.stopClip(asset: asset);
        return;
      }
      state = state.copyWith(isPreviewing: true, errorMessage: () => null);
      unawaited(_stopPreviewAfter(asset, generation));
    } catch (_) {
      if (generation == _previewGeneration) {
        state = state.copyWith(
          isPreviewing: false,
          errorMessage: () => 'Could not audition this take.',
        );
      }
    }
  }

  /// Ends any active audition without deleting the pending take.
  Future<void> stopPreview() async {
    ++_previewGeneration;
    final asset = state.pendingAsset;
    if (asset != null) {
      try {
        await ref.read(songAudioClipSinkProvider).stopClip(asset: asset);
      } catch (_) {
        // Preview cleanup must not prevent accepting or discarding a take.
      }
    }
    if (state.isPreviewing) {
      state = state.copyWith(isPreviewing: false);
    }
  }

  Future<void> reset() async {
    await cancel();
  }

  Future<void> _stopPreviewAfter(AudioAsset asset, int generation) async {
    await Future<void>.delayed(Duration(milliseconds: asset.durationMs));
    if (generation != _previewGeneration ||
        state.pendingAsset?.id != asset.id) {
      return;
    }
    try {
      await ref.read(songAudioClipSinkProvider).stopClip(asset: asset);
    } catch (_) {
      // The player may already have stopped at the end of the take.
    }
    if (generation == _previewGeneration &&
        state.pendingAsset?.id == asset.id) {
      state = state.copyWith(isPreviewing: false);
    }
  }

  void _startBackgroundPlayback(int startTick) {
    final playback = ref.read(songPlaybackProvider.notifier);
    playback.stopPlayback();
    unawaited(playback.startPlayback(startTick: startTick));
  }

  void _stopBackgroundPlayback() {
    ref.read(songPlaybackProvider.notifier).stopPlayback();
  }

  /// Restores the target track's mute state to what it was before the
  /// recording started.  If the user had it muted to begin with, leave it
  /// muted; otherwise unmute.
  void _restoreTargetTrackMute() {
    final restoredId = state.targetTrackId;
    final originalMuted = _originalMuted;
    if (restoredId == null || originalMuted == null) return;
    final project = ref.read(songProjectProvider);
    final t = project.tracks.where((x) => x.id == restoredId).firstOrNull;
    if (t != null && t.isMuted != originalMuted) {
      ref.read(songProjectProvider.notifier).toggleMute(restoredId);
    }
    _originalMuted = null;
  }
}

final songAudioRecorderProvider =
    NotifierProvider<SongAudioRecorderNotifier, SongAudioRecorderState>(
      SongAudioRecorderNotifier.new,
    );
