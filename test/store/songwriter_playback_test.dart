import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playback fires a metronome accent on each bar downbeat', () async {
    final accents = <bool>[];
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider.overrideWithValue(
        ({required bool accent}) async => accents.add(accent),
      ),
    ]);
    addTearDown(container.dispose);

    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 1);
    sw.addSection(label: 'B', lengthBars: 1);

    final transport = container.read(songwriterPlaybackProvider.notifier);
    await transport.startPlayback(tickDurationOverride: Duration.zero);

    expect(accents.length, greaterThanOrEqualTo(2));
    expect(accents.where((a) => a).length, 2);
    expect(container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.completed);
  });

  test('stopPlayback halts the clock', () async {
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider
          .overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 4);
    final transport = container.read(songwriterPlaybackProvider.notifier);
    transport.stopPlayback();
    expect(container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.idle);
  });

  test('startPlayback fires chord and drum sinks from flattened events',
      () async {
    final chordCalls = <List<int>>[];
    final drumCalls = <List<DrumLaneId>>[];

    final container = ProviderContainer(overrides: [
      songwriterNoteSinkProvider.overrideWithValue(
        (notes) => chordCalls.add(notes),
      ),
      drumPatternPlaybackSinkProvider.overrideWithValue(
        (lanes, volume) async => drumCalls.add(lanes),
      ),
      songwriterMetronomeSinkProvider
          .overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(container.dispose);

    container.read(songwriterProvider.notifier).loadProject(
          const SongwriterProjectSnapshot(
            config:
                SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
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
                    blocks: [
                      SongBlock(
                        id: 'b1',
                        startBar: 0,
                        spanBars: 1,
                        chordNotes: ['C', 'E', 'G'],
                      ),
                    ],
                  ),
                  SongLane(
                    id: 'l2',
                    kind: SongLaneKind.drum,
                    order: 1,
                    blocks: [
                      SongBlock(
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
              DrumPattern(
                id: 'p1',
                name: 'beat',
                lengthTicks: 16,
                lanes: [
                  DrumLaneSequence(
                    laneId: DrumLaneId.kick,
                    activeTicks: [0, 8],
                  ),
                ],
              ),
            ],
          ),
        );

    await container
        .read(songwriterPlaybackProvider.notifier)
        .startPlayback(tickDurationOverride: Duration.zero);

    expect(chordCalls, [
      [60, 64, 67],
    ]);
    expect(drumCalls, [
      [DrumLaneId.kick],
      [DrumLaneId.kick],
    ]);
  });

  test('activePositionForBar maps a global bar to a section instance', () {
    final pos = activePositionForBar(
      [const SongSection(id: 's1', lengthBars: 2, order: 0, repeat: 2)],
      3,
    );
    expect(pos, isNotNull);
    expect(pos!.sectionId, 's1');
    expect(pos.instanceIndex, 1);
    expect(pos.localBar, 1);
  });
}
