/// Production [SongAudioClipSink] backed by one `AudioPlayer` per asset.
///
/// Sets a global iOS audio session that allows multiple internal
/// `AVAudioPlayer` instances to coexist (mixes within the app) and pre-loads
/// every player's source at [prepare] time so the tick loop's parallel
/// startClip calls only have to seek + resume.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart';

class AudioPlayersClipSink implements SongAudioClipSink {
  AudioPlayersClipSink(this.repository) {
    // Run once per sink lifetime: configure the global audio session so
    // concurrent in-app playback does not interrupt itself.  Without
    // `mixWithOthers`, a new player's session activation can preempt any
    // other player whose preparation has not yet completed.
    AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
  }

  final SongAudioRepository repository;
  final Map<String, AudioPlayer> _players = {};

  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {
    for (final asset in assets) {
      final file = await repository.resolvePath(asset.id, asset.format);
      if (!file.existsSync()) continue;
      final player = _players.putIfAbsent(asset.id, () {
        final p = AudioPlayer();
        // Keep the loaded source after `stop()` so subsequent plays only
        // need to seek + resume.
        p.setReleaseMode(ReleaseMode.stop);
        return p;
      });
      // Always (re)bind the source — covers replaced/re-recorded assets and
      // the first-time load on a fresh player.
      await player.setSource(DeviceFileSource(file.path));
      await player.pause();
    }
  }

  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async {
    var player = _players[asset.id];
    if (player == null) {
      // Lazy fall-back path: a clip was added after [prepare] (e.g. the user
      // imported during playback).  Load + bind now.
      final file = await repository.resolvePath(asset.id, asset.format);
      if (!file.existsSync()) return;
      player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(DeviceFileSource(file.path));
      _players[asset.id] = player;
    }
    await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    await player.setVolume(volume.clamp(0.0, 1.0));
    await player.seek(Duration(milliseconds: offsetMs));
    await player.resume();
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    final player = _players[asset.id];
    if (player == null) return;
    await player.stop();
    await player.setReleaseMode(ReleaseMode.stop);
  }

  @override
  Future<void> stopAll() async {
    for (final player in _players.values) {
      await player.stop();
    }
  }
}

/// Override in `main.dart` to swap the no-op sink in [songAudioClipSinkProvider]
/// for the real one.  Tests keep using the no-op default unless they override
/// the same provider explicitly.
final productionSongAudioClipSinkProvider = Provider<SongAudioClipSink>((ref) {
  return AudioPlayersClipSink(ref.read(songAudioRepositoryProvider));
});
