import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_stretch_rules.dart';

SongwriterProjectSnapshot _p(int tempo) => SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: tempo, beatsPerBar: 4, beatUnit: 4),
      audioClips: const [AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 1000)],
      sections: const [SongSection(id: 's1', lengthBars: 4, order: 0, lanes: [
        SongLane(id: 'l1', kind: SongLaneKind.audio, order: 0, blocks: [
          SongBlock(id: 'b1', startBar: 0, spanBars: 2, audioClipId: 'c1'),
        ]),
      ])],
    );

void main() {
  test('audioClipSpanBars finds the placing block span', () {
    expect(audioClipSpanBars(_p(120), 'c1'), 2);
    expect(audioClipSpanBars(_p(120), 'missing'), isNull);
  });
  test('stretchTargetMs = span bars x bar ms', () {
    expect(stretchTargetMs(_p(120), 'c1'), 4000); // 120bpm 4/4: 2 bars=4000ms
    expect(stretchTargetMs(_p(60), 'c1'), 8000);
  });
}
