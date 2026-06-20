import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_playback.dart';
import 'package:muzician/schema/rules/song_rules.dart' as song_rules;
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/models/song_project.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container({SongAudioClipSink? audioSink}) {
  final container = ProviderContainer(
    overrides: [
      songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
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
          (_) => (notes, vol) async =>
              noteCalls.add((notes: notes, volume: vol)),
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
          NotePatternNote(id: 'n1', midiNote: 60, startTick: 0,
              durationTicks: 4),
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

  test('loop region wraps the tick clock and re-fires events', () async {
    final fires = <int>[];
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith(
          (_) => (notes, vol) async => fires.add(notes.first),
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

    final project = container.read(songProjectProvider.notifier);
    project.setTotalMeasures(1);
    final trackId = project.addTrack(SongTrackType.note);
    project.createEmptyNotePatternClip(trackId: trackId, startTick: 0);
    final pattern = container.read(songProjectProvider).notePatterns.single;
    project.applyNotePattern(
      pattern.id,
      pattern.copyWith(
        notes: const [
          NotePatternNote(id: 'n1', midiNote: 60, startTick: 0,
              durationTicks: 4),
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

    expect(fires.length, greaterThanOrEqualTo(3),
        reason: 'event at tick 0 re-fires on each loop pass');
  });

  test('count-in fires beatsPerMeasure clicks before the first tick',
      () async {
    final clicks = <bool>[];
    final fires = <int>[];
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith(
          (_) => (notes, vol) async => fires.add(notes.first),
        ),
        songDrumPlaybackSinkProvider.overrideWith(
          (_) => (lanes, vol) async {},
        ),
        songMetronomeSinkProvider.overrideWith(
          (_) => ({required bool accent}) async => clicks.add(accent),
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
          NotePatternNote(id: 'n1', midiNote: 60, startTick: 0,
              durationTicks: 4),
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
