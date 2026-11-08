/// Clip sink for the Songwriter transport. Defaults to the no-op sink; the real
/// [AudioPlayersClipSink] (bound to the songwriter audio repository) is wired in
/// main.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_player_sink.dart';
import 'audio_repository.dart';
import 'audio_clip_sink.dart';

final songwriterAudioClipSinkProvider = Provider<AudioClipSink>(
  (ref) => const NoopAudioClipSink(),
);

final productionSongwriterAudioClipSinkProvider = Provider<AudioClipSink>(
  (ref) => AudioPlayersClipSink(ref.read(songwriterAudioRepositoryProvider)),
);
