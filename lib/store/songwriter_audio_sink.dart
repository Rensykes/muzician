/// Clip sink for the Songwriter transport. Defaults to the no-op sink; the real
/// [AudioPlayersClipSink] (bound to the songwriter audio repository) is wired in
/// main.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'song_audio_player_sink.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart' show SongAudioClipSink, NoopSongAudioClipSink;

final songwriterAudioClipSinkProvider = Provider<SongAudioClipSink>(
  (ref) => const NoopSongAudioClipSink(),
);

final productionSongwriterAudioClipSinkProvider = Provider<SongAudioClipSink>(
  (ref) => AudioPlayersClipSink(ref.read(songwriterAudioRepositoryProvider)),
);
