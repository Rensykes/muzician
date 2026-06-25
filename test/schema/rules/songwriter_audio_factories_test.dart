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

  test('makeAudioBlock carries the clip id and placement', () {
    final block = makeAudioBlock(audioClipId: 'c1', startBar: 1, spanBars: 2);
    expect(block.id, isNotEmpty);
    expect(block.audioClipId, 'c1');
    expect(block.startBar, 1);
    expect(block.spanBars, 2);
  });

  group('audioBlockDefaultSpan', () {
    test('4-bar section at startBar 0 → span 3', () {
      expect(audioBlockDefaultSpan(sectionLengthBars: 4, startBar: 0), 3);
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
