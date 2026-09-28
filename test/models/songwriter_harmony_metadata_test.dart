import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  group('SongLane.harmonyInstrument', () {
    test('round-trips without changing the rest of the lane JSON', () {
      const lane = SongLane(
        id: 'piano-harmony',
        kind: SongLaneKind.harmony,
        order: 2,
        label: 'Piano Harmony',
        repeat: 3,
        volume: 0.7,
        pan: -0.2,
        muted: true,
        harmonyInstrument: HarmonyLaneInstrument.piano,
        blocks: [
          SongBlock(
            id: 'chord',
            startBar: 1,
            spanBars: 2,
            chordSymbol: 'C',
            chordNotes: ['C', 'E', 'G'],
          ),
        ],
      );

      final restored = SongLane.fromJson(lane.toJson());
      expect(restored.harmonyInstrument, HarmonyLaneInstrument.piano);
      expect(restored.id, lane.id);
      expect(restored.kind, lane.kind);
      expect(restored.label, lane.label);
      expect(restored.order, lane.order);
      expect(restored.repeat, lane.repeat);
      expect(restored.volume, lane.volume);
      expect(restored.pan, lane.pan);
      expect(restored.muted, lane.muted);
      expect(restored.blocks.single.chordSymbol, 'C');
    });

    test('copyWith updates or clears the nullable identity', () {
      const lane = SongLane(
        id: 'harmony',
        kind: SongLaneKind.harmony,
        order: 0,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );

      expect(
        lane
            .copyWith(harmonyInstrument: HarmonyLaneInstrument.piano)
            .harmonyInstrument,
        HarmonyLaneInstrument.piano,
      );
      expect(
        lane.copyWith(clearHarmonyInstrument: true).harmonyInstrument,
        isNull,
      );
      expect(
        SongLane.fromJson({
          'id': 'legacy',
          'kind': 'save',
          'order': 0,
          'harmonyInstrument': 'unknown',
        }).harmonyInstrument,
        isNull,
      );
    });
  });

  group('SongBlock save identity', () {
    test('serializes the canonical save link without duplicate provenance', () {
      const block = SongBlock(
        id: 'copied-chord',
        startBar: 4,
        spanBars: 1,
        saveId: 'shared-save',
      );

      final json = block.toJson();
      expect(json['saveId'], 'shared-save');
      expect(json, isNot(contains('duplicateGroupId')));
      expect(SongBlock.fromJson(json).saveId, 'shared-save');
    });
  });
}
