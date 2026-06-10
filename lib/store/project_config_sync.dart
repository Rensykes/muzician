/// Watches the active project's [ProjectConfig] and pushes its key /
/// tempo / time-signature into every instrument's live store.
///
/// Single source of truth for project-driven config: when the user picks a
/// different project, or edits the active project's config sheet, this sync
/// fires and every tab's in-memory state catches up immediately.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/piano_roll.dart' show TimeSignature;
import '../models/save_system.dart';
import '../store/fretboard_store.dart';
import '../store/piano_roll_store.dart';
import '../store/piano_store.dart';
import '../store/save_system_store.dart';
import '../store/song_project_store.dart';
import '../store/songwriter_store.dart';
import '../utils/note_utils.dart';

/// Returns the active project's key (`root` pitch-class name, `scaleName`)
/// when the selected save folder is a project with a key configured.
///
/// Returns `null` outside a project context or when no key has been set.
final activeProjectKeyProvider =
    Provider<({String root, String scaleName})?>((ref) {
      final folder = ref.watch(selectedProjectProvider);
      if (folder == null || folder.kind != SaveFolderKind.project) return null;
      final cfg = folder.projectConfig;
      if (cfg == null) return null;
      final rootPc = cfg.keyRootPc;
      final scaleName = cfg.keyScaleName;
      if (rootPc == null || scaleName == null) return null;
      return (root: chromaticNotes[rootPc], scaleName: scaleName);
    });

/// Mount once on app start (read it from `main.dart`). The provider has no
/// state — its body wires the listeners.
final projectConfigSyncProvider = Provider<void>((ref) {
  ref.listen<SaveFolder?>(selectedProjectProvider, (prev, next) {
    // Defer state mutations so they don't happen during this provider's
    // build phase — Riverpod forbids modifying other providers on build.
    Future.microtask(() => _apply(ref, next));
  }, fireImmediately: true);
});

void _apply(Ref ref, SaveFolder? folder) {
  if (folder == null || folder.kind != SaveFolderKind.project) return;
  final cfg = folder.projectConfig;
  if (cfg == null) return;

  final scaleNotes = _scaleNotesFor(cfg.keyRootPc, cfg.keyScaleName);
  final keyString = cfg.keyRootPc == null
      ? null
      : chromaticNotes[cfg.keyRootPc!];

  // Fretboard + Piano live highlight
  ref.read(fretboardProvider.notifier).setHighlightedNotes(scaleNotes);
  ref.read(pianoProvider.notifier).setHighlightedNotes(scaleNotes);

  // Piano Roll: config + highlight
  final roll = ref.read(pianoRollProvider.notifier);
  roll.setTempo(cfg.tempo);
  roll.setTimeSignature(
    TimeSignature(beatsPerMeasure: cfg.beatsPerBar, beatUnit: cfg.beatUnit),
  );
  roll.setKey(keyString);
  roll.setHighlightedNotes(scaleNotes);

  // Song
  final song = ref.read(songProjectProvider.notifier);
  song.setTempo(cfg.tempo);
  song.setTimeSignature(
    TimeSignature(beatsPerMeasure: cfg.beatsPerBar, beatUnit: cfg.beatUnit),
  );
  song.setScale(root: keyString, scaleName: cfg.keyScaleName);

  // Songwriter
  final writer = ref.read(songwriterProvider.notifier);
  writer.setTempo(cfg.tempo);
  writer.setKey(cfg.keyRootPc, cfg.keyScaleName);
}

List<String> _scaleNotesFor(int? rootPc, String? scaleName) {
  if (rootPc == null || scaleName == null) return const [];
  final intervals = scaleIntervals[scaleName];
  if (intervals == null) return const [];
  return intervals.map((i) => chromaticNotes[(rootPc + i) % 12]).toList();
}
