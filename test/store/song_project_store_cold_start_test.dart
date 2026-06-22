import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/schema/rules/song_rules.dart' as rules;
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/song_sessions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold start: first read of song restores the selected project draft',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(songSessionsProvider.notifier).hydrate();

    final p1 = c
        .read(saveSystemProvider.notifier)
        .createProject('A', const ProjectConfig(tempo: 100))!;

    // Project is selected and a working draft exists BEFORE the song provider
    // is ever read — the cold-start path (no project-switch event fires).
    c.read(saveSystemProvider.notifier).selectProject(p1);
    final draft = rules.getDefaultSongProject().copyWith(
      config: rules.getDefaultSongProject().config.copyWith(tempo: 155),
    );
    c.read(songSessionsProvider.notifier).put(p1, draft);

    // First read must seed from the stored draft, not the default project.
    expect(c.read(songProjectProvider).config.tempo, 155);
  });

  test('cold start: no draft falls back to the project default config',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(songSessionsProvider.notifier).hydrate();

    final p1 = c
        .read(saveSystemProvider.notifier)
        .createProject('A', const ProjectConfig(tempo: 90))!;
    c.read(saveSystemProvider.notifier).selectProject(p1);

    // No session stored → seed from the project's ProjectConfig (tempo 90).
    expect(c.read(songProjectProvider).config.tempo, 90);
  });
}
