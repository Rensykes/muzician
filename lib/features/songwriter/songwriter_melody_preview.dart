import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/song_project.dart';
import '../../theme/studio_theme.dart';

typedef MelodyPreviewNote = ({int startTick, int endTick, int midiNote});

class SongwriterMelodyPreview extends StatelessWidget {
  const SongwriterMelodyPreview({
    super.key,
    required this.pattern,
    required this.segmentStartTick,
    required this.segmentEndTick,
  });
  final NotePattern pattern;
  final int segmentStartTick;
  final int segmentEndTick;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MelodyPreviewPainter(
      pattern: pattern,
      segmentStartTick: segmentStartTick,
      segmentEndTick: segmentEndTick,
      palette: StudioPalette.of(context),
    ),
    child: const SizedBox.expand(),
  );
}

class _MelodyPreviewPainter extends CustomPainter {
  _MelodyPreviewPainter({
    required this.pattern,
    required this.segmentStartTick,
    required this.segmentEndTick,
    required this.palette,
  });

  final NotePattern pattern;
  final int segmentStartTick;
  final int segmentEndTick;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final notes = melodyPreviewNotes(
      pattern: pattern,
      segmentStartTick: segmentStartTick,
      segmentEndTick: segmentEndTick,
    );
    if (notes.isEmpty || size.isEmpty) return;
    final pitches = pattern.notes
        .where(
          (note) => note.startTick >= 0 && note.startTick < pattern.lengthTicks,
        )
        .map((note) => note.midiNote);
    final low = pitches.reduce(math.min);
    final high = pitches.reduce(math.max);
    final range = high - low + 1;
    final rowHeight = (size.height - 6).clamp(0.0, double.infinity) / range;
    // Wide ranges cannot fit a distinct 2px row per semitone; preserve pitch
    // centers and allow adjacent bars to overlap rather than becoming invisible.
    final height = math.min(
      size.height,
      math.max(2.0, math.min(5.0, rowHeight * .75)),
    );
    final paint = Paint()..color = palette.teal.withValues(alpha: .8);
    for (final note in notes) {
      final x =
          size.width *
          (note.startTick - segmentStartTick) /
          (segmentEndTick - segmentStartTick);
      final right =
          size.width *
          (note.endTick - segmentStartTick) /
          (segmentEndTick - segmentStartTick);
      final y = 3 + (high - note.midiNote + .5) * rowHeight - height / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, y, right, y + height),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MelodyPreviewPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.segmentStartTick != segmentStartTick ||
      oldDelegate.segmentEndTick != segmentEndTick ||
      oldDelegate.palette != palette;
}

List<MelodyPreviewNote> melodyPreviewNotes({
  required NotePattern pattern,
  required int segmentStartTick,
  required int segmentEndTick,
}) {
  final length = pattern.lengthTicks;
  if (length <= 0 ||
      pattern.notes.isEmpty ||
      segmentEndTick <= segmentStartTick ||
      segmentEndTick <= 0) {
    return [];
  }
  final windowStart = segmentStartTick < 0 ? 0 : segmentStartTick;
  final windowEnd = segmentEndTick < length ? segmentEndTick : length;
  if (windowStart >= windowEnd) return [];
  final result = <MelodyPreviewNote>[];
  for (final note in pattern.notes) {
    if (note.startTick < 0 || note.startTick >= length) continue;
    final start = note.startTick;
    final noteEnd = start + (note.durationTicks < 1 ? 1 : note.durationTicks);
    final end = noteEnd < length ? noteEnd : length;
    final visibleStart = start < windowStart ? windowStart : start;
    final visibleEnd = end < windowEnd ? end : windowEnd;
    if (visibleStart < visibleEnd) {
      result.add((
        startTick: visibleStart,
        endTick: visibleEnd,
        midiNote: note.midiNote,
      ));
    }
  }
  return result;
}
