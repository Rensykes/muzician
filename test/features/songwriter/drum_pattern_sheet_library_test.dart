import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/drum_pattern_sheet.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  testWidgets('drum sheet shows the Library button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(songwriterProvider.notifier).loadProject(
      const SongwriterProjectSnapshot(
        name: 'demo',
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        drumPatterns: [
          DrumPattern(
            id: 'p1',
            name: 'Beat',
            lengthTicks: 16,
            lanes: [
              DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSongwriterDrumPatternSheet(
                  context: context,
                  patternId: 'p1',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drumLibraryButton')), findsOneWidget);
  });
}
