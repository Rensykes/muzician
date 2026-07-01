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
    final container = ProviderContainer(
      overrides: [
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async => accents.add(accent),
        ),
      ],
    );
    addTearDown(container.dispose);

    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 1);
    sw.addSection(label: 'B', lengthBars: 1);

    final transport = container.read(songwriterPlaybackProvider.notifier);
    await transport.startPlayback(tickDurationOverride: Duration.zero);

    expect(accents.length, greaterThanOrEqualTo(2));
    expect(accents.where((a) => a).length, 2);
    expect(
      container.read(songwriterPlaybackProvider).status,
      SongwriterPlaybackStatus.completed,
    );
  });

  test('stopPlayback halts the clock', () async {
    final container = ProviderContainer(
      overrides: [
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 4);
    final transport = container.read(songwriterPlaybackProvider.notifier);
    transport.stopPlayback();
    expect(
      container.read(songwriterPlaybackProvider).status,
      SongwriterPlaybackStatus.idle,
    );
  });

  test(
    'startPlayback fires chord and drum sinks from flattened events',
    () async {
      final chordCalls = <List<int>>[];
      final drumCalls = <List<DrumLaneId>>[];

      final container = ProviderContainer(
        overrides: [
          songwriterNoteSinkProvider.overrideWithValue(
            (notes) => chordCalls.add(notes),
          ),
          drumPatternPlaybackSinkProvider.overrideWithValue(
            (lanes, volume) async => drumCalls.add(lanes),
          ),
          songwriterMetronomeSinkProvider.overrideWithValue(
            ({required bool accent}) async {},
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(songwriterProvider.notifier)
          .loadProject(
            const SongwriterProjectSnapshot(
              config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
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
    },
  );

  test(
    'tick clock is wall-anchored: body cost does not accumulate as drift',
    () async {
      // Inject a heavy synchronous cost on every metronome beat. Without
      // wall-clock anchoring the loop would add this on top of every tick's
      // delay, so total playback time would balloon past the ideal span. With
      // anchoring it is absorbed into the per-tick budget.
      final container = ProviderContainer(
        overrides: [
          songwriterMetronomeSinkProvider.overrideWithValue(({
            required bool accent,
          }) async {
            final spin = Stopwatch()..start();
            while (spin.elapsedMilliseconds < 12) {
              // Busy-wait to simulate per-beat UI/audio work on the loop isolate.
            }
          }),
        ],
      );
      addTearDown(container.dispose);

      final sw = container.read(songwriterProvider.notifier);
      sw.addSection(label: 'A', lengthBars: 2); // 2 bars 4/4 → 32 ticks.

      final clock = Stopwatch()..start();
      await container
          .read(songwriterPlaybackProvider.notifier)
          // 32 ticks * 4ms ≈ 124ms ideal span; 8 beats * 12ms = 96ms of injected
          // cost. Anchored, total stays near the ideal span (cost overlaps the
          // waits). Unanchored it would be ~124 + 96 ≈ 220ms+.
          .startPlayback(tickDurationOverride: const Duration(milliseconds: 4));
      final elapsedMs = clock.elapsedMilliseconds;

      expect(
        container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.completed,
      );
      expect(
        elapsedMs,
        lessThan(180),
        reason: 'drift not absorbed; loop ran for ${elapsedMs}ms',
      );
    },
  );

  test('activePositionForBar maps a global bar to a section instance', () {
    final pos = activePositionForBar([
      const SongSection(id: 's1', lengthBars: 2, order: 0, repeat: 2),
    ], 3);
    expect(pos, isNotNull);
    expect(pos!.sectionId, 's1');
    expect(pos.instanceIndex, 1);
    expect(pos.localBar, 1);
  });

  group('sectionBarGlobalTick', () {
    const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;

    test('localBar within a later section maps to its global tick', () {
      final sections = [
        const SongSection(id: 's1', lengthBars: 2, order: 0),
        const SongSection(id: 's2', lengthBars: 4, order: 1),
      ];
      // s2 starts at global bar 2; bar 1 of s2 → global bar 3.
      expect(sectionBarGlobalTick(sections, cfg, 's2', 1), 3 * measureTicks);
      expect(sectionBarGlobalTick(sections, cfg, 's1', 0), 0);
    });

    test('repeated section uses the requested instance', () {
      final sections = [
        const SongSection(id: 's1', lengthBars: 2, order: 0, repeat: 2),
      ];
      // instance 0 starts at bar 0; instance 1 at bar 2.
      expect(sectionBarGlobalTick(sections, cfg, 's1', 1), 1 * measureTicks);
      expect(
        sectionBarGlobalTick(sections, cfg, 's1', 1, instanceIndex: 1),
        3 * measureTicks,
      );
    });

    test('unknown section id → 0', () {
      expect(sectionBarGlobalTick(const [], cfg, 'nope', 3), 0);
    });

    test('localBar is clamped into the section length', () {
      final sections = [const SongSection(id: 's1', lengthBars: 2, order: 0)];
      // bar 5 in a 2-bar section clamps to bar 1.
      expect(sectionBarGlobalTick(sections, cfg, 's1', 5), 1 * measureTicks);
    });
  });

  test('startPlayback(startTick:) skips bars before the start', () async {
    final accents = <bool>[];
    final container = ProviderContainer(
      overrides: [
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async => accents.add(accent),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 1);
    sw.addSection(label: 'B', lengthBars: 1);
    final cfg = container.read(songwriterProvider).config;
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;

    await container
        .read(songwriterPlaybackProvider.notifier)
        .startPlayback(
          startTick: measureTicks,
          tickDurationOverride: Duration.zero,
        );

    // Bar 0's downbeat accent is skipped; only bar 1's fires.
    expect(accents.where((a) => a).length, 1);
    expect(
      container.read(songwriterPlaybackProvider).status,
      SongwriterPlaybackStatus.completed,
    );
  });

  test(
    'startPlayback(startTick:) past the end completes without firing',
    () async {
      final accents = <bool>[];
      final container = ProviderContainer(
        overrides: [
          songwriterMetronomeSinkProvider.overrideWithValue(
            ({required bool accent}) async => accents.add(accent),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'A', lengthBars: 1);

      await container
          .read(songwriterPlaybackProvider.notifier)
          .startPlayback(
            startTick: 100000,
            tickDurationOverride: Duration.zero,
          );

      expect(accents, isEmpty);
      expect(
        container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.completed,
      );
    },
  );

  group('songwriterStartTickProvider', () {
    test('defaults to 0; setTick clamps negatives; reset returns to 0', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(songwriterStartTickProvider), 0);
      c.read(songwriterStartTickProvider.notifier).setTick(48);
      expect(c.read(songwriterStartTickProvider), 48);
      c.read(songwriterStartTickProvider.notifier).setTick(-5);
      expect(c.read(songwriterStartTickProvider), 0);
      c.read(songwriterStartTickProvider.notifier).reset();
      expect(c.read(songwriterStartTickProvider), 0);
    });
  });
}
