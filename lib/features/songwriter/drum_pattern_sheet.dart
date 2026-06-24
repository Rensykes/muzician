/// Bottom-sheet host that edits a single Songwriter [DrumPattern] using the
/// generalized [DrumMachineEditorBody].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_playback_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../store/drum_pattern_playback_store.dart' show DrumBackingDescriptor;
import '../song/drum_machine_editor.dart';
import '../_mockup_shell.dart';

Future<void> showSongwriterDrumPatternSheet({
  required BuildContext context,
  required String patternId,
  String? sectionId,
}) {
  return showWidgetSheet(
    context: context,
    title: 'Drum Pattern',
    child: _Body(patternId: patternId, sectionId: sectionId),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.patternId, this.sectionId});
  final String patternId;
  final String? sectionId;

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

    // Compute the looping harmony bed from the section this sheet was opened
    // from. Null when there is no section context or the section has no chords.
    final backing = _backingFor(ref, project);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: DrumMachineEditorBody(
        key: Key('drumPatternBody_$patternId'),
        pattern: pattern,
        tempo: project.config.tempo,
        backing: backing,
        onChanged: (updated) {
          ref.read(songwriterProvider.notifier).updateDrumPattern(updated);
        },
      ),
    );
  }

  DrumBackingDescriptor? _backingFor(
    WidgetRef ref,
    SongwriterProjectSnapshot project,
  ) {
    final id = sectionId;
    if (id == null) return null;
    SongSection? section;
    for (final s in project.sections) {
      if (s.id == id) {
        section = s;
        break;
      }
    }
    if (section == null) return null;
    final saves = ref.watch(saveSystemProvider).saves;
    final loop = sectionHarmonyLoop(section, project.config, saves);
    if (loop.notesByTick.isEmpty) return null;
    return loop;
  }
}
