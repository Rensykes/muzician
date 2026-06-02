import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('snapshot round-trips through InstrumentSnapshot.fromJson', () {
    const snap = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 4,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.harmony,
              order: 0,
              blocks: [
                SongBlock(
                  id: 'b1',
                  startBar: 0,
                  spanBars: 2,
                  chordSymbol: 'C',
                  chordNotes: ['C', 'E', 'G'],
                  romanNumeral: 'I',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final json = snap.toJson();
    expect(json['type'], 'songwriter');

    final back = InstrumentSnapshot.fromJson(json);
    expect(back, isA<SongwriterProjectSnapshot>());
    final sw = back as SongwriterProjectSnapshot;
    expect(sw.sections.single.lanes.single.blocks.single.romanNumeral, 'I');
    expect(sw.instrument, 'songwriter');
    expect(sw.pendingChord, isNull);
    expect(sw.selectedNotes, containsAll(['C', 'E', 'G']));
  });
}
