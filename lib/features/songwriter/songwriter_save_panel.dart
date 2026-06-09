import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
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
      return const _SongwriterRequiresProjectPlaceholder();
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
    );
  }
}

class _SongwriterRequiresProjectPlaceholder extends StatelessWidget {
  const _SongwriterRequiresProjectPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Select a project to save / load arrangements',
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

@visibleForTesting
SongwriterProjectSnapshot songwriterCaptureForTest(ProviderContainer c) =>
    c.read(songwriterProvider);
