/// Injectable hook that readies synthesised voices before a transport starts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/note_player.dart';
import '../utils/playback_voice_spec.dart';

/// Renders and caches [voices] and pre-creates [sequencedPlayers] sequenced
/// players. Must not throw: preparation is best effort.
typedef PlaybackVoicePrepareSink =
    Future<void> Function(
      Iterable<PlaybackVoiceSpec> voices, {
      int sequencedPlayers,
    });

/// Defaults to [NotePlayer]; override in tests to run without real audio.
final playbackVoicePrepareSinkProvider = Provider<PlaybackVoicePrepareSink>(
  (ref) =>
      (voices, {sequencedPlayers = 0}) => NotePlayer.instance
          .prepareForPlayback(voices, sequencedPlayers: sequencedPlayers),
);
