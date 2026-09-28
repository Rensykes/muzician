import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  group('saveAnchorLane', () {
    const primary = SongLane(
      id: 'primary',
      kind: SongLaneKind.harmony,
      order: 0,
    );
    const secondary = SongLane(
      id: 'secondary',
      kind: SongLaneKind.harmony,
      order: 1,
    );
    const legacySave = SongLane(
      id: 'legacy-save',
      kind: SongLaneKind.save,
      order: 2,
    );
    const secondarySave = SongLane(
      id: 'secondary-save',
      kind: SongLaneKind.save,
      order: 3,
      anchorLaneId: 'secondary',
    );
    const staleSave = SongLane(
      id: 'stale-save',
      kind: SongLaneKind.save,
      order: 4,
      anchorLaneId: 'deleted-harmony',
    );
    const section = SongSection(
      id: 'section',
      lengthBars: 4,
      order: 0,
      lanes: [primary, secondary, legacySave, secondarySave, staleSave],
    );

    test(
      'null anchor resolves to primary and valid explicit anchor resolves',
      () {
        expect(saveAnchorLane(section, legacySave), same(primary));
        expect(saveAnchorLane(section, secondarySave), same(secondary));
      },
    );

    test(
      'stale explicit anchor remains unresolved and save lane keeps its mix',
      () {
        expect(saveAnchorLane(section, staleSave), isNull);
        expect(mixGoverningLane(section, staleSave), same(staleSave));
      },
    );

    test('legacy save lane has no resolved harmony when section has none', () {
      const sectionWithoutHarmony = SongSection(
        id: 'empty',
        lengthBars: 4,
        order: 0,
        lanes: [legacySave],
      );
      expect(saveAnchorLane(sectionWithoutHarmony, legacySave), isNull);
    });
  });

  group('harmony lane factories', () {
    test(
      'makeSection seeds its primary harmony lane with the selected instrument',
      () {
        final defaultSection = makeSection(
          id: 'stable-section',
          lengthBars: 4,
          order: 0,
        );
        expect(defaultSection.id, 'stable-section');
        expect(defaultSection.lanes, hasLength(1));
        expect(defaultSection.lanes.single.kind, SongLaneKind.harmony);
        expect(
          defaultSection.lanes.single.harmonyInstrument,
          HarmonyLaneInstrument.fretboard,
        );

        final pianoSection = makeSection(
          lengthBars: 4,
          order: 1,
          harmonyInstrument: HarmonyLaneInstrument.piano,
        );
        expect(
          pianoSection.lanes.single.harmonyInstrument,
          HarmonyLaneInstrument.piano,
        );
      },
    );

    test('makeLane injects instrument metadata only for harmony lanes', () {
      final harmony = makeLane(
        kind: SongLaneKind.harmony,
        order: 0,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      final drum = makeLane(
        kind: SongLaneKind.drum,
        order: 1,
        harmonyInstrument: HarmonyLaneInstrument.piano,
      );
      expect(harmony.harmonyInstrument, HarmonyLaneInstrument.piano);
      expect(drum.harmonyInstrument, isNull);
    });
  });
}
