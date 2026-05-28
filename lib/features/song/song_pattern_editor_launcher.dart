/// Song Pattern Editor Launcher
/// Opens the appropriate pattern editor for a clip instance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import 'drum_machine_editor.dart';
import 'song_note_pattern_editor.dart';

/// Opens the pattern editor for [clip].
///
/// * [SongPatternType.note] → [SongNotePatternEditor] in full-screen dialog.
/// * [SongPatternType.drum] → [DrumMachineEditor] in full-screen dialog.
Future<void> openClipEditor(
  BuildContext context,
  WidgetRef ref,
  SongClipInstance clip,
) {
  if (clip.patternType == SongPatternType.note) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            SongNotePatternEditor(clipId: clip.id, patternId: clip.patternId),
      ),
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          DrumMachineEditor(clipId: clip.id, patternId: clip.patternId),
    ),
  );
}
