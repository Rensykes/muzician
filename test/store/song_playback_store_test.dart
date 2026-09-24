import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_playback.dart';
import 'package:muzician/models/piano_roll.dart' show TimeSignature;
import 'package:muzician/schema/rules/song_rules.dart' as song_rules;
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/models/song_project.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container({SongAudioClipSink? audioSink}) {
  final container = ProviderContainer(
    overrides: [
      songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
      songSequencedNotePlaybackSinkProvider.overrideWithValue(
        ({
          required int midiNote,
          required Duration duration,
          required Duration onsetDelay,
          required double volume,
        }) {},
      ),
      songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      if (audioSink != null)
        songAudioClipSinkProvider.overrideWithValue(audioSink),
    ],
  );
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('initial state is idle', () {
    final container = _container();
    addTearDown(container.dispose);
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('stopPlayback resets state to idle', () {
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    notifier.stopPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('startPlayback with no clips completes quickly', () async {
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    await notifier.startPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.completed,
    );
  });

  test(
    'Song live sink applies the serialized boundary duration trim',
    () async {
      final audioRoot = await Directory.systemTemp.createTemp(
        'song-live-boundary-',
      );
      addTearDown(() => audioRoot.delete(recursive: true));
      final calls = <({Duration duration, Duration onset})>[];
      final container = ProviderContainer(
        overrides: [
          songAudioRepositoryProvider.overrideWithValue(
            SongAudioRepository.testWith(rootDirectory: audioRoot),
          ),
          songNotePlaybackSinkProvider.overrideWith(
            (_) => (notes, volume) async {},
          ),
          songSequencedNotePlaybackSinkProvider.overrideWithValue(({
            required int midiNote,
            required Duration duration,
            required Duration onsetDelay,
            required double volume,
          }) {
            calls.add((duration: duration, onset: onsetDelay));
          }),
          songSequencedNoteStopSinkProvider.overrideWithValue(() {}),
          songDrumPlaybackSinkProvider.overrideWith(
            (_) => (lanes, volume) async {},
          ),
          songMetronomeSinkProvider.overrideWith(
            (_) => ({required bool accent}) async {},
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(songProjectProvider.notifier)
          .loadProject(
            const SongProject(
              config: SongProjectConfig(
                tempo: 120,
                timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
                totalMeasures: 1,
              ),
              tracks: [
                SongTrack(
                  id: 't1',
                  name: 'Lead',
                  type: SongTrackType.note,
                  order: 0,
                ),
              ],
              clips: [
                SongClipInstance(
                  id: 'c1',
                  trackId: 't1',
                  patternId: 'p1',
                  patternType: SongPatternType.note,
                  startTick: 0,
                ),
              ],
              notePatterns: [
                NotePattern(
                  id: 'p1',
                  name: 'Lead',
                  lengthTicks: 16,
                  notes: [
                    NotePatternNote(
                      id: 'last-note',
                      midiNote: 72,
                      startTick: 15,
                      durationTicks: 1,
                      onsetOffsetMs: 24,
                      durationOffsetMs: -24,
                    ),
                  ],
                  pitchRangeStart: 48,
                  pitchRangeEnd: 84,
                  snapTicks: 1,
                  highlightedNotes: [],
                ),
              ],
              drumPatterns: [],
            ),
          );

      await container
          .read(songPlaybackProvider.notifier)
          .startPlayback(
            tickDurationOverride: const Duration(milliseconds: 125),
          );

      expect(calls, hasLength(1));
      expect(calls.single.onset, const Duration(milliseconds: 24));
      expect(calls.single.duration, const Duration(milliseconds: 101));
      expect(
        calls.single.onset + calls.single.duration,
        const Duration(milliseconds: 125),
      );
    },
  );

  group('seek', () {
    test('parks the cursor at the given tick while idle', () {
      final container = _container();
      addTearDown(container.dispose);
      // Ensure the project is long enough that tick 8 is in range.
      container.read(songProjectProvider.notifier).setTotalMeasures(4);
      container.read(songPlaybackProvider.notifier).seek(8);
      final state = container.read(songPlaybackProvider);
      expect(state.status, SongPlaybackStatus.idle);
      expect(state.currentTick, 8);
    });

    test('clamps negative ticks to zero', () {
      final container = _container();
      addTearDown(container.dispose);
      container.read(songPlaybackProvider.notifier).seek(-5);
      expect(container.read(songPlaybackProvider).currentTick, 0);
    });

    test('clamps beyond the end of the project', () {
      final container = _container();
      addTearDown(container.dispose);
      final config = container.read(songProjectProvider).config;
      final maxTick = song_rules.songTotalTicks(config) - 1;
      container.read(songPlaybackProvider.notifier).seek(999999);
      expect(container.read(songPlaybackProvider).currentTick, maxTick);
    });
  });

  test('schedules audio clip starts/stops as the transport ticks', () async {
    final sink = _RecordingAudioSink();
    final container = _container(audioSink: sink);
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    project.setTempo(240); // 240 BPM keeps the loop fast
    final trackId = project.addTrack(SongTrackType.audio);
    project.addAudioClip(
      trackId: trackId,
      startTick: 0,
      asset: const AudioAsset(
        id: 'a-fast',
        durationMs: 60,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      ),
    );

    await container.read(songPlaybackProvider.notifier).startPlayback();

    expect(sink.startCalls, isNotEmpty);
    expect(sink.stopCalls, isNotEmpty);
    expect(sink.startCalls.first.assetId, 'a-fast');
  });

  test('note sink receives per-track volume', () async {
    final noteCalls = <({List<int> notes, double volume})>[];
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith(
          (_) =>
              (notes, vol) async => noteCalls.add((notes: notes, volume: vol)),
        ),
        songSequencedNotePlaybackSinkProvider.overrideWithValue(
          ({
            required int midiNote,
            required Duration duration,
            required Duration onsetDelay,
            required double volume,
          }) => noteCalls.add((notes: [midiNote], volume: volume * 0.8)),
        ),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
        songMetronomeSinkProvider.overrideWith(
          (_) => ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    project.setTotalMeasures(1);
    final trackId = project.addTrack(SongTrackType.note);
    project.setTrackVolume(trackId, 0.5);
    final clipId = project.createEmptyNotePatternClip(
      trackId: trackId,
      startTick: 0,
    );
    final pattern = container.read(songProjectProvider).notePatterns.single;
    project.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(
            id: 'n1',
            midiNote: 60,
            startTick: 0,
            durationTicks: 4,
          ),
        ],
      ),
    );
    expect(clipId, isNotEmpty);

    await container
        .read(songPlaybackProvider.notifier)
        .startPlayback(tickDurationOverride: Duration.zero);

    expect(noteCalls, isNotEmpty);
    expect(noteCalls.first.notes, [60]);
    expect(noteCalls.first.volume, closeTo(0.4, 1e-9)); // 0.8 * 0.5
  });

  test(
    'Song sequenced sink receives duration and stagger with 6/8 timing',
    () async {
      final audioRoot = await Directory.systemTemp.createTemp(
        'song-playback-timing-',
      );
      addTearDown(() => audioRoot.delete(recursive: true));
      final calls = <({int midi, Duration duration, Duration onset})>[];
      var stopCalls = 0;
      final container = ProviderContainer(
        overrides: [
          songAudioRepositoryProvider.overrideWithValue(
            SongAudioRepository.testWith(rootDirectory: audioRoot),
          ),
          songSequencedNotePlaybackSinkProvider.overrideWithValue(({
            required int midiNote,
            required Duration duration,
            required Duration onsetDelay,
            required double volume,
          }) {
            calls.add((midi: midiNote, duration: duration, onset: onsetDelay));
          }),
          songSequencedNoteStopSinkProvider.overrideWithValue(() {
            stopCalls++;
          }),
          songNotePlaybackSinkProvider.overrideWith(
            (_) => (notes, vol) async {},
          ),
          songDrumPlaybackSinkProvider.overrideWith(
            (_) => (lanes, vol) async {},
          ),
          songMetronomeSinkProvider.overrideWith(
            (_) => ({required bool accent}) async {},
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(songProjectProvider.notifier)
          .loadProject(
            const SongProject(
              config: SongProjectConfig(
                tempo: 120,
                timeSignature: TimeSignature(beatsPerMeasure: 6, beatUnit: 8),
                totalMeasures: 1,
              ),
              tracks: [
                SongTrack(
                  id: 'lead',
                  name: 'Lead',
                  type: SongTrackType.note,
                  order: 0,
                ),
              ],
              clips: [
                SongClipInstance(
                  id: 'c1',
                  trackId: 'lead',
                  patternId: 'p1',
                  patternType: SongPatternType.note,
                  startTick: 0,
                ),
              ],
              notePatterns: [
                NotePattern(
                  id: 'p1',
                  name: 'Lead',
                  lengthTicks: 12,
                  notes: [
                    NotePatternNote(
                      id: 'n1',
                      midiNote: 67,
                      startTick: 0,
                      durationTicks: 2,
                      onsetOffsetMs: 12,
                    ),
                  ],
                  pitchRangeStart: 48,
                  pitchRangeEnd: 84,
                  snapTicks: 1,
                  highlightedNotes: [],
                ),
              ],
              drumPatterns: [],
              audioAssets: [],
              audioPatterns: [],
              markers: [],
            ),
          );

      await container
          .read(songPlaybackProvider.notifier)
          .startPlayback(endTickExclusive: 1);

      expect(calls, hasLength(1));
      expect(calls.single.midi, 67);
      expect(calls.single.duration, const Duration(milliseconds: 250));
      expect(calls.single.onset, const Duration(milliseconds: 12));
      container.read(songPlaybackProvider.notifier).stopPlayback();
      expect(
        stopCalls,
        2,
      ); // transport start clears old voices; stop releases this run
    },
  );

  test('Song 4/4 sequenced duration uses quarter-note BPM timing', () async {
    final calls = <({Duration duration, Duration onset})>[];
    var stopCalls = 0;
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songSequencedNotePlaybackSinkProvider.overrideWithValue(({
          required int midiNote,
          required Duration duration,
          required Duration onsetDelay,
          required double volume,
        }) {
          calls.add((duration: duration, onset: onsetDelay));
        }),
        songSequencedNoteStopSinkProvider.overrideWithValue(() {
          stopCalls++;
        }),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
        songMetronomeSinkProvider.overrideWith(
          (_) => ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    project.setTempo(120);
    project.setTotalMeasures(1);
    final trackId = project.addTrack(SongTrackType.note);
    project.createEmptyNotePatternClip(trackId: trackId, startTick: 0);
    final pattern = container.read(songProjectProvider).notePatterns.single;
    project.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(
            id: 'four-four-note',
            midiNote: 67,
            startTick: 0,
            durationTicks: 3,
            onsetOffsetMs: 7,
          ),
        ],
      ),
    );

    await container
        .read(songPlaybackProvider.notifier)
        .startPlayback(endTickExclusive: 1);

    expect(calls, [
      (
        duration: const Duration(milliseconds: 375),
        onset: const Duration(milliseconds: 7),
      ),
    ]);
    container.read(songPlaybackProvider.notifier).stopPlayback();
    expect(stopCalls, 2);
  });

  test('loop region wraps the tick clock and re-fires events', () async {
    final fires = <int>[];
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith(
          (_) =>
              (notes, vol) async => fires.add(notes.first),
        ),
        songSequencedNotePlaybackSinkProvider.overrideWithValue(({
          required int midiNote,
          required Duration duration,
          required Duration onsetDelay,
          required double volume,
        }) async {
          fires.add(midiNote);
        }),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
        songMetronomeSinkProvider.overrideWith(
          (_) => ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    project.setTotalMeasures(1);
    final trackId = project.addTrack(SongTrackType.note);
    project.createEmptyNotePatternClip(trackId: trackId, startTick: 0);
    final pattern = container.read(songProjectProvider).notePatterns.single;
    project.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(
            id: 'n1',
            midiNote: 60,
            startTick: 0,
            durationTicks: 4,
          ),
        ],
      ),
    );

    final playback = container.read(songPlaybackProvider.notifier);
    playback.setLoopRegion(0, 4);

    // Stop after the event fired three times (i.e. two wraps happened).
    final run = playback.startPlayback(
      tickDurationOverride: const Duration(milliseconds: 1),
    );
    while (fires.length < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    playback.stopPlayback();
    await run;

    expect(
      fires.length,
      greaterThanOrEqualTo(3),
      reason: 'event at tick 0 re-fires on each loop pass',
    );
  });

  test('count-in fires beatsPerMeasure clicks before the first tick', () async {
    final clicks = <bool>[];
    final fires = <int>[];
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith(
          (_) =>
              (notes, vol) async => fires.add(notes.first),
        ),
        songSequencedNotePlaybackSinkProvider.overrideWithValue(({
          required int midiNote,
          required Duration duration,
          required Duration onsetDelay,
          required double volume,
        }) async {
          fires.add(midiNote);
        }),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
        songMetronomeSinkProvider.overrideWith(
          (_) =>
              ({required bool accent}) async => clicks.add(accent),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Metronome must be on for the count-in to sound.
    container.read(settingsProvider.notifier).setMetronomeEnabled(true);

    final project = container.read(songProjectProvider.notifier);
    project.setTotalMeasures(1);
    final trackId = project.addTrack(SongTrackType.note);
    project.createEmptyNotePatternClip(trackId: trackId, startTick: 0);
    final pattern = container.read(songProjectProvider).notePatterns.single;
    project.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(
            id: 'n1',
            midiNote: 60,
            startTick: 0,
            durationTicks: 4,
          ),
        ],
      ),
    );

    final playback = container.read(songPlaybackProvider.notifier);
    playback.toggleCountIn();
    expect(container.read(songPlaybackProvider).countInEnabled, isTrue);

    await playback.startPlayback(tickDurationOverride: Duration.zero);

    // 4/4 default: 4 count-in clicks (first accented) before the note fired,
    // then per-beat clicks during the measure.
    expect(clicks.length, greaterThanOrEqualTo(4));
    expect(clicks.first, isTrue);
    expect(fires, isNotEmpty);
  });

  test('cycleTempoMultiplier cycles 1.0 → 0.75 → 0.5 → 1.0', () {
    final container = _container();
    addTearDown(container.dispose);
    final playback = container.read(songPlaybackProvider.notifier);
    expect(container.read(songPlaybackProvider).tempoMultiplier, 1.0);
    playback.cycleTempoMultiplier();
    expect(container.read(songPlaybackProvider).tempoMultiplier, 0.75);
    playback.cycleTempoMultiplier();
    expect(container.read(songPlaybackProvider).tempoMultiplier, 0.5);
    playback.cycleTempoMultiplier();
    expect(container.read(songPlaybackProvider).tempoMultiplier, 1.0);
  });

  test('setLoopRegion ignores empty ranges; clearLoopRegion resets', () {
    final container = _container();
    addTearDown(container.dispose);
    final playback = container.read(songPlaybackProvider.notifier);
    playback.setLoopRegion(8, 8);
    expect(container.read(songPlaybackProvider).hasLoop, isFalse);
    playback.setLoopRegion(8, 16);
    expect(container.read(songPlaybackProvider).hasLoop, isTrue);
    playback.clearLoopRegion();
    expect(container.read(songPlaybackProvider).hasLoop, isFalse);
  });

  test('tick clock is wall-anchored: per-beat body cost does not accumulate '
      'as drift', () async {
    // A heavy synchronous cost on every metronome beat. Without wall-clock
    // anchoring the loop adds this on top of every tick's delay, so reaching
    // the final beat takes far longer than the ideal span. Anchored, it is
    // absorbed into the per-tick budget.
    final lastBeat = Completer<void>();
    var beats = 0;
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
        songMetronomeSinkProvider.overrideWith(
          (_) => ({required bool accent}) async {
            beats++;
            if (beats >= 8) {
              if (!lastBeat.isCompleted) lastBeat.complete();
              return; // Exclude the final beat's cost from the measurement.
            }
            final spin = Stopwatch()..start();
            while (spin.elapsedMilliseconds < 12) {
              // Busy-wait simulating per-beat UI/audio work on the loop.
            }
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(settingsProvider.notifier).setMetronomeEnabled(true);
    container.read(songProjectProvider.notifier).setTotalMeasures(2);

    final playback = container.read(songPlaybackProvider.notifier);
    final clock = Stopwatch()..start();
    // 2 bars 4/4 → 8 beats at ticks 0,4,…,28; override 4ms/tick puts the
    // 8th beat at 112ms ideal. Seven intervening beats inject 7 × 12 = 84ms
    // of cost; anchored that fits within the 112ms span. Unanchored total ≈
    // 112 + 84 = 196ms.
    unawaited(
      playback.startPlayback(
        tickDurationOverride: const Duration(milliseconds: 4),
      ),
    );
    await lastBeat.future;
    final elapsedMs = clock.elapsedMilliseconds;
    playback.stopPlayback();

    expect(
      elapsedMs,
      lessThan(150),
      reason: 'drift not absorbed; reached final beat in ${elapsedMs}ms',
    );
  });
}

class _AudioCall {
  final String assetId;
  const _AudioCall(this.assetId);
}

class _RecordingAudioSink implements SongAudioClipSink {
  final List<_AudioCall> startCalls = [];
  final List<_AudioCall> stopCalls = [];
  final List<String> preparedAssetIds = [];

  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {
    preparedAssetIds.addAll(assets.map((a) => a.id));
  }

  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    double balance = 0.0,
    bool loop = false,
  }) async {
    startCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    stopCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopAll() async {}
}
