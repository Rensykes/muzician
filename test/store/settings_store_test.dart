import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setSaveBrowserGrid updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setSaveBrowserGrid(true);
    expect(container.read(settingsProvider).saveBrowserGrid, true);
  });
}
