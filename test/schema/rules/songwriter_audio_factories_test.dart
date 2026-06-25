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
}
