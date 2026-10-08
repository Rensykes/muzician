import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('set lane repeat and remove lane', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    final l = n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'Guitar');

    n.setLaneRepeat(sectionId: s, laneId: l, repeat: 3);
    expect(
      c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == l)
          .repeat,
      3,
    );

    n.removeLane(sectionId: s, laneId: l);
    expect(
      c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .where((lane) => lane.id == l),
      isEmpty,
    );
  });

  test(
    'deleting a Harmony source removes linked Save lanes and leaves strum unresolved',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final secondaryHarmonyId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      final saveLaneId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.save,
      );
      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: saveLaneId,
        harmonyLaneId: secondaryHarmonyId,
      );
      final strumLaneId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.guitarStrum,
      );
      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: strumLaneId,
        harmonyLaneId: secondaryHarmonyId,
      );

      n.removeLane(sectionId: sectionId, laneId: secondaryHarmonyId);
      var section = c.read(songwriterProvider).sections.single;
      expect(
        section.lanes.any((lane) => lane.id == secondaryHarmonyId),
        isFalse,
      );
      expect(section.lanes.any((lane) => lane.id == saveLaneId), isFalse);
      final strum = section.lanes.singleWhere((lane) => lane.id == strumLaneId);
      expect(strum.anchorLaneId, secondaryHarmonyId);
      expect(
        guitarStrumAnchorLane(
          section,
          strum,
          projectDefault: HarmonyLaneInstrument.fretboard,
        ),
        isNull,
      );

      expect(n.undo(), isTrue);
      section = c.read(songwriterProvider).sections.single;
      expect(
        section.lanes.any((lane) => lane.id == secondaryHarmonyId),
        isTrue,
      );
      expect(section.lanes.any((lane) => lane.id == saveLaneId), isTrue);
      expect(
        section.lanes
            .singleWhere((lane) => lane.id == strumLaneId)
            .anchorLaneId,
        secondaryHarmonyId,
      );
    },
  );

  test(
    'empty Harmony lane instrument change preserves ID and checks dependents',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final editableLaneId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      final strumLaneId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.guitarStrum,
      );
      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: strumLaneId,
        harmonyLaneId: editableLaneId,
      );

      expect(
        n.setHarmonyLaneInstrument(
          sectionId: sectionId,
          laneId: editableLaneId,
          instrument: HarmonyLaneInstrument.piano,
        ),
        isTrue,
      );
      var lane = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((candidate) => candidate.id == editableLaneId);
      expect(lane.id, editableLaneId);
      expect(lane.harmonyInstrument, HarmonyLaneInstrument.piano);
      expect(
        c
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .singleWhere((candidate) => candidate.id == strumLaneId)
            .anchorLaneId,
        editableLaneId,
      );
      final unresolvedSection = c.read(songwriterProvider).sections.single;
      final unresolvedStrum = unresolvedSection.lanes.singleWhere(
        (candidate) => candidate.id == strumLaneId,
      );
      expect(
        guitarStrumAnchorLane(
          unresolvedSection,
          unresolvedStrum,
          projectDefault: HarmonyLaneInstrument.fretboard,
        ),
        isNull,
      );
      final beforeInvalidAssignment = n.historyRevision;
      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: strumLaneId,
        harmonyLaneId: editableLaneId,
      );
      expect(n.historyRevision, beforeInvalidAssignment);

      final blockedByBlockId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      n.addSilentBlock(
        sectionId: sectionId,
        laneId: blockedByBlockId,
        startBar: 0,
        spanBars: 1,
        verseCount: 1,
      );
      expect(
        n.setHarmonyLaneInstrument(
          sectionId: sectionId,
          laneId: blockedByBlockId,
          instrument: HarmonyLaneInstrument.piano,
        ),
        isFalse,
      );

      final blockedBySaveId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.fretboard,
      );
      final dependentSaveId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.save,
      );
      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: dependentSaveId,
        harmonyLaneId: blockedBySaveId,
      );
      expect(
        n.setHarmonyLaneInstrument(
          sectionId: sectionId,
          laneId: blockedBySaveId,
          instrument: HarmonyLaneInstrument.piano,
        ),
        isFalse,
      );
      lane = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((candidate) => candidate.id == blockedBySaveId);
      expect(lane.harmonyInstrument, HarmonyLaneInstrument.fretboard);
    },
  );

  group('Guitar Strum anchor assignment', () {
    test(
      'rejects occupied targets and releases sources after reassignment/delete',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = c.read(songwriterProvider.notifier);
        n.addSection(label: 'Verse', lengthBars: 4);
        final sectionId = c.read(songwriterProvider).sections.single.id;
        final primaryId = c
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .single
            .id;
        n.setHarmonyLaneInstrument(
          sectionId: sectionId,
          laneId: primaryId,
          instrument: HarmonyLaneInstrument.fretboard,
        );
        final secondaryId = n.addLane(
          sectionId: sectionId,
          kind: SongLaneKind.harmony,
          harmonyInstrument: HarmonyLaneInstrument.fretboard,
        );
        final firstStrumId = n.addLane(
          sectionId: sectionId,
          kind: SongLaneKind.guitarStrum,
        );
        final secondStrumId = n.addLane(
          sectionId: sectionId,
          kind: SongLaneKind.guitarStrum,
        );
        n.setLaneAnchorLane(
          sectionId: sectionId,
          laneId: firstStrumId,
          harmonyLaneId: primaryId,
        );
        n.setLaneAnchorLane(
          sectionId: sectionId,
          laneId: secondStrumId,
          harmonyLaneId: secondaryId,
        );

        final beforeRejectedAssignment = n.historyRevision;
        n.setLaneAnchorLane(
          sectionId: sectionId,
          laneId: secondStrumId,
          harmonyLaneId: primaryId,
        );
        var section = c.read(songwriterProvider).sections.single;
        expect(
          section.lanes
              .singleWhere((lane) => lane.id == secondStrumId)
              .anchorLaneId,
          secondaryId,
        );
        expect(n.historyRevision, beforeRejectedAssignment);

        n.setLaneAnchorLane(
          sectionId: sectionId,
          laneId: secondStrumId,
          harmonyLaneId: null,
        );
        n.setLaneAnchorLane(
          sectionId: sectionId,
          laneId: firstStrumId,
          harmonyLaneId: secondaryId,
        );
        n.setLaneAnchorLane(
          sectionId: sectionId,
          laneId: secondStrumId,
          harmonyLaneId: primaryId,
        );
        section = c.read(songwriterProvider).sections.single;
        expect(
          section.lanes
              .singleWhere((lane) => lane.id == firstStrumId)
              .anchorLaneId,
          secondaryId,
        );
        expect(
          section.lanes
              .singleWhere((lane) => lane.id == secondStrumId)
              .anchorLaneId,
          primaryId,
        );

        n.removeLane(sectionId: sectionId, laneId: secondStrumId);
        section = c.read(songwriterProvider).sections.single;
        expect(
          availableGuitarStrumHarmonyLanes(
            section,
            projectDefault: HarmonyLaneInstrument.fretboard,
            excludingLaneId: firstStrumId,
          ).map((lane) => lane.id),
          [primaryId, secondaryId],
        );
      },
    );

    test('allows multiple Unassigned lanes without consuming a source', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final sourceId = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .single
          .id;
      n.setHarmonyLaneInstrument(
        sectionId: sectionId,
        laneId: sourceId,
        instrument: HarmonyLaneInstrument.fretboard,
      );

      expect(n.canAddGuitarStrumLane(sectionId), isTrue);
      final first = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.guitarStrum,
      );
      final second = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.guitarStrum,
      );
      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(n.canAddGuitarStrumLane(sectionId), isTrue);
      expect(
        c
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .where((lane) => lane.kind == SongLaneKind.guitarStrum)
            .every((lane) => lane.anchorLaneId == null),
        isTrue,
      );

      n.setLaneAnchorLane(
        sectionId: sectionId,
        laneId: first,
        harmonyLaneId: sourceId,
      );
      expect(n.canAddGuitarStrumLane(sectionId), isFalse);
      expect(
        n.addLane(sectionId: sectionId, kind: SongLaneKind.guitarStrum),
        isEmpty,
      );
      expect(
        c
            .read(songwriterProvider)
            .sections
            .single
            .lanes
            .where((lane) => lane.kind == SongLaneKind.guitarStrum)
            .length,
        2,
      );
    });

    test('reusing a pattern within one lane does not claim another source', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final section = c.read(songwriterProvider).sections.single;
      n.setHarmonyLaneInstrument(
        sectionId: section.id,
        laneId: section.lanes.single.id,
        instrument: HarmonyLaneInstrument.fretboard,
      );
      final laneId = n.addLane(
        sectionId: section.id,
        kind: SongLaneKind.guitarStrum,
      );
      final patternId = n.addGuitarStrumPattern();
      n.addGuitarStrumBlock(
        sectionId: section.id,
        laneId: laneId,
        patternId: patternId,
        startBar: 0,
        spanBars: 1,
      );
      n.addGuitarStrumBlock(
        sectionId: section.id,
        laneId: laneId,
        patternId: patternId,
        startBar: 1,
        spanBars: 1,
      );

      final lane = c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((candidate) => candidate.id == laneId);
      expect(lane.blocks, hasLength(2));
      expect(lane.blocks.map((block) => block.patternId), [
        patternId,
        patternId,
      ]);
      expect(lane.anchorLaneId, isNull);
    });
  });

  group('renameLane', () {
    test('sets, replaces and clears the label', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'V', lengthBars: 4);
      final s = c.read(songwriterProvider).sections.single.id;
      final l = n.addLane(
        sectionId: s,
        kind: SongLaneKind.harmony,
        label: 'Harmony',
      );
      String? label() => c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == l)
          .label;

      n.renameLane(sectionId: s, laneId: l, label: 'Guitars');
      expect(label(), 'Guitars');

      n.renameLane(sectionId: s, laneId: l, label: null);
      expect(label(), isNull);
    });
  });

  group('lane mix ops', () {
    test('volume and pan set with clamping, mute toggles', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'V', lengthBars: 4);
      final s = c.read(songwriterProvider).sections.single.id;
      final l = n.addLane(
        sectionId: s,
        kind: SongLaneKind.harmony,
        label: 'Harmony',
      );
      SongLane lane() => c
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((lane) => lane.id == l);

      n.setLaneVolume(sectionId: s, laneId: l, volume: 0.5);
      expect(lane().volume, 0.5);
      n.setLaneVolume(sectionId: s, laneId: l, volume: 1.7);
      expect(lane().volume, 1.0);
      n.setLaneVolume(sectionId: s, laneId: l, volume: -0.2);
      expect(lane().volume, 0.0);

      n.setLanePan(sectionId: s, laneId: l, pan: -2.0);
      expect(lane().pan, -1.0);
      n.setLanePan(sectionId: s, laneId: l, pan: 0.4);
      expect(lane().pan, 0.4);

      n.setLaneMuted(sectionId: s, laneId: l, muted: true);
      expect(lane().muted, true);
      n.setLaneMuted(sectionId: s, laneId: l, muted: false);
      expect(lane().muted, false);
    });
  });
}
