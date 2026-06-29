import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('makeAudioClip sets full-region trim + loop default', () {
    final clip = makeAudioClip(assetId: 'a1', durationMs: 4000);
    expect(clip.id, isNotEmpty);
    expect(clip.assetId, 'a1');
    expect(clip.trimStartMs, 0);
    expect(clip.trimEndMs, 4000);
    expect(clip.fitMode, AudioFitMode.loop);
    expect(clip.segments, isEmpty);
  });

  test('makeAudioClip honours an explicit oneShot fitMode', () {
    final clip = makeAudioClip(
      assetId: 'a1',
      durationMs: 4000,
      fitMode: AudioFitMode.oneShot,
    );
    expect(clip.fitMode, AudioFitMode.oneShot);
  });

  group('recordedClipSpanBars', () {
    test('5s take at 120 BPM 4/4 (1 bar = 2000ms) → 3 bars', () {
      expect(
        recordedClipSpanBars(durationMs: 5000, msPerBar: 2000, maxBars: 8),
        3,
      );
    });
    test('clamps to the room left in the section (maxBars)', () {
      expect(
        recordedClipSpanBars(durationMs: 60000, msPerBar: 2000, maxBars: 4),
        4,
      );
    });
    test('floors at 1 bar for a tiny take', () {
      expect(
        recordedClipSpanBars(durationMs: 100, msPerBar: 2000, maxBars: 8),
        1,
      );
    });
    test('non-positive msPerBar falls back to maxBars', () {
      expect(
        recordedClipSpanBars(durationMs: 5000, msPerBar: 0, maxBars: 6),
        6,
      );
    });
  });

  test('makeAudioBlock carries the clip id and placement', () {
    final block = makeAudioBlock(audioClipId: 'c1', startBar: 1, spanBars: 2);
    expect(block.id, isNotEmpty);
    expect(block.audioClipId, 'c1');
    expect(block.startBar, 1);
    expect(block.spanBars, 2);
  });

  group('audioBlockDefaultSpan', () {
    test('4-bar section at startBar 0 → span 4 (fills to section end)', () {
      expect(audioBlockDefaultSpan(sectionLengthBars: 4, startBar: 0), 4);
    });

    test('4-bar section at startBar 2 → span 2', () {
      expect(audioBlockDefaultSpan(sectionLengthBars: 4, startBar: 2), 2);
    });

    test('4-bar section at startBar 3 → span 1', () {
      expect(audioBlockDefaultSpan(sectionLengthBars: 4, startBar: 3), 1);
    });

    test('1-bar section at startBar 0 → span 1', () {
      expect(audioBlockDefaultSpan(sectionLengthBars: 1, startBar: 0), 1);
    });
  });
}
