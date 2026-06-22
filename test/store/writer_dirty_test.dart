import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ProviderContainer seeded() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    return c;
  }

  String pid(ProviderContainer c) =>
      c.read(saveSystemProvider).selectedProjectId!;

  test('unbound empty project is not dirty', () {
    final c = seeded();
    expect(c.read(writerDirtyProvider), false);
  });

  test('unbound project with content is dirty', () {
    final c = seeded();
    c.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 4);
    expect(c.read(writerDirtyProvider), true);
  });

  test('bound and unchanged is not dirty', () {
    final c = seeded();
    c.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 4);
    final saveId = c
        .read(saveSystemProvider.notifier)
        .saveSnapshot('s1', pid(c), c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid(c), saveId);
    expect(c.read(writerDirtyProvider), false);
  });

  test('bound then edited is dirty', () {
    final c = seeded();
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final saveId = c
        .read(saveSystemProvider.notifier)
        .saveSnapshot('s1', pid(c), c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid(c), saveId);
    n.setTempo(200);
    expect(c.read(writerDirtyProvider), true);
  });

  test('bound but save deleted falls back to content check', () {
    final c = seeded();
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final saveId = c
        .read(saveSystemProvider.notifier)
        .saveSnapshot('s1', pid(c), c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid(c), saveId);
    c.read(saveSystemProvider.notifier).deleteSave(saveId);
    expect(c.read(writerDirtyProvider), true);
  });
}
