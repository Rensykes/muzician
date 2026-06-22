import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/app_bootstrap.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup restore: a saved Writer draft survives the hydrate sequence',
      () async {
    // ── Phase A: a prior run that selected a project and added a section. ──
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c0 = ProviderContainer();
    await c0.read(saveSystemProvider.notifier).hydrate();
    await c0.read(songwriterSessionsProvider.notifier).hydrate();
    final pid = c0
        .read(saveSystemProvider.notifier)
        .createProject('Vorrei', const ProjectConfig())!;
    c0.read(saveSystemProvider.notifier).selectProject(pid);
    c0.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 4);
    // Let the debounced persists flush to (mock) SharedPreferences.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final prefs = await SharedPreferences.getInstance();
    final saveBlob = prefs.getString('@muzician/save-system/v3')!;
    final sessBlob = prefs.getString('@muzician/songwriter_sessions/v1')!;
    c0.dispose();

    // ── Phase B: relaunch — the writer provider is alive (IndexedStack builds
    // it eagerly) BEFORE the stores hydrate, exactly as in the app shell. ──
    SharedPreferences.setMockInitialValues(<String, Object>{
      '@muzician/save-system/v3': saveBlob,
      '@muzician/songwriter_sessions/v1': sessBlob,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    // Registers the project-selection listener before any hydrate runs.
    c.read(songwriterProvider);

    await hydrateStores(c.read);

    expect(c.read(saveSystemProvider).selectedProjectId, pid);
    expect(c.read(songwriterProvider).sections, isNotEmpty);
  });
}
