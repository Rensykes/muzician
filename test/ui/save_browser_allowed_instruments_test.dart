import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/ui/save_browser_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('allowedInstruments restricts the picker to the listed types '
      'and hides songwriter + song saves', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.hydrate();
    await settings.setSaveBrowserGrid(false);

    final ss = container.read(saveSystemProvider.notifier);
    final folderId = ss.createSaveFolder('Mixed', null)!;

    // Allowed: fretboard.
    ss.saveSnapshot(
      'FretSave',
      folderId,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    );
    // Allowed: piano.
    ss.saveSnapshot(
      'PianoSave',
      folderId,
      PianoSnapshot(
        currentRange: PianoRangeName.key49,
        selectedKeys: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: PianoViewMode.exact,
      ),
    );
    // Excluded: songwriter (whole-arrangement save).
    ss.saveSnapshot(
      'SongwriterSave',
      folderId,
      const SongwriterProjectSnapshot(
        name: 'Some Song',
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        sections: [],
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SaveBrowserPanel(
            allowedInstruments: const {'fretboard', 'piano', 'piano_roll'},
            onPick: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mixed'));
    await tester.pumpAndSettle();

    expect(find.text('FretSave'), findsOneWidget);
    expect(find.text('PianoSave'), findsOneWidget);
    expect(find.text('SongwriterSave'), findsNothing,
        reason: 'songwriter saves must be hidden by the allowlist');
  });
}
