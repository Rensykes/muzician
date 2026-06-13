/// Coach-tour steps for the Writer page.
library;

import 'package:flutter/widgets.dart';

import '../../ui/core/coach_overlay.dart';

/// The GlobalKeys the Writer sheet attaches to its tour targets.
class WriterCoachKeys {
  WriterCoachKeys();
  final header = GlobalKey();
  final body = GlobalKey();
  final addSection = GlobalKey();
}

List<CoachStep> writerCoachSteps(WriterCoachKeys k) => [
  CoachStep(
    key: k.header,
    title: 'Header',
    body:
        'Set the key and tempo, play the arrangement, and toggle the '
        'metronome. The ⋮ menu has save / load and structure editing.',
  ),
  CoachStep(
    key: k.body,
    title: 'Sections',
    body:
        'Tap a bar to drop a chord from the wheel. A section’s ⋮ menu adds '
        'drum lanes and sets repeats.',
  ),
  CoachStep(
    key: k.addSection,
    title: 'Build structure',
    body: 'Add sections to lay out the whole song, verse by chorus.',
  ),
];
