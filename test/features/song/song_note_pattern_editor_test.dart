import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_note_pattern_editor.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  testWidgets('SongNotePatternEditor shows pattern name and Make unique', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

  testWidgets('failed save keeps editor open and shows feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
              SongClipInstance(
                id: 'c2',
                trackId: 't1',
                patternId: 'p2',
                patternType: SongPatternType.note,
                startTick: 16,
              ),
            ],
            notePatterns: const [
              NotePattern(
                id: 'p1',
                name: 'Pattern A',
                lengthTicks: 16,
                notes: [],
                pitchRangeStart: 48,
                pitchRangeEnd: 84,
                snapTicks: 1,
                highlightedNotes: [],
              ),
              NotePattern(
                id: 'p2',
                name: 'Pattern B',
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

    final scopes = tester.widgetList<UncontrolledProviderScope>(
      find.byType(UncontrolledProviderScope),
    );
    final isolatedContainer = scopes.last.container;
    isolatedContainer.read(pianoRollProvider.notifier).setTotalMeasures(2);
    isolatedContainer.read(pianoRollProvider.notifier).addNote(60, 16, 4);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.byType(SongNotePatternEditor), findsOneWidget);
    expect(
      find.text(
        'Pattern resize rejected because it would overlap another clip.',
      ),
      findsOneWidget,
    );
  });
}
