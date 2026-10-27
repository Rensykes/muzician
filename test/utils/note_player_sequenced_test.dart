import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/guitar_sound.dart';
import 'package:muzician/utils/note_player.dart';

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
}

class _AudioPlatform extends AudioplayersPlatformInterface {
  final events = <String, StreamController<AudioEvent>>{};
  final sources = <Uint8List>[];
  final sourcePlayers = <String>[];
  final resumes = <String>[];
  final stops = <String>[];
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
  Future<void> create(String playerId) async {}
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}
  @override
  Future<void> setVolume(String playerId, double volume) async {}
  @override
  Future<void> setBalance(String playerId, double balance) async {}
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
  Future<int?> getCurrentPosition(String playerId) async => 0;
  Future<void> close() async {
    for (final event in events.values) {
      await event.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
