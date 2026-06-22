import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold start: first read of writer restores the selected project draft',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(songwriterSessionsProvider.notifier).hydrate();

    final p1 = c
        .read(saveSystemProvider.notifier)
        .createProject('A', const ProjectConfig(tempo: 100))!;

    // Project is selected and a working draft exists BEFORE the writer provider
    // is ever read — the cold-start path (no project-switch event fires).
    c.read(saveSystemProvider.notifier).selectProject(p1);
    c.read(songwriterSessionsProvider.notifier).put(
          p1,
          const SongwriterProjectSnapshot(
            name: 'A draft',
            config: SongwriterConfig(
              tempo: 155,
              beatsPerBar: 4,
              beatUnit: 4,
              keyRoot: 0,
              keyScaleName: 'major',
            ),
          ),
        );

    // First read must seed from the stored draft, not _emptyProject().
    expect(c.read(songwriterProvider).config.tempo, 155);
    expect(c.read(songwriterProvider).name, 'A draft');
  });

  test('cold start: no draft falls back to the project default config',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(songwriterSessionsProvider.notifier).hydrate();

    final p1 = c
        .read(saveSystemProvider.notifier)
        .createProject('A', const ProjectConfig(tempo: 90))!;
    c.read(saveSystemProvider.notifier).selectProject(p1);

    // No session stored → seed from the project's ProjectConfig (tempo 90).
    expect(c.read(songwriterProvider).config.tempo, 90);
  });
}
