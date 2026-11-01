import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: StudioTheme.data(AppThemeVariant.studio),
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('secondary mouse button does not toggle a fret cell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(fretboardProvider.notifier);
    // Empty highlights make `_guardOutOfKey` confirm immediately, so a
    // primary tap toggles the cell instead of opening the out-of-key dialog.
    notifier.setHighlightedNotes([]);
    notifier.setCapo(2);
    notifier.toggleCell(0, 2, 'F#');

    await tester.pumpWidget(
      _host(container, const GuitarFretboard(hideToolbar: true)),
    );
    await tester.pumpAndSettle();

    final paintFinder = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_FretboardPainter',
    );
    // Cell (string 0, fret 2) paints at local (190, 36) with capo 2.
    final cellPoint =
        tester.getRect(paintFinder).topLeft + const Offset(190, 36);

    final gesture = await tester.startGesture(
      cellPoint,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final cells = container.read(fretboardProvider).selectedCells;
    expect(
      cells.any((cell) => cell.stringIndex == 0 && cell.fret == 2),
      isTrue,
      reason: 'A right-click must not toggle the cell off',
    );
  });
}
