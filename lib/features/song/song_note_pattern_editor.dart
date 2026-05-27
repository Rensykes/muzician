/// SongNotePatternEditor – isolated piano-roll editor host for a NotePattern.
///
/// Creates an isolated [ProviderContainer] seeded from the pattern so that edits
/// never leak into the standalone Piano Roll screen.  On save the edited state
/// is converted back to a [NotePattern] and applied via [songProjectProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_pattern_bridge_rules.dart' as bridge;
import '../../store/piano_roll_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../piano_roll/piano_roll_detection_panel.dart';
import '../piano_roll/piano_roll_grid.dart';

// ── Seeded PianoRollNotifier ──────────────────────────────────────────────────

class _SeededPianoRollNotifier extends PianoRollNotifier {
  _SeededPianoRollNotifier(this.seedState);
  final PianoRollState seedState;

  @override
  PianoRollState build() => seedState;
}

// ── Editor Widget ─────────────────────────────────────────────────────────────

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

  @override
  void dispose() {
    _isolatedContainer?.dispose();
    super.dispose();
  }

  void _ensureIsolatedContainer(NotePattern pattern, SongProject project) {
    if (_isolatedContainer != null) return;

    _patternName = pattern.name;

    final seedState = bridge.pianoRollStateFromNotePattern(
      pattern,
      tempo: project.config.tempo,
      timeSignature: project.config.timeSignature,
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
    final nextPattern = bridge.notePatternFromPianoRollState(
      pianoRollState,
      patternId: widget.patternId,
      patternName: _patternName,
    );
    ref
        .read(songProjectProvider.notifier)
        .applyNotePattern(widget.patternId, nextPattern);
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
      // Verify clip exists (will throw if missing).
      project.clips.firstWhere((c) => c.id == widget.clipId);
      pattern = project.notePatterns.firstWhere(
        (p) => p.id == widget.patternId,
      );
    } catch (_) {
      // Clip or pattern removed concurrently — pop back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    _ensureIsolatedContainer(pattern, project);

    final usageCount = project.clips
        .where((c) => c.patternId == widget.patternId)
        .length;

    return Scaffold(
      backgroundColor: MuzicianTheme.surface,
      appBar: AppBar(
        backgroundColor: MuzicianTheme.surface,
        title: Text(
          _patternName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
        child: Column(
          children: [
            const Expanded(child: PianoRollGrid()),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: PianoRollDetectionPanel(),
            ),
          ],
        ),
      ),
    );
  }
}
