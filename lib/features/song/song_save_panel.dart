library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/save_system_store.dart';
import '../../store/song_project_store.dart';
import '../../ui/save_browser_panel.dart';

class SongSavePanel extends ConsumerWidget {
  const SongSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      return const _SongRequiresProjectPlaceholder();
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

class _SongRequiresProjectPlaceholder extends StatelessWidget {
  const _SongRequiresProjectPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Select a project to save / load songs',
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () { /* wired in Task 16 */ },
            child: const Text('Choose project'),
          ),
        ],
      ),
    );
  }
}
