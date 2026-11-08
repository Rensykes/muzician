/// Save / load panel for reusable drum loops. Wraps the shared save browser
/// filtered to `'drum_loop'` snapshots: capturing saves the current pattern,
/// loading applies the loop back into the editor via [onApply].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../store/save_system_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';
import '../_mockup_shell.dart';

/// Opens the drum-loop library as a bottom sheet.
Future<void> showDrumLoopLibrarySheet({
  required BuildContext context,
  required DrumPattern currentPattern,
  required void Function(DrumPattern pattern) onApply,
}) {
  return showWidgetSheet(
    context: context,
    title: 'My Loops',
    child: DrumLoopSavePanel(currentPattern: currentPattern, onApply: onApply),
  );
}

class DrumLoopSavePanel extends ConsumerWidget {
  const DrumLoopSavePanel({
    super.key,
    required this.currentPattern,
    required this.onApply,
  });

  /// The pattern captured when the user saves a new loop.
  final DrumPattern currentPattern;

  /// Called with a loaded loop's pattern so the editor can apply it.
  final void Function(DrumPattern pattern) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      return const ProjectRequiredPlaceholder(
        message: 'Drum loops need a real project.\nDump is not allowed here.',
        allowDump: false,
      );
    }
    return SaveBrowserPanel(
      rootFolderId: selected.id,
      instrumentFilter: 'drum_loop',
      captureSnapshot: () => DrumLoopSnapshot(pattern: currentPattern),
      onLoad: (snapshot) {
        if (snapshot is DrumLoopSnapshot) onApply(snapshot.pattern);
      },
    );
  }
}
