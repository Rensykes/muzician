/// Song Pattern Editor Launcher
/// Opens the appropriate pattern editor for a clip instance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import 'song_note_pattern_editor.dart';

/// Opens the pattern editor for [clip].
///
/// * [SongPatternType.note] → [SongNotePatternEditor] in full-screen dialog.
/// * [SongPatternType.drum] → no-op (drum editor not yet implemented).
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
  return Future.value();
}
