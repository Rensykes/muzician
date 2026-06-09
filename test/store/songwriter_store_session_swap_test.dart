import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switching project: outgoing persisted, incoming loaded from ProjectConfig', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(songwriterSessionsProvider.notifier).hydrate();

    final p1 = c.read(saveSystemProvider.notifier)
        .createProject('A', const ProjectConfig(tempo: 100))!;
    final p2 = c.read(saveSystemProvider.notifier)
        .createProject('B', const ProjectConfig(tempo: 80))!;

    c.read(saveSystemProvider.notifier).selectProject(p1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.read(songwriterProvider.notifier).setTempo(133);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    c.read(saveSystemProvider.notifier).selectProject(p2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Outgoing persisted: sessions[p1] has tempo 133.
    expect(c.read(songwriterSessionsProvider.notifier).get(p1)?.config.tempo, 133);
    // Incoming loaded: default for p2 (project tempo 80 seeded).
    expect(c.read(songwriterProvider).config.tempo, 80);
  });
}
