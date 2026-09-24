import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_export_actions.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'canceling replacement on a non-empty Song keeps project and media intact',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'song-bundle-cancel-test-',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final repository = SongAudioRepository.testWith(rootDirectory: directory);
      final asset = AudioAsset(
        id: 'current-take',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: const [],
        sourceLabel: 'Current take',
      );
      final mediaFile = File(
        '${directory.path}/song_audio/${asset.id}.${asset.format}',
      )..parent.createSync(recursive: true);
      mediaFile.writeAsBytesSync([1, 2, 3, 4]);
      final project = SongProject(
        config: const SongProjectConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [
          SongTrack(
            id: 'audio-track',
            name: 'Audio',
            type: SongTrackType.audio,
            order: 0,
          ),
        ],
        clips: const [
          SongClipInstance(
            id: 'audio-clip',
            trackId: 'audio-track',
            patternId: 'audio-pattern',
            patternType: SongPatternType.audio,
            startTick: 0,
          ),
        ],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: [asset],
        audioPatterns: const [
          AudioClipPattern(
            id: 'audio-pattern',
            name: 'Current take',
            assetId: 'current-take',
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [songAudioRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(songProjectProvider.notifier).state = project;
      var pickerCalls = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () {
                    importSongBundle(
                      context,
                      ref,
                      pickBundleBytes: () async {
                        pickerCalls++;
                        return null;
                      },
                    );
                  },
                  child: const Text('Import bundle'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Import bundle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Replace this Song?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelSongBundleReplacement')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(pickerCalls, 0);
      expect(identical(container.read(songProjectProvider), project), isTrue);
      expect(mediaFile.readAsBytesSync(), [1, 2, 3, 4]);
    },
  );
}
