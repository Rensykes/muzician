import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';

DrumPattern fullPattern(String id) => DrumPattern(
  id: id,
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    for (final laneId in DrumLaneId.values)
      DrumLaneSequence(
        laneId: laneId,
        activeTicks: laneId == DrumLaneId.kick
            ? const [0, 4, 8, 12]
            : laneId == DrumLaneId.snare
            ? const [4, 12]
            : const [],
      ),
  ],
);

Future<void> pumpBody(
  WidgetTester tester,
  void Function(DrumPattern) onChanged,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: DrumMachineEditorBody(
            pattern: fullPattern('p1'),
            tempo: 120,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('clear-all empties every lane after confirm', (tester) async {
    DrumPattern? captured;
    await pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('drumClearAllButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    for (final lane in captured!.lanes) {
      expect(lane.activeTicks, isEmpty, reason: lane.laneId.name);
    }
  });

  testWidgets('clear-all cancel keeps the pattern intact', (tester) async {
    DrumPattern? captured;
    await pumpBody(tester, (p) => captured = p);

    await tester.tap(find.byKey(const Key('drumClearAllButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Cancelling never calls onChanged, so no clear happened.
    expect(captured, isNull);
  });
}
