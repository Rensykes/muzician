import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';

void main() {
  const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);

  SongBlock chord(String id) => SongBlock(
    id: id,
    startBar: 0,
    spanBars: 1,
    chordNotes: const ['C', 'E', 'G'],
  );

  test('two harmony lanes with distinct pans produce two note groups', () {
    final project = SongwriterProjectSnapshot(
      config: cfg,
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.harmony,
              order: 0,
              pan: -0.5,
              blocks: [chord('b1')],
            ),
            SongLane(
              id: 'l2',
              kind: SongLaneKind.harmony,
              order: 1,
              pan: 0.5,
              volume: 0.7,
              blocks: [chord('b2')],
            ),
          ],
        ),
      ],
    );
    final events = flattenPlaybackEvents(project, const []);
    expect(events, hasLength(1));
    final groups = events.single.noteGroups;
    expect(groups, hasLength(2));
    final byPan = {for (final g in groups) g.pan: g};
    expect(byPan[-0.5]!.volume, 1.0);
    expect(byPan[-0.5]!.midiNotes, [60, 64, 67]);
    expect(byPan[0.5]!.volume, 0.7);
    expect(byPan[0.5]!.midiNotes, [60, 64, 67]);
  });

  test('lanes with identical volume and pan merge into one group', () {
    final project = SongwriterProjectSnapshot(
      config: cfg,
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.harmony,
              order: 0,
              blocks: [chord('b1')],
            ),
            SongLane(
              id: 'l2',
              kind: SongLaneKind.harmony,
              order: 1,
              blocks: [chord('b2')],
            ),
          ],
        ),
      ],
    );
    final events = flattenPlaybackEvents(project, const []);
    expect(events.single.noteGroups, hasLength(1));
    expect(events.single.noteGroups.single.midiNotes, [
      60, 64, 67, 60, 64, 67, //
    ]);
  });

  test('muted lanes emit nothing', () {
    final project = SongwriterProjectSnapshot(
      config: cfg,
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.harmony,
              order: 0,
              muted: true,
              blocks: [chord('b1')],
            ),
            SongLane(
              id: 'l2',
              kind: SongLaneKind.drum,
              order: 1,
              muted: true,
              blocks: [
                const SongBlock(
                  id: 'b2',
                  startBar: 0,
                  spanBars: 1,
                  patternId: 'p1',
                ),
              ],
            ),
          ],
        ),
      ],
      drumPatterns: [
        const DrumPattern(
          id: 'p1',
          name: 'beat',
          lengthTicks: 16,
          lanes: [
            DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
          ],
        ),
      ],
    );
    expect(flattenPlaybackEvents(project, const []), isEmpty);
  });

  test('drum lane volume and pan reach the drum group', () {
    final project = SongwriterProjectSnapshot(
      config: cfg,
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.drum,
              order: 0,
              volume: 0.5,
              pan: 0.3,
              blocks: [
                const SongBlock(
                  id: 'b1',
                  startBar: 0,
                  spanBars: 1,
                  patternId: 'p1',
                ),
              ],
            ),
          ],
        ),
      ],
      drumPatterns: [
        const DrumPattern(
          id: 'p1',
          name: 'beat',
          lengthTicks: 16,
          lanes: [
            DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
          ],
        ),
      ],
    );
    final events = flattenPlaybackEvents(project, const []);
    final g = events.single.drumGroups.single;
    expect(g.volume, 0.5);
    expect(g.pan, 0.3);
    expect(g.drumLanes, [DrumLaneId.kick]);
  });

  group('save lanes follow the primary harmony lane mix', () {
    SongwriterProjectSnapshot project({
      required List<SongLane> lanes,
    }) => SongwriterProjectSnapshot(
      config: cfg,
      sections: [
        SongSection(id: 's1', lengthBars: 1, order: 0, lanes: lanes),
      ],
    );

    // A save block resolvable without the save system: embedded piano snapshot.
    SongLane saveLane({
      double volume = 1.0,
      double pan = 0.0,
      bool muted = false,
      String? anchorLaneId,
    }) =>
        SongLane(
          id: 'lsave',
          kind: SongLaneKind.save,
          order: 2,
          volume: volume,
          pan: pan,
          muted: muted,
          anchorLaneId: anchorLaneId,
          blocks: [
            SongBlock(
              id: 'bs',
              startBar: 0,
              spanBars: 1,
              embedded: PianoSnapshot(
                currentRange: PianoRangeName.key61,
                selectedKeys: const [
                  PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C'),
                ],
                selectedNotes: const ['C'],
                viewMode: PianoViewMode.exact,
              ),
            ),
          ],
        );

    test('save group uses the harmony lane volume/pan, not its own', () {
      final events = flattenPlaybackEvents(
        project(
          lanes: [
            SongLane(
              id: 'lh',
              kind: SongLaneKind.harmony,
              order: 0,
              volume: 0.3,
              pan: -0.6,
              blocks: [chord('b1')],
            ),
            saveLane(volume: 0.9, pan: 0.9),
          ],
        ),
        const [],
      );
      // Same mix bucket → one merged group at the harmony lane's settings.
      final g = events.single.noteGroups.single;
      expect(g.volume, 0.3);
      expect(g.pan, -0.6);
    });

    test('muted harmony lane silences its save blocks too', () {
      final events = flattenPlaybackEvents(
        project(
          lanes: [
            SongLane(
              id: 'lh',
              kind: SongLaneKind.harmony,
              order: 0,
              muted: true,
              blocks: [chord('b1')],
            ),
            saveLane(),
          ],
        ),
        const [],
      );
      expect(events, isEmpty);
    });

    test('anchored save lane follows its anchor, not the primary lane', () {
      final events = flattenPlaybackEvents(
        project(
          lanes: [
            const SongLane(
              id: 'lh1',
              kind: SongLaneKind.harmony,
              order: 0,
              volume: 0.3,
            ),
            const SongLane(
              id: 'lh2',
              kind: SongLaneKind.harmony,
              order: 1,
              volume: 0.9,
              pan: 0.5,
            ),
            saveLane(anchorLaneId: 'lh2'),
          ],
        ),
        const [],
      );
      final g = events.single.noteGroups.single;
      expect(g.volume, 0.9);
      expect(g.pan, 0.5);
    });

    test('save lane with a dangling anchor falls back to the primary lane', () {
      final events = flattenPlaybackEvents(
        project(
          lanes: [
            const SongLane(
              id: 'lh1',
              kind: SongLaneKind.harmony,
              order: 0,
              volume: 0.3,
            ),
            saveLane(anchorLaneId: 'gone'),
          ],
        ),
        const [],
      );
      expect(events.single.noteGroups.single.volume, 0.3);
    });

    test('without a harmony lane the save lane keeps its own mix', () {
      final events = flattenPlaybackEvents(
        project(lanes: [saveLane(volume: 0.7, pan: 0.5)]),
        const [],
      );
      final g = events.single.noteGroups.single;
      expect(g.volume, 0.7);
      expect(g.pan, 0.5);
    });
  });

  test('sectionHarmonyLoop and sectionAuditionBed skip muted lanes', () {
    final section = SongSection(
      id: 's1',
      lengthBars: 1,
      order: 0,
      lanes: [
        SongLane(
          id: 'l1',
          kind: SongLaneKind.harmony,
          order: 0,
          muted: true,
          blocks: [chord('b1')],
        ),
        SongLane(
          id: 'l2',
          kind: SongLaneKind.drum,
          order: 1,
          muted: true,
          blocks: [
            const SongBlock(id: 'b2', startBar: 0, spanBars: 1, patternId: 'p1'),
          ],
        ),
      ],
    );
    const pattern = DrumPattern(
      id: 'p1',
      name: 'beat',
      lengthTicks: 16,
      lanes: [
        DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
      ],
    );
    expect(sectionHarmonyLoop(section, cfg, const []).notesByTick, isEmpty);
    final bed = sectionAuditionBed(
      section,
      cfg,
      const [],
      drumPatterns: const [pattern],
    );
    expect(bed.notesByTick, isEmpty);
    expect(bed.drumByTick, isEmpty);
  });
}
