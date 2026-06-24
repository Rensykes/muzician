import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_library_sheet.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/drum_presets.dart';

void main() {
  testWidgets('library sheet lists presets by category and fires onPick', (
    tester,
  ) async {
    DrumPreset? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDrumLibrarySheet(
                context: context,
                onPick: (p) => picked = p,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Rock'), findsWidgets);
    expect(find.byKey(const Key('preset_Four on the Floor')), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset_Four on the Floor')));
    await tester.pumpAndSettle();

    expect(picked?.name, 'Four on the Floor');
  });

  DrumPattern emptyPattern(String id) => DrumPattern(
    id: id,
    name: 'Beat',
    lengthTicks: 16,
    lanes: [
      for (final laneId in DrumLaneId.values)
        DrumLaneSequence(laneId: laneId, activeTicks: const []),
    ],
  );

  testWidgets('Library button applies a preset to the pattern, same id', (
    tester,
  ) async {
    DrumPattern? captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: emptyPattern('p1'),
              tempo: 120,
              enableLibrary: true,
              onChanged: (p) => captured = p,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('drumLibraryButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preset_Four on the Floor')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.id, 'p1'); // same id → block stays linked
    final kick = captured!.lanes.firstWhere((l) => l.laneId == DrumLaneId.kick);
    expect(kick.activeTicks, [0, 4, 8, 12]);
  });

  testWidgets('no Library button when enableLibrary is false', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: emptyPattern('p1'),
              tempo: 120,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('drumLibraryButton')), findsNothing);
  });

  testWidgets('My Loops button shows when enableLibrary is true', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: emptyPattern('p1'),
              tempo: 120,
              enableLibrary: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('drumLoopsButton')), findsOneWidget);
  });

  testWidgets('My Loops button hidden when enableLibrary is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: emptyPattern('p1'),
              tempo: 120,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('drumLoopsButton')), findsNothing);
  });
}
