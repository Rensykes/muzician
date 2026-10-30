import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/scaled_instrument_board.dart';

void main() {
  group('dockCanvasScale', () {
    for (final (height, expected) in const [
      (600.0, 1.0),
      (640.0, 1.0),
      (840.0, 1.125),
      (1040.0, 1.25),
      (1400.0, 1.25),
    ]) {
      test('$height -> $expected', () {
        expect(dockCanvasScale(height), closeTo(expected, 1e-9));
      });
    }
  });

  testWidgets('scales child to fill width and maps taps to child space', (
    tester,
  ) async {
    Offset? tapped;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 500,
            height: 250,
            child: ScaledInstrumentBoard(
              scale: 1.25,
              baseHeight: 200,
              child: GestureDetector(
                key: const Key('board'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => tapped = details.localPosition,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    // Child is laid out at 400x200 logical and painted at 500x250.
    expect(
      tester.getSize(find.byKey(const Key('board'))),
      const Size(400, 200),
    );
    expect(
      tester.getRect(find.byKey(const Key('board'))),
      const Rect.fromLTWH(0, 0, 500, 250),
    );

    await tester.tapAt(const Offset(250, 125));
    expect(tapped, isNotNull);
    expect(tapped!.dx, closeTo(200, 0.01));
    expect(tapped!.dy, closeTo(100, 0.01));
  });

  testWidgets('scale 1.0 is an identity layout', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 120,
            child: ScaledInstrumentBoard(
              scale: 1,
              baseHeight: 120,
              child: SizedBox.expand(key: Key('board')),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('board'))),
      const Size(300, 120),
    );
  });
}
