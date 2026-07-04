import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_mixer_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<(ProviderContainer, String, List<String>)> pumpMixer(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    final h = n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final d = n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('openMixer'),
                onPressed: () =>
                    showSongwriterMixerSheet(context, sectionId: sectionId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openMixer')));
    await tester.pumpAndSettle();
    return (container, sectionId, [h, d]);
  }

  testWidgets('renders one strip per lane', (tester) async {
    await pumpMixer(tester);
    expect(find.text('Harmony'), findsOneWidget);
    expect(find.text('Beat'), findsOneWidget);
  });

  testWidgets('volume slider writes lane volume', (tester) async {
    final (container, sectionId, laneIds) = await pumpMixer(tester);
    final slider = find.byKey(Key('mixerVolume_${laneIds.first}'));
    expect(slider, findsOneWidget);
    // Drag fully left → volume 0.
    await tester.drag(slider, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final lane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneIds.first);
    expect(lane.volume, 0.0);
  });

  testWidgets('pan slider snaps near-center to 0', (tester) async {
    final (container, sectionId, laneIds) = await pumpMixer(tester);
    final slider = find.byKey(Key('mixerPan_${laneIds.first}'));
    // Tiny nudge stays snapped at center.
    await tester.drag(slider, const Offset(4, 0));
    await tester.pumpAndSettle();
    final lane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneIds.first);
    expect(lane.pan, 0.0);
  });

  testWidgets('mute toggle flips lane.muted', (tester) async {
    final (container, sectionId, laneIds) = await pumpMixer(tester);
    await tester.tap(find.byKey(Key('mixerMute_${laneIds.last}')));
    await tester.pumpAndSettle();
    SongLane lane() => container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.id == laneIds.last);
    expect(lane().muted, true);
    await tester.tap(find.byKey(Key('mixerMute_${laneIds.last}')));
    await tester.pumpAndSettle();
    expect(lane().muted, false);
  });
}
