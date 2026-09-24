import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_stretch_rules.dart';

SongwriterProjectSnapshot _p(
  int tempo, {
  int beatsPerBar = 4,
  int beatUnit = 4,
  int sectionBars = 4,
  int blockBars = 2,
}) => SongwriterProjectSnapshot(
  config: SongwriterConfig(
    tempo: tempo,
    beatsPerBar: beatsPerBar,
    beatUnit: beatUnit,
  ),
  audioClips: const [AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 1000)],
  sections: [
    SongSection(
      id: 's1',
      lengthBars: sectionBars,
      order: 0,
      lanes: [
        SongLane(
          id: 'l1',
          kind: SongLaneKind.audio,
          order: 0,
          blocks: [
            SongBlock(
              id: 'b1',
              startBar: 0,
              spanBars: blockBars,
              audioClipId: 'c1',
            ),
          ],
        ),
      ],
    ),
  ],
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
  test('stretch target uses quarter-note BPM for a 6/8 bar', () {
    final project = _p(
      120,
      beatsPerBar: 6,
      beatUnit: 8,
      sectionBars: 1,
      blockBars: 1,
    );
    expect(stretchTargetMs(project, 'c1'), 1500);
  });
}
