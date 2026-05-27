import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_save_panel.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  testWidgets('SongSavePanel captures the current song project', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(songProjectProvider.notifier)
        .loadProject(
          SongProject(
            config: const SongProjectConfig(
              tempo: 132,
              timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
              totalMeasures: 4,
            ),
            tracks: const [
              SongTrack(
                id: 't1',
                name: 'Lead',
                type: SongTrackType.note,
                order: 0,
              ),
            ],
            clips: const [],
            notePatterns: const [],
            drumPatterns: const [],
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongSavePanel())),
      ),
    );

    expect(find.text('Library'), findsOneWidget);
  });
}
