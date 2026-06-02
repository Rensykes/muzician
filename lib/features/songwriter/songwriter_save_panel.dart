import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../ui/save_browser_panel.dart';

/// Save / load panel for Songwriter projects. Wraps the shared save browser
/// filtered to `'songwriter'` snapshots. Capturing returns the current project
/// (the store's state IS the snapshot); loading replaces the active project.
class SongwriterSavePanel extends ConsumerWidget {
  const SongwriterSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    return SaveBrowserPanel(
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

@visibleForTesting
SongwriterProjectSnapshot songwriterCaptureForTest(ProviderContainer c) =>
    c.read(songwriterProvider);
