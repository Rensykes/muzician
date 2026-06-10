library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/save_system_store.dart';
import '../../store/song_project_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';

class SongSavePanel extends ConsumerWidget {
  const SongSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      return const ProjectRequiredPlaceholder(
        message: 'Song needs a real project.\nDump is not allowed here.',
        allowDump: false,
      );
    }
    return SaveBrowserPanel(
      rootFolderId: selected.id,
      instrumentFilter: 'song',
      captureSnapshot: () =>
          SongProjectSnapshot(project: ref.read(songProjectProvider)),
      onLoad: (snap) {
        if (snap is SongProjectSnapshot) {
          ref.read(songProjectProvider.notifier).loadProject(snap.project);
        }
      },
    );
  }
}
