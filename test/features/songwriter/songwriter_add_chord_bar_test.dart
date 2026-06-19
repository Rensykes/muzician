import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'tapping the first bar cell adds the chord at that bar (not the 2nd row)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(songwriterProvider.notifier);

      // Clear the key so the harmony sheet shows the tappable manual picker
      // (the diatonic chord wheel is a CustomPaint and is not key-tappable).
      n.setKey(null, null);
      n.addSection(label: 'Verse', lengthBars: 8);
      final section = container.read(songwriterProvider).sections.first;
      n.addLane(
        sectionId: section.id,
        kind: SongLaneKind.harmony,
        label: 'Harmony',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // The empty 8-bar lane renders one '·' placeholder per bar.
      // Tap the very first one (bar 0 — top-left) — now opens the add menu.
      expect(find.text('·'), findsNWidgets(8));
      await tester.tap(find.text('·').first);
      await tester.pumpAndSettle();

      // Tap "Add chord" in the new add menu to open the chord sheet.
      await tester.tap(find.byKey(const Key('barActionAddChord')));
      await tester.pumpAndSettle();

      // Manual picker: pick root C then quality maj (value '').
      await tester.ensureVisible(find.byKey(const Key('harmonyRoot_0')));
      await tester.tap(find.byKey(const Key('harmonyRoot_0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('harmonyQuality_')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('harmonyQuality_')));
      await tester.pumpAndSettle();

      final lane = container
          .read(songwriterProvider)
          .sections
          .first
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.harmony);
      expect(lane.blocks, hasLength(1));
      expect(lane.blocks.first.startBar, 0);
    },
  );
}
