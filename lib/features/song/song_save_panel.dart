library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/song_project_store.dart';
import '../../ui/save_tree_browser.dart';

class SongSavePanel extends ConsumerWidget {
  const SongSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SaveTreeBrowser(
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
