import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/save_system.dart';
import 'songwriter_melody_performance_editor.dart';
import 'songwriter_screen_sheet.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({
    super.key,
    this.onEditInstrumentSave,
    this.onEditMelodyPerformance,
  });

  final ValueChanged<SaveEntry>? onEditInstrumentSave;
  final ValueChanged<String>? onEditMelodyPerformance;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SongwriterScreenSheet(
    onEditInstrumentSave: onEditInstrumentSave,
    onEditMelodyPerformance:
        onEditMelodyPerformance ??
        (patternId) => showSongwriterMelodyPerformanceEditor(
          context: context,
          patternId: patternId,
        ),
  );
}
