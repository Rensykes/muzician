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
    targetTrackId: targetTrackId != null ? targetTrackId() : this.targetTrackId,
    startTick: startTick != null ? startTick() : this.startTick,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    pendingAsset: pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
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
        if (state.status != SongAudioRecorderStatus.countIn) return;
        NotePlayer.instance.playDrumLane(DrumLaneId.closedHiHat);
        await Future<void>.delayed(beatSpacing);
      }
    }

    if (state.status != SongAudioRecorderStatus.countIn) return;
    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    _startBackgroundPlayback(startTick);
    await driver.start();
  }

  Future<void> stop() async {
    if (state.status != SongAudioRecorderStatus.recording) return;
    state = state.copyWith(status: SongAudioRecorderStatus.finalising);
    _stopBackgroundPlayback();
    final driver = ref.read(songAudioRecorderDriverProvider);
    try {
      final bytes = await driver.stop();
      final repo = ref.read(songAudioRepositoryProvider);
      final asset = await repo.writeRecording(bytes);
      state = state.copyWith(
        status: SongAudioRecorderStatus.ready,
        pendingAsset: () => asset,
        elapsedMs: asset.durationMs,
      );
    } catch (e) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    }
    _restoreTargetTrackMute();
  }

  /// Cancels an active count-in or recording without producing an asset.
  /// Safe to call in any state.
  Future<void> cancel() async {
    final st = state.status;
    if (st == SongAudioRecorderStatus.idle) return;
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

  Future<void> reset() async {
    _stopBackgroundPlayback();
    _restoreTargetTrackMute();
    state = const SongAudioRecorderState();
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
