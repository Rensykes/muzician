import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/guitar_sound.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/utils/guitar_synth.dart';
import 'package:muzician/utils/note_player.dart';
import 'package:muzician/utils/playback_voice_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xyz.luan/audioplayers.global');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AudioplayersPlatformInterface previous;
  late TargetPlatform? previousTarget;
  late _AudioPlatform platform;
  late NotePlayer player;

  setUp(() async {
    previous = AudioplayersPlatformInterface.instance;
    previousTarget = debugDefaultTargetPlatformOverride;
    platform = _AudioPlatform();
    AudioplayersPlatformInterface.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    player = NotePlayer.forTesting();
    await player.init();
  });

  tearDown(() async {
    player.stopSequencedNotes();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await platform.close();
    AudioplayersPlatformInterface.instance = previous;
    debugDefaultTargetPlatformOverride = previousTarget;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('six-note Harmony binds and starts exactly one native source', () async {
    player.playSequencedChord(
      [40, 47, 52, 55, 59, 64],
      duration: const Duration(milliseconds: 300),
      guitarTone: GuitarTone.distorted,
    );
    await platform.firstResume.future;
    expect(platform.sources, hasLength(1));
    expect(platform.resumes, hasLength(1));
    expect(platform.sources.single.length, 44 + 44100 * 300 ~/ 1000 * 2);
    player.stopSequencedNotes();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(platform.stops, contains(platform.resumes.single));
  });

  test(
    'slow source binding cannot start a voice after its release deadline',
    () async {
      platform.sourceGate = Completer<void>();
      player.playSequencedNote(60, duration: const Duration(milliseconds: 50));
      await platform.firstSource.future;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(platform.stops, isNotEmpty);
      platform.sourceGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(platform.resumes, isEmpty);
    },
  );

  test(
    'stop cancels pending source and restart keeps a separate active owner',
    () async {
      platform.sourceGate = Completer<void>();
      player.playSequencedNote(60, duration: const Duration(seconds: 1));
      await platform.firstSource.future;
      player.stopSequencedNotes();
      player.playSequencedNote(67, duration: const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final oldPlayer = platform.sourcePlayers.first;
      final newPlayer = platform.sourcePlayers.last;
      expect(newPlayer, isNot(oldPlayer));
      platform.sourceGate!.complete();
      await platform.firstResume.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(platform.resumes, [newPlayer]);
      expect(platform.stops, isNot(contains(newPlayer)));
    },
  );
  group('prepareForPlayback', () {
    const noteDuration = Duration(milliseconds: 80);

    Future<NotePlayer> readyPlayer(PlaybackVoiceRenderer? renderer) async {
      final prepared = NotePlayer.forTesting(voiceRenderer: renderer);
      await prepared.init();
      addTearDown(prepared.stopSequencedNotes);
      return prepared;
    }

    test(
      'renders each unique voice once and later plays hit the cache',
      () async {
        final rendered = <List<PlaybackVoiceSpec>>[];
        final marker = Uint8List.fromList([1, 2, 3, 4]);
        final prepared = await readyPlayer((voices) async {
          rendered.add(voices);
          return [for (final _ in voices) marker];
        });
        final voices = [
          PlaybackVoiceSpec.sequencedNote(
            60,
            duration: noteDuration,
            guitarTone: GuitarTone.clean,
          ),
          PlaybackVoiceSpec.sequencedNote(
            60,
            duration: noteDuration,
            guitarTone: GuitarTone.clean,
          ),
          PlaybackVoiceSpec.sequencedNote(62, duration: noteDuration),
        ];

        await prepared.prepareForPlayback(voices);
        await prepared.prepareForPlayback(voices);

        expect(rendered, hasLength(1));
        expect(rendered.single, hasLength(2));

        prepared.playSequencedNote(
          60,
          duration: noteDuration,
          guitarTone: GuitarTone.clean,
        );
        prepared.playSequencedNote(62, duration: noteDuration);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(platform.sources, [marker, marker]);
        expect(rendered, hasLength(1));
      },
    );

    test(
      'prepared keys match click, drum, chord and piano play paths',
      () async {
        final marker = Uint8List.fromList([9, 9]);
        final prepared = await readyPlayer(
          (voices) async => [for (final _ in voices) marker],
        );
        await prepared.prepareForPlayback([
          const PlaybackVoiceSpec.click(accent: true),
          const PlaybackVoiceSpec.drum(DrumLaneId.snare),
          PlaybackVoiceSpec.sequencedChord(
            [64, 60, 67],
            duration: noteDuration,
            guitarTone: GuitarTone.distorted,
          ),
          PlaybackVoiceSpec.sequencedChord([60, 64], duration: noteDuration),
        ]);

        prepared.playClick(accent: true);
        prepared.playDrumLane(DrumLaneId.snare);
        prepared.playSequencedChord(
          [67, 60, 64],
          duration: noteDuration,
          guitarTone: GuitarTone.distorted,
        );
        prepared.playSequencedChord([64, 60], duration: noteDuration);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(platform.sources, hasLength(4));
        expect(
          platform.sources.every((bytes) => identical(bytes, marker)),
          true,
        );
      },
    );

    test('off-isolate rendering equals the synchronous synthesis', () async {
      final prepared = await readyPlayer(null);
      await prepared.prepareForPlayback([
        PlaybackVoiceSpec.sequencedNote(
          52,
          duration: noteDuration,
          guitarTone: GuitarTone.distorted,
        ),
        PlaybackVoiceSpec.sequencedNote(72, duration: noteDuration),
      ]);

      prepared.playSequencedNote(
        52,
        duration: noteDuration,
        guitarTone: GuitarTone.distorted,
      );
      prepared.playSequencedNote(72, duration: noteDuration);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        platform.sources.first,
        GuitarSynth.renderNote(
          52,
          tone: GuitarTone.distorted,
          duration: noteDuration,
        ),
      );
      expect(platform.sources.last.length, 44 + 44100 * 80 ~/ 1000 * 2);
    });

    test(
      'falls back to synchronous rendering when the isolate path fails',
      () async {
        var attempts = 0;
        final prepared = await readyPlayer((voices) async {
          attempts++;
          throw StateError('no isolates');
        });
        await prepared.prepareForPlayback([
          PlaybackVoiceSpec.sequencedNote(
            57,
            duration: noteDuration,
            guitarTone: GuitarTone.clean,
          ),
        ]);
        prepared.playSequencedNote(
          57,
          duration: noteDuration,
          guitarTone: GuitarTone.clean,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(attempts, 1);
        expect(
          platform.sources.single,
          GuitarSynth.renderNote(
            57,
            tone: GuitarTone.clean,
            duration: noteDuration,
          ),
        );
      },
    );

    test('pre-creates a bounded sequenced pool once and reuses it', () async {
      final prepared = await readyPlayer(
        (voices) async => [for (final _ in voices) Uint8List(44)],
      );
      final baseline = platform.created.length;
      await prepared.prepareForPlayback(const [], sequencedPlayers: 4);
      expect(platform.created.length - baseline, 4);
      await prepared.prepareForPlayback(const [], sequencedPlayers: 3);
      expect(platform.created.length - baseline, 4);
      await prepared.prepareForPlayback(const [], sequencedPlayers: 500);
      expect(platform.created.length - baseline, 16);
      expect(platform.releaseModes.length, greaterThanOrEqualTo(16));

      for (var i = 0; i < 3; i++) {
        prepared.playSequencedNote(60 + i, duration: noteDuration);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(platform.created.length - baseline, 16);
    });

    test('writes prepared WAVs once on Apple platforms', () async {
      final dir = Directory('build/note_player_prepare_test')
        ..createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var renders = 0;
      final prepared = NotePlayer.forTesting(
        voiceRenderer: (voices) async {
          renders++;
          return [
            for (final _ in voices) Uint8List.fromList([1, 2, 3]),
          ];
        },
      );
      await prepared.init(tempDirectoryOverride: dir.path);
      final voices = [
        const PlaybackVoiceSpec.click(accent: false),
        const PlaybackVoiceSpec.drum(DrumLaneId.kick),
      ];
      await prepared.prepareForPlayback(voices);
      await prepared.prepareForPlayback(voices);
      expect(renders, 1);
      expect(
        dir.listSync().map((entity) => entity.uri.pathSegments.last).toSet(),
        {'click_2.wav', 'drum_10.wav'},
      );
    });

    test('is a no-op before init', () async {
      var calls = 0;
      final idle = NotePlayer.forTesting(
        voiceRenderer: (voices) async {
          calls++;
          return [for (final _ in voices) Uint8List(44)];
        },
      );
      await idle.prepareForPlayback([
        PlaybackVoiceSpec.sequencedNote(60, duration: noteDuration),
      ], sequencedPlayers: 2);
      expect(calls, 0);
    });

    test('Stop cancels voices that start after a prepared run', () async {
      final prepared = await readyPlayer(
        (voices) async => [for (final _ in voices) Uint8List(44)],
      );
      await prepared.prepareForPlayback([
        PlaybackVoiceSpec.sequencedNote(60, duration: noteDuration),
      ], sequencedPlayers: 1);
      prepared.playSequencedNote(
        60,
        duration: noteDuration,
        onsetDelay: const Duration(milliseconds: 40),
      );
      prepared.stopSequencedNotes();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(platform.sources, isEmpty);
      expect(platform.resumes, isEmpty);
    });
  });
  group('guitar strokes', () {
    const strings = [
      (midi: 40, onsetMs: 0, durationMs: 120),
      (midi: 47, onsetMs: 12, durationMs: 108),
      (midi: 52, onsetMs: 24, durationMs: 96),
      (midi: 55, onsetMs: 36, durationMs: 84),
      (midi: 59, onsetMs: 48, durationMs: 72),
      (midi: 64, onsetMs: 60, durationMs: 60),
    ];

    test('six strings bind and start exactly one native voice', () async {
      player.playSequencedStroke(strings, guitarTone: GuitarTone.clean);
      await platform.firstResume.future;
      expect(platform.sources, hasLength(1));
      expect(platform.resumes, hasLength(1));
      expect(platform.sourcePlayers.toSet(), hasLength(1));
      expect(
        platform.sources.single,
        GuitarSynth.renderStroke(strings, tone: GuitarTone.clean),
      );
      expect(platform.sources.single.length, 44 + 44100 * 120 ~/ 1000 * 2);
    });

    test('the voice releases at the stroke end, not per string', () async {
      player.playSequencedStroke(strings, guitarTone: GuitarTone.clean);
      await platform.firstResume.future;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(platform.stops, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(platform.stops, [platform.resumes.single]);
    });

    test('Stop silences a sounding stroke and cancels a pending one', () async {
      player.playSequencedStroke(strings, guitarTone: GuitarTone.clean);
      await platform.firstResume.future;
      player.stopSequencedNotes();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(platform.stops, contains(platform.resumes.single));

      platform.sourceGate = Completer<void>();
      player.playSequencedStroke(strings, guitarTone: GuitarTone.distorted);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      player.stopSequencedNotes();
      platform.sourceGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(platform.resumes, hasLength(1));
    });

    test('a prepared stroke is a cache hit at play time', () async {
      final rendered = <List<PlaybackVoiceSpec>>[];
      final marker = Uint8List.fromList([5, 6, 7, 8]);
      final prepared = NotePlayer.forTesting(
        voiceRenderer: (voices) async {
          rendered.add(voices);
          return [for (final _ in voices) marker];
        },
      );
      await prepared.init();
      addTearDown(prepared.stopSequencedNotes);
      await prepared.prepareForPlayback([
        PlaybackVoiceSpec.guitarStroke(strings, guitarTone: GuitarTone.clean),
      ], sequencedPlayers: 1);
      expect(rendered.single.single.kind, PlaybackVoiceKind.guitarStroke);

      prepared.playSequencedStroke(strings, guitarTone: GuitarTone.clean);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(platform.sources.single, same(marker));
      expect(rendered, hasLength(1));
    });

    test('off-isolate stroke rendering equals the synchronous synth', () async {
      final prepared = NotePlayer.forTesting();
      await prepared.init();
      addTearDown(prepared.stopSequencedNotes);
      await prepared.prepareForPlayback([
        PlaybackVoiceSpec.guitarStroke(
          strings,
          guitarTone: GuitarTone.distorted,
        ),
      ]);
      prepared.playSequencedStroke(strings, guitarTone: GuitarTone.distorted);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        platform.sources.single,
        GuitarSynth.renderStroke(strings, tone: GuitarTone.distorted),
      );
    });

    test('stroke WAVs are LRU-bounded and recent ones stay cached', () async {
      var rendered = 0;
      final prepared = NotePlayer.forTesting(
        voiceRenderer: (voices) async {
          rendered += voices.length;
          return [for (final _ in voices) Uint8List(44)];
        },
      );
      await prepared.init();
      List<PlaybackVoiceSpec> batch(int from) => [
        for (var i = from; i < from + 200; i++)
          PlaybackVoiceSpec.guitarStroke([
            (midi: 40, onsetMs: 0, durationMs: 50 + i),
          ], guitarTone: GuitarTone.clean),
      ];
      await prepared.prepareForPlayback(batch(0));
      await prepared.prepareForPlayback(batch(200));
      expect(rendered, 400);
      // 400 strokes exceed the 256 bound: the 144 oldest were evicted, the
      // newest batch is still cached.
      await prepared.prepareForPlayback(batch(200));
      expect(rendered, 400);
      await prepared.prepareForPlayback(batch(0));
      expect(rendered, 544);
    });

    test('an empty stroke is ignored', () async {
      player.playSequencedStroke(const [], guitarTone: GuitarTone.clean);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(platform.sources, isEmpty);
    });
  });

  group('preview pool source affinity', () {
    Future<void> hit(DrumLaneId lane, [int waitMs = 300]) async {
      player.playDrumLane(lane);
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }

    test(
      'a lane returns to the player that already holds its sample',
      () async {
        await hit(DrumLaneId.kick);
        await hit(DrumLaneId.snare);
        await hit(DrumLaneId.kick);
        await hit(DrumLaneId.snare);
        final ids = platform.sourcePlayers;
        expect(ids, hasLength(4));
        expect(ids[2], ids[0]);
        expect(ids[3], ids[1]);
        expect(ids[0], isNot(ids[1]));
      },
    );

    test(
      'a retrigger while the sample still rings takes another player',
      () async {
        await hit(DrumLaneId.kick, 10);
        await hit(DrumLaneId.kick, 10);
        expect(platform.sourcePlayers, hasLength(2));
        expect(platform.sourcePlayers[0], isNot(platform.sourcePlayers[1]));
      },
    );

    test('a click and a drum never share a ringing player', () async {
      player.playClick(accent: true);
      player.playDrumLane(DrumLaneId.closedHiHat);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(platform.sourcePlayers.toSet(), hasLength(2));
    });

    test('more simultaneous voices than players still all play', () async {
      for (final lane in DrumLaneId.values) {
        player.playDrumLane(lane);
      }
      player.playClick();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(platform.sources, hasLength(DrumLaneId.values.length + 1));
    });
  });

  test('one-shot voices never poll the playback position', () async {
    await player.prepareForPlayback(const [], sequencedPlayers: 1);
    player.playSequencedNote(60, duration: const Duration(milliseconds: 40));
    player.playSequencedStroke(const [
      (midi: 40, onsetMs: 0, durationMs: 40),
    ], guitarTone: GuitarTone.clean);
    player.playDrumLane(DrumLaneId.kick);
    player.playClick();
    player.previewNote(64);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(platform.resumes, hasLength(5));
    expect(platform.positionQueries, isEmpty);
  });

  group('sequenced player pool', () {
    test(
      'unchanged volume and balance are not re-sent to a reused player',
      () async {
        player.playSequencedNote(
          60,
          duration: const Duration(milliseconds: 40),
          volume: 0.5,
          pan: 0.25,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        player.playSequencedNote(
          62,
          duration: const Duration(milliseconds: 40),
          volume: 0.5,
          pan: 0.25,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(platform.sourcePlayers.toSet(), hasLength(1));
        expect(platform.volumes, hasLength(1));
        expect(platform.balances, hasLength(1));

        player.playSequencedNote(
          64,
          duration: const Duration(milliseconds: 40),
          volume: 0.7,
          pan: -0.25,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(platform.volumes.last.$2, 0.7);
        expect(platform.balances.last.$2, -0.25);
      },
    );

    test('the pool is capped and surplus voices are dropped', () async {
      final baseline = platform.created.length;
      for (var i = 0; i < 60; i++) {
        player.playSequencedNote(
          40 + i % 24,
          duration: const Duration(seconds: 1),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(platform.created.length - baseline, 32);
      expect(platform.resumes.toSet(), hasLength(32));
      expect(platform.resumes, hasLength(32));
    });
  });
}

class _AudioPlatform extends AudioplayersPlatformInterface {
  final events = <String, StreamController<AudioEvent>>{};
  final created = <String>[];
  final releaseModes = <String>[];
  final sources = <Uint8List>[];
  final sourcePlayers = <String>[];
  final resumes = <String>[];
  final stops = <String>[];
  final volumes = <(String, double)>[];
  final balances = <(String, double)>[];
  final positionQueries = <String>[];
  final firstSource = Completer<void>();
  final firstResume = Completer<void>();
  Completer<void>? sourceGate;

  StreamController<AudioEvent> stream(String id) => events.putIfAbsent(
    id,
    () => StreamController<AudioEvent>.broadcast(sync: true),
  );
  @override
  Stream<AudioEvent> getEventStream(String playerId) => stream(playerId).stream;
  @override
  Future<void> create(String playerId) async => created.add(playerId);
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async =>
      releaseModes.add(playerId);
  @override
  Future<void> setVolume(String playerId, double volume) async =>
      volumes.add((playerId, volume));
  @override
  Future<void> setBalance(String playerId, double balance) async =>
      balances.add((playerId, balance));
  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    sources.add(bytes);
    sourcePlayers.add(playerId);
    if (!firstSource.isCompleted) firstSource.complete();
    await sourceGate?.future;
    stream(playerId).add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> resume(String playerId) async {
    resumes.add(playerId);
    if (!firstResume.isCompleted) firstResume.complete();
  }

  @override
  Future<void> stop(String playerId) async => stops.add(playerId);
  @override
  Future<void> release(String playerId) async {}
  @override
  Future<void> dispose(String playerId) async {}
  @override
  Future<int?> getCurrentPosition(String playerId) async {
    positionQueries.add(playerId);
    return 0;
  }

  Future<void> close() async {
    for (final event in events.values) {
      await event.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
