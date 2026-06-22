import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../store/writer_save_binding_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';

/// Save / load panel for Songwriter projects. Wraps the shared save browser
/// filtered to `'songwriter'` snapshots. Capturing returns the current project
/// (the store's state IS the snapshot); loading replaces the active project.
class SongwriterSavePanel extends ConsumerWidget {
  const SongwriterSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      return const ProjectRequiredPlaceholder(
        message: 'Songwriter needs a real project.\nDump is not allowed here.',
        allowDump: false,
      );
    }
    final notifier = ref.read(songwriterProvider.notifier);
    return SaveBrowserPanel(
      rootFolderId: selected.id,
      instrumentFilter: 'songwriter',
      captureSnapshot: () => ref.read(songwriterProvider),
      onLoad: (snapshot) {
        if (snapshot is SongwriterProjectSnapshot) {
          notifier.loadProject(snapshot);
        }
      },
      onLoadSaveId: (saveId) => ref
          .read(writerSaveBindingProvider.notifier)
          .bind(selected.id, saveId),
      onSaved: (saveId) =>
          ref.read(writerSaveBindingProvider.notifier).bind(selected.id, saveId),
    );
  }
}

@visibleForTesting
SongwriterProjectSnapshot songwriterCaptureForTest(ProviderContainer c) =>
    c.read(songwriterProvider);
