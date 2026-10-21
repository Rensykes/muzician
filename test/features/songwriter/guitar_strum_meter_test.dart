import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/guitar_strum_pattern_sheet.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final meter in [(3, 8), (6, 8), (3, 16), (2, 2)]) {
    testWidgets(
      '${meter.$1}/${meter.$2} strum groups retain bar boundaries at 320 and 1.5 text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final writer = container.read(songwriterProvider.notifier);
        writer.setMeter(beatsPerBar: meter.$1, beatUnit: meter.$2);
        final config = container.read(songwriterProvider).config;
        final patternId = writer.addGuitarStrumPattern(
          lengthTicks: config.measureTicks * 2,
        );
        final original = container
            .read(songwriterProvider)
            .guitarStrumPatterns
            .single;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: StudioTheme.data(AppThemeVariant.studio),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showGuitarStrumPatternSheet(
                      context: context,
                      patternId: patternId,
                    ),
                    child: const Text('Open strum'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('Open strum'));
        await tester.pumpAndSettle();

        for (var beat = 0; beat < meter.$1 * 2; beat++) {
          final group = find.byKey(Key('guitarStrumBeat_$beat'));
          expect(group, findsOneWidget);
          expect(
            find.descendant(
              of: group,
              matching: find.text(
                'Bar ${beat ~/ meter.$1 + 1} · Beat ${beat % meter.$1 + 1}',
              ),
            ),
            findsOneWidget,
          );
          final firstTick = beat * config.ticksPerBeat;
          final lastTick = firstTick + config.ticksPerBeat - 1;
          expect(
            firstTick ~/ config.measureTicks,
            lastTick ~/ config.measureTicks,
          );
          for (var tick = firstTick; tick <= lastTick; tick++) {
            final face = find.byKey(Key('guitarStrumStepFace_$tick'));
            expect(find.descendant(of: group, matching: face), findsOneWidget);
            expect(tester.getSize(face), const Size(44, 44));
            final rect = tester.getRect(face);
            final groupRect = tester.getRect(group);
            expect(rect.left, greaterThanOrEqualTo(groupRect.left));
            expect(rect.right, lessThanOrEqualTo(groupRect.right));
          }
        }
        expect(
          find.byKey(Key('guitarStrumBeat_${meter.$1 * 2}')),
          findsNothing,
        );
        expect(
          container.read(songwriterProvider).guitarStrumPatterns.single,
          same(original),
          reason:
              'Grouping must not rewrite events, tick positions, or pattern length.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
