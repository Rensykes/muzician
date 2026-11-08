import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';

DrumPattern _emptyPattern() => const DrumPattern(
  id: 'p1',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.closedHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.openHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.clap, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.lowTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.highTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.crash, activeTicks: []),
  ],
);

Future<void> _pumpBody(
  WidgetTester tester,
  void Function(DrumPattern) onChanged,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: _emptyPattern(),
            tempo: 120,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every-beat fill sets the kick lane to [0,4,8,12]', (
    tester,
  ) async {
    DrumPattern? captured;
    await _pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fillEvery_4')));
    await tester.pumpAndSettle();

    final kick =
        captured!.lanes.firstWhere((l) => l.laneId == DrumLaneId.kick);
    expect(kick.activeTicks, [0, 4, 8, 12]);
  });

  testWidgets('euclid fill sets the snare lane to [0,5,10]', (tester) async {
    DrumPattern? captured;
    await _pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('laneFillMenu_snare')));
    await tester.pumpAndSettle();
    // Lower hits from the default (4) to 3 via the minus stepper, then apply.
    await tester.tap(find.byKey(const Key('euclidHitsMinus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fillEuclidApply')));
    await tester.pumpAndSettle();

    final snare =
        captured!.lanes.firstWhere((l) => l.laneId == DrumLaneId.snare);
    // 3 hits over 16 ticks → Bjorklund spacing 5,5,6.
    expect(snare.activeTicks, [0, 5, 10]);
  });

  testWidgets('clear-lane empties the lane', (tester) async {
    DrumPattern? captured;
    await _pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fillEvery_4')));
    await tester.pumpAndSettle();
    expect(
      captured!.lanes
          .firstWhere((l) => l.laneId == DrumLaneId.kick)
          .activeTicks,
      isNotEmpty,
    );

    await tester.tap(find.byKey(const Key('laneFillMenu_kick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fillClear')));
    await tester.pumpAndSettle();
    expect(
      captured!.lanes
          .firstWhere((l) => l.laneId == DrumLaneId.kick)
          .activeTicks,
      isEmpty,
    );
  });
}
