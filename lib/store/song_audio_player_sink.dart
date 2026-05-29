/// Production [SongAudioClipSink] backed by one `AudioPlayer` per active clip.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart';

class AudioPlayersClipSink implements SongAudioClipSink {
  final SongAudioRepository repository;
  final Map<String, AudioPlayer> _players = {};

  AudioPlayersClipSink(this.repository);

  @override
  Future<void> startClip(
      {required AudioAsset asset, required int offsetMs}) async {
    final file = await repository.resolvePath(asset.id, asset.format);
    if (!file.existsSync()) return;
    final player = _players.putIfAbsent(asset.id, AudioPlayer.new);
    await player.stop();
    await player.setSource(DeviceFileSource(file.path));
    await player.seek(Duration(milliseconds: offsetMs));
    await player.resume();
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    final player = _players[asset.id];
    if (player == null) return;
    await player.stop();
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
final productionSongAudioClipSinkProvider =
    Provider<SongAudioClipSink>((ref) {
  return AudioPlayersClipSink(ref.read(songAudioRepositoryProvider));
});
