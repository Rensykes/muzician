/// SongNotePatternEditor – isolated piano-roll editor host for a NotePattern.
///
/// Creates an isolated [ProviderContainer] seeded from the pattern so that edits
/// never leak into the standalone Piano Roll screen.  On save the edited state
/// is converted back to a [NotePattern] and applied via [songProjectProvider].
///
/// The editor mounts the full [PianoRollScreenV2] shell (stack builder,
/// detection, hum recorder, transport, tools, snap, pitch range), but hides the
/// per-pattern scale picker — the scale is inherited from the song.  Save/Load
/// panels are also hidden because loading would smash the host pattern length.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_pattern_bridge_rules.dart' as bridge;
import '../../store/piano_roll_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';
import '../piano_roll/piano_roll_screen_v2.dart';

class _SeededPianoRollNotifier extends PianoRollNotifier {
  _SeededPianoRollNotifier(this.seedState);
  final PianoRollState seedState;

  @override
  PianoRollState build() => seedState;
}

class SongNotePatternEditor extends ConsumerStatefulWidget {
  final String clipId;
  final String patternId;

  const SongNotePatternEditor({
    super.key,
    required this.clipId,
    required this.patternId,
  });

  @override
  ConsumerState<SongNotePatternEditor> createState() =>
      _SongNotePatternEditorState();
}

class _SongNotePatternEditorState extends ConsumerState<SongNotePatternEditor> {
  ProviderContainer? _isolatedContainer;
  String _patternName = '';

  /// Snapshot of the pattern's per-pattern `highlightedNotes` taken at open
  /// time.  Preserved through save so the pattern keeps its own fallback when
  /// the song scale is cleared later.
  List<String> _patternHighlightFallback = const [];

  @override
  void dispose() {
    _isolatedContainer?.dispose();
    super.dispose();
  }

  void _ensureIsolatedContainer(NotePattern pattern, SongProject project) {
    if (_isolatedContainer != null) return;

    _patternName = pattern.name;
    _patternHighlightFallback = List<String>.from(pattern.highlightedNotes);

    final scale = _songScaleFromConfig(project.config);

    final seedState = bridge.pianoRollStateFromNotePattern(
      pattern,
      tempo: project.config.tempo,
      timeSignature: project.config.timeSignature,
      songHighlightedNotes: scale?.notes,
      songKey: scale?.label,
    );

    _isolatedContainer = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _SeededPianoRollNotifier(seedState),
        ),
      ],
    );
  }

  void _onSave() {
    final pianoRollState = _isolatedContainer!.read(pianoRollProvider);
    final project = ref.read(songProjectProvider);
    final currentPattern = project.notePatterns.firstWhere(
      (p) => p.id == widget.patternId,
    );
    final hasSongScale =
        project.config.scaleRoot != null && project.config.scaleName != null;
    final nextPattern = bridge.notePatternFromPianoRollState(
      pianoRollState,
      patternId: widget.patternId,
      patternName: _patternName,
      minimumLengthTicks: currentPattern.lengthTicks,
      highlightedNotesOverride: hasSongScale ? _patternHighlightFallback : null,
    );
    final applied = ref
        .read(songProjectProvider.notifier)
        .applyNotePattern(widget.patternId, nextPattern);
    if (!applied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pattern resize rejected because it would overlap another clip.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context);
  }

  void _onMakeUnique() {
    ref.read(songProjectProvider.notifier).makeClipPatternUnique(widget.clipId);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songProjectProvider);

    NotePattern pattern;
    try {
      project.clips.firstWhere((c) => c.id == widget.clipId);
      pattern = project.notePatterns.firstWhere(
        (p) => p.id == widget.patternId,
      );
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    _ensureIsolatedContainer(pattern, project);

    final usageCount = project.clips
        .where((c) => c.patternId == widget.patternId)
        .length;

    final songScale = _songScaleFromConfig(project.config);
    final scaleLabel = songScale?.label ?? 'No song scale';

    return Scaffold(
      backgroundColor: MuzicianTheme.surface,
      appBar: AppBar(
        backgroundColor: MuzicianTheme.surface,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _patternName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            Text(
              scaleLabel,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Text(
            'Used in $usageCount clips',
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _onMakeUnique,
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Make unique'),
            style: TextButton.styleFrom(
              foregroundColor: MuzicianTheme.textSecondary,
            ),
          ),
          TextButton.icon(
            onPressed: _onSave,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Save'),
            style: TextButton.styleFrom(foregroundColor: MuzicianTheme.sky),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: UncontrolledProviderScope(
        container: _isolatedContainer!,
        child: const PianoRollScreenV2(
          showScale: false,
          showSavePanels: false,
          showBackground: false,
        ),
      ),
    );
  }
}

/// Compact view-model derived from [SongProjectConfig.scaleRoot] /
/// [SongProjectConfig.scaleName].  Returns `null` when the song has no scale.
({String label, List<String> notes})? _songScaleFromConfig(
  SongProjectConfig config,
) {
  final root = config.scaleRoot;
  final name = config.scaleName;
  if (root == null || name == null) return null;
  final notes = getScaleNotes(root, name);
  if (notes.isEmpty) return null;
  final scaleLabel = scaleGroups.values
      .expand((v) => v)
      .firstWhere((s) => s.$1 == name, orElse: () => (name, name))
      .$2;
  return (label: '$root $scaleLabel', notes: notes);
}
