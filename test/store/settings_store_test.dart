import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/guitar_sound.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('guitar tone persists independently of the other settings', () async {
    final first = ProviderContainer();
    await first.read(settingsProvider.notifier).setNoteVolume(0.4);
    await first
        .read(settingsProvider.notifier)
        .setGuitarTone(GuitarTone.distorted);
    expect(first.read(settingsProvider).guitarTone, GuitarTone.distorted);
    expect(first.read(settingsProvider).noteVolume, 0.4);
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(settingsProvider.notifier).hydrate();
    expect(restored.read(settingsProvider).guitarTone, GuitarTone.distorted);
    expect(restored.read(settingsProvider).noteVolume, 0.4);
  });

  test('setSaveBrowserGrid updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setSaveBrowserGrid(true);
    expect(container.read(settingsProvider).saveBrowserGrid, true);
  });

  test('setDefaultNewProjectHarmonyInstrument persists the choice', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .setDefaultNewProjectHarmonyInstrument(HarmonyLaneInstrument.piano);

    expect(
      container.read(settingsProvider).defaultNewProjectHarmonyInstrument,
      HarmonyLaneInstrument.piano,
    );
  });

  test('setNoteSpelling persists and reloads the preference', () async {
    final first = ProviderContainer();
    await first
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    expect(first.read(settingsProvider).noteSpelling, NoteSpelling.flats);
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(settingsProvider.notifier).hydrate();
    expect(restored.read(settingsProvider).noteSpelling, NoteSpelling.flats);
  });

  test('theme preference persists and rehydrates other settings', () async {
    final first = ProviderContainer();
    await first
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    await first.read(settingsProvider.notifier).setSaveBrowserGrid(true);
    await first
        .read(settingsProvider.notifier)
        .setThemeVariant(AppThemeVariant.studioMuzician);

    final changed = first.read(settingsProvider);
    expect(changed.themeVariant, AppThemeVariant.studioMuzician);
    expect(changed.noteSpelling, NoteSpelling.flats);
    expect(changed.saveBrowserGrid, true);
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(settingsProvider.notifier).hydrate();

    final hydrated = restored.read(settingsProvider);
    expect(hydrated.themeVariant, AppThemeVariant.studioMuzician);
    expect(hydrated.noteSpelling, NoteSpelling.flats);
    expect(hydrated.saveBrowserGrid, true);
  });

  test('rapid theme changes persist the latest selection', () async {
    final first = ProviderContainer();
    await Future.wait([
      first
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studioMuzician),
      first
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studio),
    ]);
    expect(first.read(settingsProvider).themeVariant, AppThemeVariant.studio);
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(settingsProvider.notifier).hydrate();
    expect(
      restored.read(settingsProvider).themeVariant,
      AppThemeVariant.studio,
    );
  });
}
