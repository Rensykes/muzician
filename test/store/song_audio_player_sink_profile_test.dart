import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_player_sink.dart';
import 'package:muzician/store/song_audio_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clip sink propagates a path-resolution failure from prepare', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'song_clip_sink_profile_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final rootFile = File('${tempDirectory.path}/not_a_directory');
    await rootFile.writeAsString('fixture');
    final failingRepository = SongAudioRepository.testWith(
      rootDirectory: Directory(rootFile.path),
    );
    final calls = <String>[];
    const globalAudioChannel = MethodChannel('xyz.luan/audioplayers.global');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(globalAudioChannel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(globalAudioChannel, null),
    );

    final sink = AudioPlayersClipSink(failingRepository);
    await expectLater(
      sink.prepare([
        const AudioAsset(
          id: 'profile_failure_clip',
          durationMs: 1000,
          sampleRate: 44100,
          channels: 1,
          format: 'wav',
          peaks: [],
          sourceLabel: 'Temporary profile test',
        ),
      ]),
      throwsA(isA<FileSystemException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, contains('setAudioContext'));
  });
}
