library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'save_system_store.dart';
import 'settings_store.dart';
import 'song_sessions_store.dart';
import 'songwriter_sessions_store.dart';
import 'writer_save_binding_store.dart';

/// A reader compatible with both [WidgetRef.read] and [ProviderContainer.read],
/// so the bootstrap can run from the app shell and from tests.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Hydrates the persisted stores and restores the active project selection.
///
/// Order matters. The per-project session stores and the writer save bindings
/// are hydrated BEFORE [saveSystemProvider]. Hydrating the save system restores
/// `selectedProjectId`, which fires the project-selection listeners that load
/// each feature's session for that project — and those listeners read the
/// session maps. Hydrating the save system last left the listeners reading
/// empty maps, so a project opened with a blank session instead of its draft.
Future<void> hydrateStores(ProviderReader read) async {
  await read(settingsProvider.notifier).hydrate();
  await read(songSessionsProvider.notifier).hydrate();
  await read(songwriterSessionsProvider.notifier).hydrate();
  await read(writerSaveBindingProvider.notifier).hydrate();
  // Last: selecting the restored project fires session listeners that need the
  // maps above already populated.
  await read(saveSystemProvider.notifier).hydrate();

  final notifier = read(saveSystemProvider.notifier);
  final selected = read(saveSystemProvider).selectedProjectId;
  // First launch (or selection cleared): default to Dump so the user can create
  // saves freely on Fretboard / Piano / Roll without a forced project modal.
  // Song / Songwriter still prompt when entered because Dump is not a project.
  notifier.selectProject(selected ?? notifier.ensureDumpFolder());
}
