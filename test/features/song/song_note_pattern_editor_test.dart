import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_note_pattern_editor.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  testWidgets('SongNotePatternEditor shows pattern name and Make unique', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(songProjectProvider.notifier)
        .loadProject(
          SongProject(
            config: const SongProjectConfig(
              tempo: 120,
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
            clips: const [
              SongClipInstance(
                id: 'c1',
                trackId: 't1',
                patternId: 'p1',
                patternType: SongPatternType.note,
                startTick: 0,
              ),
            ],
            notePatterns: const [
              NotePattern(
                id: 'p1',
                name: 'Test Pattern',
                lengthTicks: 16,
                notes: [],
                pitchRangeStart: 48,
                pitchRangeEnd: 84,
                snapTicks: 1,
                highlightedNotes: [],
              ),
            ],
            drumPatterns: const [],
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SongNotePatternEditor(clipId: 'c1', patternId: 'p1'),
        ),
      ),
    );

    expect(find.text('Test Pattern'), findsOneWidget);
    expect(find.text('Make unique'), findsOneWidget);
    expect(find.text('Used in 1 clips'), findsOneWidget);
  });
}
