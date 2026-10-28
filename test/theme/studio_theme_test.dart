import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/theme/studio_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  for (final variant in AppThemeVariant.values) {
    final palette = StudioTheme.data(variant).extension<StudioPalette>()!;
    test('${variant.name} readable text and primary control contrast', () {
      for (final background in [
        palette.scaffoldBg,
        palette.surface,
        palette.dialogBg,
      ]) {
        for (final foreground in [
          palette.textPrimary,
          palette.textSecondary,
          palette.textMuted,
        ]) {
          expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(palette.sky, background), greaterThanOrEqualTo(3));
      }
      expect(
        contrast(palette.onAccent, palette.sky),
        greaterThanOrEqualTo(4.5),
      );
      expect(palette.glassBg.a, 1);
      expect(palette.isStudio, isTrue);
    });
  }

  test('palette copy and interpolation leave canonical constants intact', () {
    final colors = <Color>[Colors.red, Colors.red, Colors.red, Colors.red];
    final copy = StudioPalette.studio.copyWith(gradientColors: colors);
    colors[0] = Colors.blue;
    expect(copy.gradientColors.first, Colors.red);
    expect(() => copy.gradientColors.add(Colors.blue), throwsUnsupportedError);
    expect(StudioPalette.studio.gradientColors.first, const Color(0xFF171C1B));
    final halfway = StudioPalette.studio.lerp(
      StudioPalette.studioMuzician,
      0.5,
    );
    expect(
      halfway.sky,
      Color.lerp(
        StudioPalette.studio.sky,
        StudioPalette.studioMuzician.sky,
        0.5,
      ),
    );
  });

  testWidgets(
    'unthemed hosts retain legacy and explicit legacy overrides root',
    (tester) async {
      late StudioPalette actual;
      await tester.pumpWidget(
        StudioThemeSource(
          variant: AppThemeVariant.studio,
          child: MaterialApp(
            home: StudioRouteTheme(
              isStudio: false,
              child: Builder(
                builder: (context) {
                  actual = StudioPalette.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(actual, StudioPalette.legacy);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              actual = StudioPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(actual, StudioPalette.legacy);
    },
  );
}
