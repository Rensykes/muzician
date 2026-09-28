import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Edit in Piano passes the canonical SaveEntry to its caller', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saves = container.read(saveSystemProvider.notifier);
    final projectId = saves.createProject('Project', const ProjectConfig())!;
    saves.selectProject(projectId);
    final saveId = saves.saveSnapshot(
      'Piano voicing',
      projectId,
      PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: const [],
        selectedNotes: const ['C4', 'E4', 'G4'],
        viewMode: PianoViewMode.exact,
      ),
    )!;
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    notifier.addLibraryBlockAt(
      sectionId: sectionId,
      saveId: saveId,
      startBar: 0,
    );
    await notifier.reconcileCurrentProject();
    final canonical = container
        .read(saveSystemProvider)
        .saves
        .singleWhere((entry) => entry.id == saveId);
    final saveBlock = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((lane) => lane.kind == SongLaneKind.save)
        .blocks
        .single;
    SaveEntry? received;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterScreenSheet(
              onEditInstrumentSave: (entry) => received = entry,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('saveCell_${saveBlock.id}_0')));
    await tester.pumpAndSettle();
    expect(find.text('Edit in Piano'), findsOneWidget);
    await tester.tap(find.byKey(const Key('barActionEditInstrument')));
    await tester.pumpAndSettle();

    expect(identical(received, canonical), isTrue);
  });
}
