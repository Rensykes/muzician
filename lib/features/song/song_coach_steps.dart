/// Coach-tour steps for the Song page.
library;

import 'package:flutter/widgets.dart';

import '../../ui/core/coach_overlay.dart';

/// The GlobalKeys the Song screen attaches to its tour targets.
class SongCoachKeys {
  SongCoachKeys();
  final transport = GlobalKey();
  final timeline = GlobalKey();
  final addTrack = GlobalKey();
  final overflow = GlobalKey();
}

List<CoachStep> songCoachSteps(SongCoachKeys k) => [
  CoachStep(
    key: k.transport,
    title: 'Transport',
    body:
        'Play, loop, and practice here. Drag the ruler for a loop region; the '
        'chips set practice tempo (½×/¾×), metronome, count-in, and snap.',
  ),
  CoachStep(
    key: k.timeline,
    title: 'Timeline',
    body:
        'Long-press a lane to add a clip; tap a clip to open the action bar '
        '(split, transpose, trim, duplicate, move). Tap the ruler to seek, '
        'double-tap it to drop a marker.',
  ),
  CoachStep(
    key: k.addTrack,
    title: 'Add tracks',
    body: 'Create note, drum, or audio tracks.',
  ),
  CoachStep(
    key: k.overflow,
    title: 'More',
    body:
        'Start a new song, import an arrangement from Writer, or export a WAV.',
  ),
];
