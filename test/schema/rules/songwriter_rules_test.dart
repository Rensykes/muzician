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

  group('legacy guitar-strum anchor migration', () {
    SongwriterProjectSnapshot legacy({required List<SongLane> lanes}) =>
        SongwriterProjectSnapshot.fromJson({
          'type': 'songwriter',
          'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
          'sections': [
            {
              'id': 'section',
              'lengthBars': 4,
              'order': 0,
              'lanes': lanes.map((lane) => lane.toJson()).toList(),
            },
          ],
        });

    const primary = SongLane(
      id: 'primary',
      kind: SongLaneKind.harmony,
      order: 0,
    );
    const strum = SongLane(
      id: 'strum',
      kind: SongLaneKind.guitarStrum,
      order: 1,
    );

    test('pins legacy null anchor to a Fretboard primary exactly once', () {
      final old = legacy(lanes: const [primary, strum]);
      final migrated = migrateLegacyStrumAnchors(
        old,
        projectDefault: HarmonyLaneInstrument.fretboard,
      );
      expect(migrated.sections.single.lanes.last.anchorLaneId, 'primary');
      expect(
        migrated.strumAnchorMigrationVersion,
        strumAnchorMigrationCurrentVersion,
      );

      final later = migrated.copyWith(
        sections: [
          migrated.sections.single.copyWith(
            lanes: [
              ...migrated.sections.single.lanes,
              const SongLane(
                id: 'later-guitar',
                kind: SongLaneKind.harmony,
                order: 2,
                harmonyInstrument: HarmonyLaneInstrument.fretboard,
              ),
            ],
          ),
        ],
      );
      expect(
        migrateLegacyStrumAnchors(
          later,
          projectDefault: HarmonyLaneInstrument.fretboard,
        ).sections.single.lanes[1].anchorLaneId,
        'primary',
      );
    });

    test('does not choose a secondary guitar when primary is Piano', () {
      final old = legacy(
        lanes: const [
          SongLane(
            id: 'primary',
            kind: SongLaneKind.harmony,
            order: 0,
            harmonyInstrument: HarmonyLaneInstrument.piano,
          ),
          SongLane(
            id: 'guitar',
            kind: SongLaneKind.harmony,
            order: 1,
            harmonyInstrument: HarmonyLaneInstrument.fretboard,
          ),
          strum,
        ],
      );
      final migrated = migrateLegacyStrumAnchors(
        old,
        projectDefault: HarmonyLaneInstrument.fretboard,
      );
      expect(migrated.sections.single.lanes.last.anchorLaneId, isNull);
    });

    test('marks no-source snapshots so later guitar lanes stay unassigned', () {
      final old = legacy(
        lanes: const [
          SongLane(
            id: 'primary',
            kind: SongLaneKind.harmony,
            order: 0,
            harmonyInstrument: HarmonyLaneInstrument.piano,
          ),
          strum,
        ],
      );
      final migrated = migrateLegacyStrumAnchors(
        old,
        projectDefault: HarmonyLaneInstrument.fretboard,
      );
      final withLaterGuitar = migrated.copyWith(
        sections: [
          migrated.sections.single.copyWith(
            lanes: [
              ...migrated.sections.single.lanes,
              const SongLane(
                id: 'guitar',
                kind: SongLaneKind.harmony,
                order: 2,
                harmonyInstrument: HarmonyLaneInstrument.fretboard,
              ),
            ],
          ),
        ],
      );
      final reopened = SongwriterProjectSnapshot.fromJson(
        withLaterGuitar.toJson(),
      );
      expect(
        migrateLegacyStrumAnchors(
          reopened,
          projectDefault: HarmonyLaneInstrument.fretboard,
        ).sections.single.lanes[1].anchorLaneId,
        isNull,
      );
    });
  });
}
