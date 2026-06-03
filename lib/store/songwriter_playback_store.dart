/// Songwriter transport: a bar/tick clock that drives a playhead and a
/// metronome. v1 blocks are silent visual guides — no block audio.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/note_player.dart';

typedef SongwriterMetronomeSink = Future<void> Function({required bool accent});

final songwriterMetronomeSinkProvider = Provider<SongwriterMetronomeSink>((ref) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});
