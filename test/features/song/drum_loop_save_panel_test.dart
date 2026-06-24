import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/song/drum_loop_save_panel.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/ui/project_required_placeholder.dart';
import 'package:muzician/ui/save_browser_panel.dart';

DrumPattern _pattern() => const DrumPattern(
  id: 'd1',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
);

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: DrumLoopSavePanel(
            currentPattern: _pattern(),
            onApply: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows a project-required placeholder when no project selected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.byType(ProjectRequiredPlaceholder), findsOneWidget);
    expect(find.byType(SaveBrowserPanel), findsNothing);
  });

  testWidgets('renders the save browser when a project is selected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(saveSystemProvider.notifier);
    final projectId = notifier.createProject('Demo', const ProjectConfig());
    notifier.selectProject(projectId);

    await _pump(tester, container);

    expect(find.byType(SaveBrowserPanel), findsOneWidget);
    expect(find.byType(ProjectRequiredPlaceholder), findsNothing);
  });
}
