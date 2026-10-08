/// Watches the active project's [ProjectConfig] and pushes its key /
/// tempo / time-signature into every instrument's live store.
///
/// Single source of truth for project-driven config: when the user picks a
/// different project, or edits the active project's config sheet, this sync
/// fires and every tab's in-memory state catches up immediately.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/piano_roll.dart' show TimeSignature;
import '../models/project_config.dart';
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
final activeProjectKeyProvider = Provider<({String root, String scaleName})?>((
  ref,
) {
  final folder = ref.watch(selectedProjectProvider);
  if (folder == null || folder.kind != SaveFolderKind.project) return null;
  final cfg = folder.projectConfig;
  if (cfg == null) return null;
  final rootPc = cfg.keyRootPc;
  final scaleName = cfg.keyScaleName;
  if (rootPc == null || scaleName == null || rootPc < 0 || rootPc >= 12) {
    return null;
  }
  return (root: chromaticNotes[rootPc], scaleName: scaleName);
});

/// Mount once on app start (read it from `main.dart`). The provider has no
/// state — its body wires the listeners.
final projectConfigSyncProvider = Provider<void>((ref) {
  var revision = 0;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  ref.listen<SaveFolder?>(selectedProjectProvider, (prev, next) {
    // Defer state mutations so they don't happen during this provider's
    // build phase — Riverpod forbids modifying other providers on build.
    final scheduledRevision = ++revision;
    Future.microtask(() {
      if (disposed || scheduledRevision != revision) return;
      final current = ref.read(selectedProjectProvider);
      if (!_sameSelection(current, next)) return;
      _apply(ref, next);
    });
  }, fireImmediately: true);
});

void _apply(Ref ref, SaveFolder? folder) {
  if (folder == null || folder.kind != SaveFolderKind.project) {
    _clearProjectKeyContext(ref);
    return;
  }
  final cfg = folder.projectConfig ?? const ProjectConfig();

  final rootPc = cfg.keyRootPc;
  final scaleName = cfg.keyScaleName;
  final hasKey =
      rootPc != null &&
      rootPc >= 0 &&
      rootPc < chromaticNotes.length &&
      scaleName != null;
  final scaleNotes = hasKey
      ? _scaleNotesFor(rootPc, scaleName)
      : const <String>[];
  final keyString = hasKey ? chromaticNotes[rootPc] : null;
  final activeScale = hasKey
      ? (root: chromaticNotes[rootPc], scaleName: scaleName)
      : null;

  // Fretboard + Piano live highlight
  ref.read(fretboardProvider.notifier).setHighlightedNotes(scaleNotes);
  ref.read(pianoProvider.notifier).setHighlightedNotes(scaleNotes);
  ref.read(activeScaleProvider.notifier).state = activeScale;
  ref.read(pendingScaleProvider.notifier).state = null;
  ref.read(pianoActiveScaleProvider.notifier).state = activeScale;
  ref.read(pianoPendingScaleProvider.notifier).state = null;

  // Piano Roll: config + highlight
  final roll = ref.read(pianoRollProvider.notifier);
  roll.setTempo(cfg.tempo);
  roll.setTimeSignature(
    TimeSignature(beatsPerMeasure: cfg.beatsPerBar, beatUnit: cfg.beatUnit),
  );
  roll.setKey(keyString);
  roll.setHighlightedNotes(scaleNotes);
  ref.read(pianoRollActiveScaleProvider.notifier).state = activeScale;
  ref.read(pianoRollPendingScaleProvider.notifier).state = null;

  // Song
  final song = ref.read(songProjectProvider.notifier);
  song.syncProjectConfig(
    tempo: cfg.tempo,
    timeSignature: TimeSignature(
      beatsPerMeasure: cfg.beatsPerBar,
      beatUnit: cfg.beatUnit,
    ),
    scaleRoot: keyString,
    scaleName: cfg.keyScaleName,
  );

  // Songwriter
  final writer = ref.read(songwriterProvider.notifier);
  writer.syncProjectConfig(
    tempo: cfg.tempo,
    beatsPerBar: cfg.beatsPerBar,
    beatUnit: cfg.beatUnit,
    keyRoot: hasKey ? rootPc : null,
    keyScaleName: hasKey ? scaleName : null,
  );
}

void _clearProjectKeyContext(Ref ref) {
  ref.read(fretboardProvider.notifier).setHighlightedNotes(const []);
  ref.read(pianoProvider.notifier).setHighlightedNotes(const []);
  ref.read(activeScaleProvider.notifier).state = null;
  ref.read(pendingScaleProvider.notifier).state = null;
  ref.read(pianoActiveScaleProvider.notifier).state = null;
  ref.read(pianoPendingScaleProvider.notifier).state = null;

  final roll = ref.read(pianoRollProvider.notifier);
  roll.setKey(null);
  roll.setHighlightedNotes(const []);
  ref.read(pianoRollActiveScaleProvider.notifier).state = null;
  ref.read(pianoRollPendingScaleProvider.notifier).state = null;

  final songState = ref.read(songProjectProvider);
  final songConfig = songState.config;
  ref
      .read(songProjectProvider.notifier)
      .syncProjectConfig(
        tempo: songConfig.tempo,
        timeSignature: songConfig.timeSignature,
        scaleRoot: null,
        scaleName: null,
      );

  final writerConfig = ref.read(songwriterProvider).config;
  ref
      .read(songwriterProvider.notifier)
      .syncProjectConfig(
        tempo: writerConfig.tempo,
        beatsPerBar: writerConfig.beatsPerBar,
        beatUnit: writerConfig.beatUnit,
        keyRoot: null,
        keyScaleName: null,
      );
}

bool _sameSelection(SaveFolder? current, SaveFolder? expected) {
  if (current?.id != expected?.id || current?.kind != expected?.kind) {
    return false;
  }
  final currentConfig = current?.projectConfig;
  final expectedConfig = expected?.projectConfig;
  if (currentConfig == null || expectedConfig == null) {
    return currentConfig == null && expectedConfig == null;
  }
  return currentConfig.keyRootPc == expectedConfig.keyRootPc &&
      currentConfig.keyScaleName == expectedConfig.keyScaleName &&
      currentConfig.tempo == expectedConfig.tempo &&
      currentConfig.beatsPerBar == expectedConfig.beatsPerBar &&
      currentConfig.beatUnit == expectedConfig.beatUnit &&
      currentConfig.defaultHarmonyInstrument ==
          expectedConfig.defaultHarmonyInstrument;
}

List<String> _scaleNotesFor(int? rootPc, String? scaleName) {
  if (rootPc == null ||
      rootPc < 0 ||
      rootPc >= chromaticNotes.length ||
      scaleName == null) {
    return const [];
  }
  final intervals = scaleIntervals[scaleName];
  if (intervals == null) return const [];
  return intervals.map((i) => chromaticNotes[(rootPc + i) % 12]).toList();
}
