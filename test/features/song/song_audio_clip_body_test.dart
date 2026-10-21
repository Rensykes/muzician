import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_clip_body.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/theme/studio_theme.dart';

void main() {
  testWidgets('waveform and broken overlay repaint with the host palette', (
    tester,
  ) async {
    final variant = ValueNotifier(AppThemeVariant.studio);
    addTearDown(variant.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<AppThemeVariant>(
        valueListenable: variant,
        builder: (context, value, _) => MaterialApp(
          theme: StudioTheme.data(value),
          home: const Scaffold(
            body: SizedBox(
              width: 200,
              height: 60,
              child: AudioClipBody(
                name: 'Take',
                durationMs: 1000,
                format: 'wav',
                peaks: [100, 200],
                isBroken: true,
              ),
            ),
          ),
        ),
      ),
    );
    final paints = find.descendant(
      of: find.byType(AudioClipBody),
      matching: find.byType(CustomPaint),
    );
    final oldPainters = tester
        .widgetList<CustomPaint>(paints)
        .map((paint) => paint.painter!)
        .toList();
    final oldWaveform = oldPainters.whereType<AudioWaveformPainter>().single;
    expect(oldWaveform.palette, StudioPalette.studio);
    expect(oldWaveform.accent, StudioPalette.studio.teal);
    variant.value = AppThemeVariant.studioMuzician;
    await tester.pumpAndSettle();
    final newPainters = tester
        .widgetList<CustomPaint>(paints)
        .map((paint) => paint.painter!)
        .toList();
    for (var i = 0; i < oldPainters.length; i++) {
      expect(newPainters[i].shouldRepaint(oldPainters[i]), isTrue);
    }
    expect(
      newPainters.whereType<AudioWaveformPainter>().single.palette,
      StudioPalette.studioMuzician,
    );
    expect(find.text('Take'), findsOneWidget);
  });

  testWidgets('renders clip name and duration label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: AudioClipBody(
              name: 'Take 1',
              durationMs: 12345,
              format: 'wav',
              peaks: [0, 64, 128, 192, 255],
              isBroken: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Take 1'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('WAV'), findsOneWidget);
  });

  testWidgets('shows broken indicator when isBroken', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: AudioClipBody(
              name: 'Missing',
              durationMs: 1000,
              format: 'wav',
              peaks: [],
              isBroken: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('audio-clip-broken')), findsOneWidget);
  });
}
