import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/songwriter/songwriter_section_ruler.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  testWidgets('tapping a ruler bar parks the start tick at that bar', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'A', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    final cfg = container.read(songwriterProvider).config;
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SongwriterSectionRuler(section: section, instanceIndex: 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 4 bars over 400px → 100px/bar. Tap at localX 250 → bar 2.
    final topLeft = tester.getTopLeft(
      find.byKey(Key('sectionRuler_${section.id}_0')),
    );
    await tester.tapAt(topLeft + const Offset(250, 9));
    await tester.pump();

    expect(container.read(songwriterStartTickProvider), 2 * measureTicks);
  });

  testWidgets(
    'parked marker shows only when the start tick is in this section',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sw = container.read(songwriterProvider.notifier);
      sw.addSection(label: 'A', lengthBars: 2);
      sw.addSection(label: 'B', lengthBars: 2);
      final sections = container.read(songwriterProvider).sections;
      final cfg = container.read(songwriterProvider).config;
      final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
      // Park in section B (global bar 2).
      container
          .read(songwriterStartTickProvider.notifier)
          .setTick(2 * measureTicks);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 400,
                    child: SongwriterSectionRuler(
                      section: sections[0],
                      instanceIndex: 0,
                    ),
                  ),
                  SizedBox(
                    width: 400,
                    child: SongwriterSectionRuler(
                      section: sections[1],
                      instanceIndex: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Marker in B (parked there), not in A.
      expect(find.byKey(const Key('sectionRulerMarker')), findsOneWidget);
    },
  );
}
