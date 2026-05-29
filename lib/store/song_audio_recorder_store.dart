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
  /// then returns the recorder to idle.
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
