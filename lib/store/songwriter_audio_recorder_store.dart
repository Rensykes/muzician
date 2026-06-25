/// Project-agnostic count-in -> record -> ready state machine for the Songwriter
/// audio lane. Owns no project state: the caller commits the recorded asset.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart' show AudioAsset, DrumLaneId;
import '../utils/note_player.dart';
import 'song_audio_recorder_store.dart'
    show SongAudioRecorderStatus, songAudioRecorderDriverProvider;
import 'song_audio_repository.dart';

class SongwriterAudioRecorderState {
  final SongAudioRecorderStatus status;
  final AudioAsset? pendingAsset;
  final String? errorMessage;
  const SongwriterAudioRecorderState({
    this.status = SongAudioRecorderStatus.idle,
    this.pendingAsset,
    this.errorMessage,
  });
  SongwriterAudioRecorderState copyWith({
    SongAudioRecorderStatus? status,
    AudioAsset? Function()? pendingAsset,
    String? Function()? errorMessage,
  }) => SongwriterAudioRecorderState(
    status: status ?? this.status,
    pendingAsset: pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

class SongwriterAudioRecorderNotifier
    extends Notifier<SongwriterAudioRecorderState> {
  bool _cancelled = false;

  @override
  SongwriterAudioRecorderState build() => const SongwriterAudioRecorderState();

  Future<void> start({int countInMs = 0}) async {
    final st = state.status;
    if (st != SongAudioRecorderStatus.idle &&
        st != SongAudioRecorderStatus.error) {
      return;
    }
    _cancelled = false;
    final driver = ref.read(songAudioRecorderDriverProvider);
    if (!await driver.ensurePermission()) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }
    state = const SongwriterAudioRecorderState(
      status: SongAudioRecorderStatus.countIn,
    );
    if (countInMs > 0) {
      final beat = Duration(milliseconds: (countInMs / 4).round());
      for (var i = 0; i < 4; i++) {
        if (state.status != SongAudioRecorderStatus.countIn) return;
        NotePlayer.instance.playDrumLane(DrumLaneId.closedHiHat);
        await Future<void>.delayed(beat);
      }
    }
    if (state.status != SongAudioRecorderStatus.countIn) return;
    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    await driver.start();
  }

  Future<void> stop() async {
    if (state.status != SongAudioRecorderStatus.recording) return;
    state = state.copyWith(status: SongAudioRecorderStatus.finalising);
    final driver = ref.read(songAudioRecorderDriverProvider);
    try {
      final bytes = await driver.stop();
      final asset = await ref
          .read(songwriterAudioRepositoryProvider)
          .writeRecording(bytes);
      if (_cancelled) {
        try {
          await ref.read(songwriterAudioRepositoryProvider).delete(asset.id);
        } catch (_) {}
        state = const SongwriterAudioRecorderState();
        return;
      }
      state = state.copyWith(
        status: SongAudioRecorderStatus.ready,
        pendingAsset: () => asset,
      );
    } catch (e) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (state.status == SongAudioRecorderStatus.idle) return;
    if (state.status == SongAudioRecorderStatus.recording) {
      try {
        await ref.read(songAudioRecorderDriverProvider).stop();
      } catch (_) {}
    }
    final asset = state.pendingAsset;
    if (asset != null) {
      try {
        await ref.read(songwriterAudioRepositoryProvider).delete(asset.id);
      } catch (_) {}
    }
    state = const SongwriterAudioRecorderState();
  }

  AudioAsset? consumePendingAsset() {
    final asset = state.pendingAsset;
    state = const SongwriterAudioRecorderState();
    return asset;
  }
}

final songwriterAudioRecorderProvider =
    NotifierProvider<
      SongwriterAudioRecorderNotifier,
      SongwriterAudioRecorderState
    >(SongwriterAudioRecorderNotifier.new);
