import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = '@muzician/writer_save_bindings/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('bind sets activeSaveId and resets alwaysOverwrite', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(writerSaveBindingProvider.notifier);
    n.setAlwaysOverwrite('p', true);
    n.bind('p', 'save1');
    final b = c.read(writerSaveBindingProvider)['p']!;
    expect(b.activeSaveId, 'save1');
    expect(b.alwaysOverwrite, false);
  });

  test('setAlwaysOverwrite keeps activeSaveId', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(writerSaveBindingProvider.notifier);
    n.bind('p', 'save1');
    n.setAlwaysOverwrite('p', true);
    final b = c.read(writerSaveBindingProvider)['p']!;
    expect(b.activeSaveId, 'save1');
    expect(b.alwaysOverwrite, true);
  });

  test('clear removes binding', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(writerSaveBindingProvider.notifier);
    n.bind('p', 'save1');
    n.clear('p');
    expect(c.read(writerSaveBindingProvider)['p'], isNull);
  });

  test('persist + rehydrate round-trip', () async {
    var c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(writerSaveBindingProvider.notifier).bind('p', 'save1');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect((await SharedPreferences.getInstance()).getString(_key), isNotNull);
    c.dispose();
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(writerSaveBindingProvider.notifier).hydrate();
    expect(c.read(writerSaveBindingProvider)['p']?.activeSaveId, 'save1');
  });
}
