/// Isolated Piano Roll editor host for one Writer melody pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/song_pattern_bridge_rules.dart' as bridge;
import '../../store/piano_roll_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../piano_roll/piano_roll_screen_v2.dart';

/// Identifies the one just-created Writer placement eligible for its initial
/// Piano Roll duration expansion. Existing-pattern editors should omit it.
class SongwriterMelodyInitialPlacement {
  const SongwriterMelodyInitialPlacement({
    required this.sectionId,
    required this.laneId,
    required this.blockId,
  });

  final String sectionId;
  final String laneId;
  final String blockId;
}

class _SeededPianoRollNotifier extends PianoRollNotifier {
  _SeededPianoRollNotifier(this.seedState);
  final PianoRollState seedState;

  @override
  PianoRollState build() => seedState;
}

Future<void> showSongwriterMelodyPatternEditor({
  required BuildContext context,
  required String patternId,
  SongwriterMelodyInitialPlacement? initialPlacement,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _SongwriterMelodyPatternEditor(
      patternId: patternId,
      initialPlacement: initialPlacement,
    ),
  ),
);

class _SongwriterMelodyPatternEditor extends ConsumerStatefulWidget {
  const _SongwriterMelodyPatternEditor({
    required this.patternId,
    this.initialPlacement,
  });

  final String patternId;
  final SongwriterMelodyInitialPlacement? initialPlacement;

  @override
  ConsumerState<_SongwriterMelodyPatternEditor> createState() =>
      _SongwriterMelodyPatternEditorState();
}

class _SongwriterMelodyPatternEditorState
    extends ConsumerState<_SongwriterMelodyPatternEditor> {
  ProviderContainer? _isolatedContainer;

  @override
  void dispose() {
    _isolatedContainer?.dispose();
    super.dispose();
  }

  void _ensureContainer(NotePattern pattern, SongwriterConfig config) {
    if (_isolatedContainer != null) return;
    final seedState = bridge.pianoRollStateFromNotePattern(
      pattern,
      tempo: config.tempo,
      timeSignature: TimeSignature(
        beatsPerMeasure: config.beatsPerBar,
        beatUnit: config.beatUnit,
      ),
    );
    _isolatedContainer = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _SeededPianoRollNotifier(seedState),
        ),
      ],
    );
  }

  void _save(NotePattern pattern) {
    final state = _isolatedContainer!.read(pianoRollProvider);
    final updated = bridge.notePatternFromPianoRollState(
      state,
      patternId: pattern.id,
      patternName: pattern.name,
      minimumLengthTicks: pattern.lengthTicks,
      highlightedNotesOverride: pattern.highlightedNotes,
    );
    ref
        .read(songwriterProvider.notifier)
        .saveMelodyPattern(
          updated,
          initialPlacement: widget.initialPlacement == null
              ? null
              : (
                  sectionId: widget.initialPlacement!.sectionId,
                  laneId: widget.initialPlacement!.laneId,
                  blockId: widget.initialPlacement!.blockId,
                ),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songwriterProvider);
    final pattern = project.melodyPatterns
        .where((candidate) => candidate.id == widget.patternId)
        .firstOrNull;
    if (pattern == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    _ensureContainer(pattern, project.config);

    return Scaffold(
      backgroundColor: MuzicianTheme.surface,
      appBar: AppBar(
        backgroundColor: MuzicianTheme.surface,
        title: Text(pattern.name),
        actions: [
          TextButton.icon(
            key: const Key('saveWriterMelodyPattern'),
            onPressed: () => _save(pattern),
            icon: const Icon(Icons.save_outlined, size: 18),
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
