import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:muzician/utils/playback_profile_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const globalAudioChannel = MethodChannel('xyz.luan/audioplayers.global');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AudioplayersPlatformInterface previousPlatform;
  late TargetPlatform? previousTargetPlatform;
  late _FakeAudioPlatform platform;

  setUp(() {
    previousPlatform = AudioplayersPlatformInterface.instance;
    previousTargetPlatform = debugDefaultTargetPlatformOverride;
    platform = _FakeAudioPlatform();
    AudioplayersPlatformInterface.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      globalAudioChannel,
      (call) async => null,
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = previousTargetPlatform;
    AudioplayersPlatformInterface.instance = previousPlatform;
    messenger.setMockMethodCallHandler(globalAudioChannel, null);
    await platform.closeEvents();
  });

  test(
    'forwards MIME type and binds the original source once through play',
    () async {
      final delegate = _PublicBytesSource();
      final sourceArguments = sequencedPlaybackProfileArguments(
        profileTimelineArguments: _profileArguments,
        sequencedVoiceId: 23,
        additionalArguments: const {
          'kind': 'sequenced',
          'midi': 60,
          // A local player handle must never replace the profile voice ID.
          'voice_id': 23,
          'player_id': 99,
        },
      );
      final source = PlaybackProfileSource(delegate, sourceArguments);
      final player = AudioPlayer();

      expect(source.arguments['voice_id'], 'voice-4');
      expect(source.arguments['sequenced_voice_id'], 23);
      expect(source.mimeType, 'audio/wav');
      await player.play(source);

      expect(delegate.bindCount, 1);
      expect(platform.mimeType, 'audio/wav');
      expect(platform.calls, [
        'create',
        'setSourceBytes',
        'getCurrentPosition',
        'resume',
      ]);
      expect(player.desiredState, PlayerState.playing);

      await player.dispose();
    },
  );

  test(
    'preserves play desired-state cancellation while source binding waits',
    () async {
      final sourceGate = Completer<void>();
      platform.sourceGate = sourceGate;
      final player = AudioPlayer();
      final playFuture = player.play(
        PlaybackProfileSource(_PublicBytesSource(), _profileArguments),
      );

      await platform.sourceBindingStarted.future;
      await player.pause();
      sourceGate.complete();
      await playFuture;

      expect(platform.calls, [
        'create',
        'setSourceBytes',
        'pause',
        'getCurrentPosition',
        'getCurrentPosition',
      ]);
      expect(platform.calls, isNot(contains('resume')));
      expect(player.desiredState, PlayerState.paused);
      expect(player.state, PlayerState.paused);

      await player.dispose();
    },
  );

  test('rethrows source-binding errors from play', () async {
    final error = StateError('source binding failed');
    final delegate = _FailingSource(error);
    final player = AudioPlayer();

    await expectLater(
      player.play(PlaybackProfileSource(delegate, _profileArguments)),
      throwsA(same(error)),
    );

    expect(delegate.bindCount, 1);
    expect(platform.calls, ['create']);
    await player.dispose();
  });
}

const _profileArguments = <String, Object?>{
  'run_id': 12,
  'event_id': 4,
  'voice_id': 'voice-4',
  'player_id': 99,
  'kind': 'sequenced',
  'midi': 60,
};

class _PublicBytesSource extends Source {
  int bindCount = 0;

  @override
  String? get mimeType => 'audio/wav';

  @override
  Future<void> setOnPlayer(AudioPlayer player) async {
    bindCount++;
    await player.setSourceBytes(
      Uint8List.fromList([1, 2, 3]),
      mimeType: mimeType,
    );
  }
}

class _FailingSource extends Source {
  _FailingSource(this.error);

  final Object error;
  int bindCount = 0;

  @override
  String? get mimeType => null;

  @override
  Future<void> setOnPlayer(AudioPlayer player) async {
    bindCount++;
    throw error;
  }
}

class _FakeAudioPlatform extends AudioplayersPlatformInterface {
  final List<String> calls = [];
  final StreamController<AudioEvent> _events =
      StreamController<AudioEvent>.broadcast(sync: true);
  final Completer<void> sourceBindingStarted = Completer<void>();
  Completer<void>? sourceGate;
  String? mimeType;

  @override
  Stream<AudioEvent> getEventStream(String playerId) => _events.stream;

  @override
  Future<void> create(String playerId) async {
    calls.add('create');
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    calls.add('setSourceBytes');
    this.mimeType = mimeType;
    if (!sourceBindingStarted.isCompleted) sourceBindingStarted.complete();
    await sourceGate?.future;
    _events.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> pause(String playerId) async {
    calls.add('pause');
  }

  @override
  Future<void> stop(String playerId) async {
    calls.add('stop');
  }

  @override
  Future<void> resume(String playerId) async {
    calls.add('resume');
  }

  @override
  Future<void> release(String playerId) async {
    calls.add('release');
  }

  @override
  Future<void> dispose(String playerId) async {
    calls.add('dispose');
  }

  @override
  Future<int?> getCurrentPosition(String playerId) async {
    calls.add('getCurrentPosition');
    return 0;
  }

  Future<void> closeEvents() => _events.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
