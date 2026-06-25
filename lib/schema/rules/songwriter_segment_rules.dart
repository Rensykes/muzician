/// Pure helpers for in-clip chord segments (clip-local tick space).
library;

import '../../models/songwriter.dart';

/// Total clip-local ticks for a span of [spanBars].
int clipSpanTicks(int spanBars, SongwriterConfig config) =>
    spanBars * config.beatsPerBar * config.ticksPerBeat;

/// Drops segments starting at/after [spanTotalTicks]; clamps a straddler's span
/// to end exactly at [spanTotalTicks].
List<ChordSegment> clampedSegments(
  List<ChordSegment> segments,
  int spanTotalTicks,
) {
  final out = <ChordSegment>[];
  for (final s in segments) {
    if (s.startTick >= spanTotalTicks) continue;
    final end = s.startTick + s.spanTicks;
    out.add(
      end > spanTotalTicks
          ? s.copyWith(spanTicks: spanTotalTicks - s.startTick)
          : s,
    );
  }
  return out;
}

/// The segment whose half-open range covers [tick], or null.
ChordSegment? segmentAtTick(List<ChordSegment> segments, int tick) {
  for (final s in segments) {
    if (tick >= s.startTick && tick < s.startTick + s.spanTicks) return s;
  }
  return null;
}
