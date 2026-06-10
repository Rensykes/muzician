/// Bottom-sheet host that edits a single Songwriter [DrumPattern] using the
/// generalized [DrumMachineEditorBody].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../store/songwriter_store.dart';
import '../song/drum_machine_editor.dart';
import '../_mockup_shell.dart';

Future<void> showSongwriterDrumPatternSheet({
  required BuildContext context,
  required String patternId,
}) {
  return showWidgetSheet(
    context: context,
    title: 'Drum Pattern',
    child: _Body(patternId: patternId),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.patternId});
  final String patternId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final pattern = project.drumPatterns.firstWhere(
      (p) => p.id == patternId,
      orElse: () => const DrumPattern(
        id: '',
        name: '',
        lengthTicks: 16,
        lanes: [],
      ),
    );
    if (pattern.id.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Pattern not found.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: DrumMachineEditorBody(
        key: Key('drumPatternBody_$patternId'),
        pattern: pattern,
        tempo: project.config.tempo,
        onChanged: (updated) {
          ref.read(songwriterProvider.notifier).updateDrumPattern(updated);
        },
      ),
    );
  }
}
