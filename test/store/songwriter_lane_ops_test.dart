import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart'
    show saveAnchorLane;
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
    'deleting Harmony removes its Save lanes and preserves stale strum anchor',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(songwriterProvider.notifier);
      n.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = c.read(songwriterProvider).sections.single.id;
      final secondaryHarmonyId = n.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
        harmonyInstrument: HarmonyLaneInstrument.piano,
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
      expect(saveAnchorLane(section, strum), isNull);

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
