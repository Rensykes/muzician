import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_segment_rules.dart';

void main() {
  const segs = [
    ChordSegment(id: 's1', startTick: 0, spanTicks: 480, chordSymbol: 'C'),
    ChordSegment(id: 's2', startTick: 960, spanTicks: 960, chordSymbol: 'G'),
  ];

  test(
    'clampedSegments drops segments past the new span and clamps a straddler',
    () {
      final out = clampedSegments([
        ...segs,
        const ChordSegment(
          id: 's3',
          startTick: 1300,
          spanTicks: 480,
          chordSymbol: 'F',
        ),
      ], 1200);
      expect(out.map((s) => s.id), ['s1', 's2']);
      expect(
        out.firstWhere((s) => s.id == 's2').spanTicks,
        240,
      ); // 960+960=1920 -> clamp to 1200
    },
  );

  test('segmentAtTick finds the covering segment', () {
    expect(segmentAtTick(segs, 100)?.id, 's1');
    expect(
      segmentAtTick(segs, 500),
      isNull,
    ); // gap (s1 ends at 480, s2 starts 960)
    expect(segmentAtTick(segs, 1000)?.id, 's2');
  });

  test('clipSpanTicks = spanBars * beatsPerBar * ticksPerBeat', () {
    const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    expect(clipSpanTicks(2, cfg), 2 * 4 * cfg.ticksPerBeat);
  });
}
