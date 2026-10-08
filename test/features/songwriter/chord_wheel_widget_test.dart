import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/utils/note_utils.dart';

const _wheelCaptureKey = ValueKey('wheelCapture');

Finder _wheelPainterFinder() => find.descendant(
  of: find.byType(ChordWheel),
  matching: find.byType(CustomPaint),
);

Future<void> _pumpWheel(
  WidgetTester tester, {
  required Size viewportSize,
  required double textScale,
  int keyRootPc = 0,
  String scaleName = 'major',
  NoteSpelling spelling = NoteSpelling.sharps,
  TextDirection textDirection = TextDirection.ltr,
  ValueChanged<DiatonicTriad>? onPick,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1;
  final wheelWidth = viewportSize.width < 400 ? viewportSize.width - 32 : 320.0;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: viewportSize,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _wheelCaptureKey,
              child: SizedBox(
                width: wheelWidth,
                height: 240,
                child: Directionality(
                  textDirection: textDirection,
                  child: ChordWheel(
                    key: ValueKey('wheel-${spelling.name}'),
                    keyRootPc: keyRootPc,
                    scaleName: scaleName,
                    spelling: spelling,
                    onPick: onPick ?? (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<({Size size, List<int> pixels})> _captureWheel(
  WidgetTester tester,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_wheelCaptureKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) throw StateError('Could not capture the wheel image.');
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  if (data == null) throw StateError('Could not read the wheel image pixels.');
  image.dispose();
  return (
    size: boundary.size,
    pixels: List<int>.from(data.buffer.asUint8List()),
  );
}

Offset _firstLabelCenter(Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  final outerRadius = size.shortestSide / 2 - 4;
  final innerRadius = outerRadius * 0.3;
  final labelRadius = (innerRadius + outerRadius) / 2;
  final midAngle = -math.pi / 2 + math.pi / 7;
  return Offset(
    center.dx + labelRadius * math.cos(midAngle),
    center.dy + labelRadius * math.sin(midAngle),
  );
}

int _countBrightPixels(({Size size, List<int> pixels}) image, Rect region) {
  final left = region.left.floor().clamp(0, image.size.width.toInt()).toInt();
  final top = region.top.floor().clamp(0, image.size.height.toInt()).toInt();
  final right = region.right.ceil().clamp(0, image.size.width.toInt()).toInt();
  final bottom = region.bottom
      .ceil()
      .clamp(0, image.size.height.toInt())
      .toInt();
  var count = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * image.size.width.toInt() + x) * 4;
      if (image.pixels[offset] > 200 &&
          image.pixels[offset + 1] > 200 &&
          image.pixels[offset + 2] > 200) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  testWidgets('tapping near 12 o\'clock calls onPick with degree 0 (I)', (
    tester,
  ) async {
    DiatonicTriad? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: ChordWheel(
              keyRootPc: 0,
              scaleName: 'major',
              onPick: (t) => picked = t,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap near 12 o'clock, slightly clockwise so we're inside wedge 0 (not on
    // its boundary). Center is (150,150). Move up and slightly right.
    await tester.tapAt(const Offset(160, 40));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.degree, 0);
    expect(picked!.romanNumeral, 'I');
    expect(picked!.symbol, 'C');
  });

  testWidgets('hole and outside taps do not choose a chord', (tester) async {
    DiatonicTriad? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: ChordWheel(
              keyRootPc: 0,
              scaleName: 'major',
              onPick: (triad) => picked = triad,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    await tester.tapAt(const Offset(0, 0));
    await tester.pump();

    expect(picked, isNull);
  });

  testWidgets('exposes seven labeled chord buttons with direct actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final picked = <DiatonicTriad>[];
    await _pumpWheel(
      tester,
      viewportSize: const Size(320, 800),
      textScale: 1,
      onPick: picked.add,
    );

    final triads = diatonicTriads(0, 'major');
    expect(triads, hasLength(7));
    for (final triad in triads) {
      final symbol = formatRecognizedChordLabel(
        symbol: triad.symbol,
        rootPc: triad.rootPc,
        quality: triad.quality,
        spelling: NoteSpelling.sharps,
      );
      final label = '${triad.romanNumeral}, $symbol chord';
      final target = find.semantics.byLabel(label);
      expect(target, findsOneWidget);
      final node = target.evaluate().single;
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(node.rect.width, greaterThanOrEqualTo(44));
      expect(node.rect.height, greaterThanOrEqualTo(44));

      tester.semantics.tap(find.semantics.byLabel(label));
      expect(picked, hasLength(triad.degree + 1));
      expect(picked.last.degree, triad.degree);
      expect(picked.last.rootPc, triad.rootPc);
      expect(picked.last.quality, triad.quality);
    }
    expect(find.semantics.byLabel(RegExp(r' chord$')), findsNWidgets(7));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('renders without errors and shows fallback for no scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: ChordWheel(keyRootPc: 0, scaleName: 'major', onPick: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains that an unsupported scale has no seven-degree wheel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: ChordWheel(
              keyRootPc: 0,
              scaleName: 'nonexistent',
              onPick: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This scale does not support the seven-degree chord wheel.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'scales both wheel labels and repaints at compact and wide sizes',
    (tester) async {
      for (final viewportSize in [
        const Size(320, 800),
        const Size(1024, 800),
      ]) {
        await _pumpWheel(tester, viewportSize: viewportSize, textScale: 1);
        final basePainter = tester.widget<CustomPaint>(_wheelPainterFinder());
        final baseImage = await _captureWheel(tester);

        await _pumpWheel(tester, viewportSize: viewportSize, textScale: 1.6);
        final scaledPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
        expect(
          basePainter.painter!.shouldRepaint(scaledPainter.painter!),
          isTrue,
        );
        final scaledImage = await _captureWheel(tester);
        expect(scaledImage.size, baseImage.size);

        final labelCenter = _firstLabelCenter(baseImage.size);
        final symbolRegion = Rect.fromLTRB(
          labelCenter.dx - 34,
          labelCenter.dy - 32,
          labelCenter.dx + 34,
          labelCenter.dy,
        );
        final numeralRegion = Rect.fromLTRB(
          labelCenter.dx - 34,
          labelCenter.dy + 1,
          labelCenter.dx + 34,
          labelCenter.dy + 29,
        );
        expect(
          _countBrightPixels(scaledImage, symbolRegion),
          greaterThan(_countBrightPixels(baseImage, symbolRegion)),
        );
        expect(
          _countBrightPixels(scaledImage, numeralRegion),
          greaterThan(_countBrightPixels(baseImage, numeralRegion)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('spelling changes wheel labels without changing picked triads', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    DiatonicTriad? picked;
    const viewportSize = Size(320, 800);
    final tonic = diatonicTriads(1, 'major').first;
    String labelFor(NoteSpelling spelling) => formatRecognizedChordLabel(
      symbol: tonic.symbol,
      rootPc: tonic.rootPc,
      quality: tonic.quality,
      spelling: spelling,
    );
    final sharpLabel = labelFor(NoteSpelling.sharps);
    final flatLabel = labelFor(NoteSpelling.flats);
    expect(tonic.symbol, 'C#');
    expect(sharpLabel, 'C#');
    expect(flatLabel, 'Db');

    await _pumpWheel(
      tester,
      viewportSize: viewportSize,
      textScale: 1,
      keyRootPc: 1,
      spelling: NoteSpelling.sharps,
      onPick: (triad) => picked = triad,
    );
    final sharpPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
    final sharpTarget = find.semantics.byLabel('I, C# chord');
    expect(sharpTarget, findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('I, C# chord'));
    expect(picked?.rootPc, 1);
    expect(picked?.symbol, 'C#');
    final wheelRect = tester.getRect(_wheelPainterFinder());
    await tester.tapAt(wheelRect.center + const Offset(10, -80));
    await tester.pumpAndSettle();
    expect(picked?.rootPc, 1);
    expect(picked?.quality, '');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _pumpWheel(
      tester,
      viewportSize: viewportSize,
      textScale: 1,
      keyRootPc: 1,
      spelling: NoteSpelling.flats,
      onPick: (triad) => picked = triad,
    );
    final flatPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
    expect(sharpPainter.painter!.shouldRepaint(flatPainter.painter!), isTrue);
    final flatTarget = find.semantics.byLabel('I, Db chord');
    expect(flatTarget, findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('I, Db chord'));
    expect(picked?.rootPc, 1);
    expect(picked?.quality, '');
    expect(picked?.symbol, 'C#');
    final flatWheelRect = tester.getRect(_wheelPainterFinder());
    await tester.tapAt(flatWheelRect.center + const Offset(10, -80));
    await tester.pumpAndSettle();
    expect(picked?.rootPc, 1);
    expect(picked?.quality, '');
    expect(picked?.symbol, 'C#');
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    semantics.dispose();
  });

  testWidgets('rebuilds degree labels and actions after wheel inputs change', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final originalPicks = <DiatonicTriad>[];
    final updatedPicks = <DiatonicTriad>[];
    final originalCallback = originalPicks.add;
    final updatedCallback = updatedPicks.add;

    await _pumpWheel(
      tester,
      viewportSize: const Size(320, 800),
      textScale: 1,
      onPick: originalCallback,
    );
    var previousPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
    expect(find.semantics.byLabel('I, C chord'), findsOneWidget);

    await _pumpWheel(
      tester,
      viewportSize: const Size(320, 800),
      textScale: 1,
      keyRootPc: 1,
      onPick: originalCallback,
    );
    var nextPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
    expect(
      previousPainter.painter!.shouldRebuildSemantics(nextPainter.painter!),
      isTrue,
    );
    expect(find.semantics.byLabel('I, C chord'), findsNothing);
    expect(find.semantics.byLabel('I, C# chord'), findsOneWidget);

    previousPainter = nextPainter;
    await _pumpWheel(
      tester,
      viewportSize: const Size(320, 800),
      textScale: 1,
      keyRootPc: 1,
      scaleName: 'minor',
      onPick: originalCallback,
    );
    nextPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
    expect(
      previousPainter.painter!.shouldRebuildSemantics(nextPainter.painter!),
      isTrue,
    );
    expect(find.semantics.byLabel('I, C# chord'), findsNothing);
    expect(find.semantics.byLabel('i, C#m chord'), findsOneWidget);

    previousPainter = nextPainter;
    await _pumpWheel(
      tester,
      viewportSize: const Size(320, 800),
      textScale: 1.6,
      keyRootPc: 1,
      scaleName: 'minor',
      textDirection: TextDirection.rtl,
      onPick: updatedCallback,
    );
    nextPainter = tester.widget<CustomPaint>(_wheelPainterFinder());
    expect(
      previousPainter.painter!.shouldRebuildSemantics(nextPainter.painter!),
      isTrue,
    );

    tester.semantics.tap(find.semantics.byLabel('i, C#m chord'));
    expect(originalPicks, isEmpty);
    expect(updatedPicks, hasLength(1));
    expect(updatedPicks.single.degree, 0);
    expect(updatedPicks.single.rootPc, 1);
    expect(updatedPicks.single.quality, 'm');
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    semantics.dispose();
  });
}
