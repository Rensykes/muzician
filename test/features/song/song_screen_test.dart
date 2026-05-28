import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_screen.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';

void main() {
  testWidgets('SongScreen renders header and empty state', (tester) async {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongScreen()),
      ),
    );

    expect(find.text('Song'), findsOneWidget);
    expect(find.text('Add Track'), findsAtLeast(1));
    expect(find.text('No tracks yet'), findsOneWidget);
  });

  testWidgets('creating a note track renders a track header', (tester) async {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    container.read(songProjectProvider.notifier).addTrack(SongTrackType.note);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongScreen()),
      ),
    );

    expect(find.text('Note Track'), findsOneWidget);
    expect(find.text('NOTE'), findsOneWidget);
  });

  testWidgets('creating a drum track shows DRUM badge', (tester) async {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    container.read(songProjectProvider.notifier).addTrack(SongTrackType.drum);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongScreen()),
      ),
    );

    expect(find.text('Drum Track'), findsOneWidget);
    expect(find.text('DRUM'), findsOneWidget);
  });
}
