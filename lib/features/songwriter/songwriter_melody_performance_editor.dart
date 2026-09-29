/// Per-pattern Piano/Fretboard target and physical note-position editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/fretboard.dart';
import '../../models/harmony_lane_instrument.dart';
import '../../models/piano.dart' show PianoRangeName;
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/fretboard_rules.dart' show tunings;
import '../../schema/rules/piano_rules.dart'
    show midiToNoteWithOctave, pianoRanges;
import '../../schema/rules/songwriter_melody_instrument_rules.dart';
import '../../store/fretboard_store.dart';
import '../../store/piano_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../fretboard/fretboard.dart';
import '../piano/piano_keyboard.dart';
import 'songwriter_melody_pattern_editor.dart';

Future<void> showSongwriterMelodyPerformanceEditor({
  required BuildContext context,
  required String patternId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => SongwriterMelodyPerformanceEditor(patternId: patternId),
  ),
);

/// Writer's isolated instrument view for one melody pattern.
class SongwriterMelodyPerformanceEditor extends ConsumerStatefulWidget {
  const SongwriterMelodyPerformanceEditor({super.key, required this.patternId});

  final String patternId;

  @override
  ConsumerState<SongwriterMelodyPerformanceEditor> createState() =>
      _SongwriterMelodyPerformanceEditorState();
}

class _SongwriterMelodyPerformanceEditorState
    extends ConsumerState<SongwriterMelodyPerformanceEditor> {
  String? _selectedNoteId;

  void _selectTarget(
    HarmonyLaneInstrument instrument,
    SongwriterNotifier notifier,
  ) {
    final accepted = notifier.setMelodyPerformanceInstrument(
      patternId: widget.patternId,
      instrument: instrument,
    );
    if (accepted) return;
    _showMessage('This instrument cannot play every note in the pattern.');
  }

  void _selectPosition({
    required SongwriterNotifier notifier,
    required String noteId,
    required FretboardNotePosition position,
  }) {
    final accepted = notifier.setMelodyNoteFretboardPosition(
      patternId: widget.patternId,
      noteId: noteId,
      position: position,
    );
    if (accepted) return;
    _showMessage('That fretboard position is no longer playable.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songwriterProvider);
    final pianoState = ref.watch(pianoProvider);
    final fretboardState = ref.watch(fretboardProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    final pattern = project.melodyPatterns
        .where((candidate) => candidate.id == widget.patternId)
        .firstOrNull;

    if (pattern == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final performance = project.melodyPerformancesByPatternId[pattern.id];
    final pianoPlayable = canOpenOnInstrument(
      pattern: pattern,
      instrument: HarmonyLaneInstrument.piano,
      pianoRange: pianoState.currentRange,
      fretboard: fretboardState,
    );
    final fretboardPlayable = canOpenOnInstrument(
      pattern: pattern,
      instrument: HarmonyLaneInstrument.fretboard,
      pianoRange: pianoState.currentRange,
      fretboard: fretboardState,
    );
    final selectedNote = _selectedNote(pattern);
    final selectedNoteId = selectedNote?.id;
    final selectedPositions = selectedNote == null
        ? const <FretboardNotePosition>[]
        : fretboardPositionsForMidi(
            midiNote: selectedNote.midiNote,
            state: fretboardState,
          );
    final boardNotes = <FretboardOverlayNote>[];
    if (performance != null &&
        performance.instrument == HarmonyLaneInstrument.fretboard) {
      for (final note in pattern.notes) {
        final position = performance.fretboardPositionsByNoteId[note.id];
        if (position == null ||
            !isValidFretboardNotePosition(
              midiNote: note.midiNote,
              position: position,
              state: fretboardState,
            )) {
          continue;
        }
        boardNotes.add(
          FretboardOverlayNote(
            midiNote: note.midiNote,
            stringIndex: position.stringIndex,
            fret: position.fret,
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: MuzicianTheme.surface,
      appBar: AppBar(
        backgroundColor: MuzicianTheme.surface,
        title: Text('${pattern.name} performance'),
        leading: IconButton(
          tooltip: 'Close performance editor',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Text(
              'Play this pattern on',
              style: TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _InstrumentTargetPicker(
              selected: performance?.instrument,
              pianoEnabled: pianoPlayable,
              fretboardEnabled: fretboardPlayable,
              onSelected: (instrument) => _selectTarget(instrument, notifier),
            ),
            const SizedBox(height: 12),
            if (performance == null) ...[
              const _InstructionCard(
                icon: Icons.touch_app_outlined,
                text: 'Choose Piano or Fretboard to map this pattern.',
              ),
              _PatternRollButton(
                onPressed: () => showSongwriterMelodyPatternEditor(
                  context: context,
                  patternId: pattern.id,
                ),
              ),
            ] else if (!_isPlayable(
              performance.instrument,
              pianoPlayable: pianoPlayable,
              fretboardPlayable: fretboardPlayable,
            )) ...[
              _UnavailableInstrumentCard(
                instrument: performance.instrument,
                notes: _unplayableNotes(
                  pattern,
                  performance.instrument,
                  pianoRange: pianoState.currentRange,
                  fretboardState: fretboardState,
                ),
                onEditNotes: () => showSongwriterMelodyPatternEditor(
                  context: context,
                  patternId: pattern.id,
                ),
              ),
            ] else if (performance.instrument ==
                HarmonyLaneInstrument.piano) ...[
              Text(
                'MIDI keys in ${pianoRanges[pianoState.currentRange]!.displayName}',
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: pianoKeyboardHeight,
                child: PianoKeyboard(
                  hideToolbar: true,
                  controlledMidiNotes: {
                    for (final note in pattern.notes) note.midiNote,
                  },
                ),
              ),
              const SizedBox(height: 12),
              _PatternNoteList(
                pattern: pattern,
                selectedNoteId: selectedNoteId,
                onSelected: (noteId) => setState(() {
                  _selectedNoteId = noteId;
                }),
                fretboardState: fretboardState,
                performance: performance,
              ),
              _PatternRollButton(
                onPressed: () => showSongwriterMelodyPatternEditor(
                  context: context,
                  patternId: pattern.id,
                ),
              ),
            ] else ...[
              Text(
                'Tap a blue matching note position to move the selected note. '
                'Green markers show saved positions.',
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label:
                    'Controlled melody fretboard. '
                    'Tapping a matching highlighted position assigns it to '
                    'the selected melody note.',
                child: SizedBox(
                  height: fretboardBoardHeight,
                  child: GuitarFretboard(
                    hideToolbar: true,
                    palette: FretboardPalette.midnight,
                    controlledMode: true,
                    controlledNotes: boardNotes,
                    selectableMidiNote: selectedNote?.midiNote,
                    onControlledPositionSelected: selectedNote == null
                        ? null
                        : (coordinate) => _selectPosition(
                            notifier: notifier,
                            noteId: selectedNote.id,
                            position: FretboardNotePosition(
                              stringIndex: coordinate.stringIndex,
                              fret: coordinate.fret,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _PatternNoteList(
                pattern: pattern,
                selectedNoteId: selectedNoteId,
                onSelected: (noteId) => setState(() {
                  _selectedNoteId = noteId;
                }),
                fretboardState: fretboardState,
                performance: performance,
              ),
              _PatternRollButton(
                onPressed: () => showSongwriterMelodyPatternEditor(
                  context: context,
                  patternId: pattern.id,
                ),
              ),
              if (selectedNote != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Valid positions for ${midiToNoteWithOctave(selectedNote.midiNote)}',
                  style: const TextStyle(
                    color: MuzicianTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (selectedPositions.isEmpty)
                  const _InstructionCard(
                    icon: Icons.info_outline,
                    text:
                        'No valid fret positions are available under the '
                        'current tuning, capo, and fret count.',
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final position in selectedPositions)
                        _PositionChip(
                          position: position,
                          state: fretboardState,
                          selected:
                              performance
                                      .fretboardPositionsByNoteId[selectedNote
                                          .id]
                                      ?.stringIndex ==
                                  position.stringIndex &&
                              performance
                                      .fretboardPositionsByNoteId[selectedNote
                                          .id]
                                      ?.fret ==
                                  position.fret,
                          onPressed: () => _selectPosition(
                            notifier: notifier,
                            noteId: selectedNote.id,
                            position: position,
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  NotePatternNote? _selectedNote(NotePattern pattern) {
    final current = pattern.notes
        .where((note) => note.id == _selectedNoteId)
        .firstOrNull;
    if (current != null) return current;
    return pattern.notes.firstOrNull;
  }

  bool _isPlayable(
    HarmonyLaneInstrument instrument, {
    required bool pianoPlayable,
    required bool fretboardPlayable,
  }) => instrument == HarmonyLaneInstrument.piano
      ? pianoPlayable
      : fretboardPlayable;

  List<NotePatternNote> _unplayableNotes(
    NotePattern pattern,
    HarmonyLaneInstrument instrument, {
    required PianoRangeName pianoRange,
    required FretboardState fretboardState,
  }) {
    final playable = instrument == HarmonyLaneInstrument.piano
        ? playablePianoMidis(pianoRange)
        : playableFretboardMidis(fretboardState);
    return pattern.notes
        .where((note) => !playable.contains(note.midiNote))
        .toList();
  }
}

class _InstrumentTargetPicker extends StatelessWidget {
  const _InstrumentTargetPicker({
    required this.selected,
    required this.pianoEnabled,
    required this.fretboardEnabled,
    required this.onSelected,
  });

  final HarmonyLaneInstrument? selected;
  final bool pianoEnabled;
  final bool fretboardEnabled;
  final ValueChanged<HarmonyLaneInstrument> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _TargetButton(
          label: 'Piano',
          icon: Icons.piano,
          selected: selected == HarmonyLaneInstrument.piano,
          enabled: pianoEnabled,
          onPressed: () => onSelected(HarmonyLaneInstrument.piano),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _TargetButton(
          label: 'Fretboard',
          icon: Icons.music_note,
          selected: selected == HarmonyLaneInstrument.fretboard,
          enabled: fretboardEnabled,
          onPressed: () => onSelected(HarmonyLaneInstrument.fretboard),
        ),
      ),
    ],
  );
}

class _TargetButton extends StatelessWidget {
  const _TargetButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    selected: selected,
    label: '$label performance target${enabled ? '' : ', unavailable'}',
    child: SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected
              ? MuzicianTheme.sky
              : MuzicianTheme.textSecondary,
          side: BorderSide(
            color: selected
                ? MuzicianTheme.sky.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.12),
          ),
          backgroundColor: selected
              ? MuzicianTheme.sky.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.025),
        ),
      ),
    ),
  );
}

class _UnavailableInstrumentCard extends StatelessWidget {
  const _UnavailableInstrumentCard({
    required this.instrument,
    required this.notes,
    required this.onEditNotes,
  });

  final HarmonyLaneInstrument instrument;
  final List<NotePatternNote> notes;
  final VoidCallback onEditNotes;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF251B21),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: MuzicianTheme.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This instrument cannot play every pattern note.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${instrument == HarmonyLaneInstrument.piano ? 'Piano' : 'Fretboard'} '
            'view is unavailable for: ${notes.map((note) => midiToNoteWithOctave(note.midiNote)).join(', ')}.',
            style: const TextStyle(color: MuzicianTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onEditNotes,
              icon: const Icon(Icons.edit_note),
              label: const Text('Correct notes in Piano Roll'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PatternRollButton extends StatelessWidget {
  const _PatternRollButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.edit_note),
      label: const Text('Edit notes in Piano Roll'),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}

class _PatternNoteList extends StatelessWidget {
  const _PatternNoteList({
    required this.pattern,
    required this.selectedNoteId,
    required this.onSelected,
    required this.fretboardState,
    required this.performance,
  });

  final NotePattern pattern;
  final String? selectedNoteId;
  final ValueChanged<String> onSelected;
  final FretboardState fretboardState;
  final WriterMelodyPerformance performance;

  @override
  Widget build(BuildContext context) {
    if (pattern.notes.isEmpty) {
      return const _InstructionCard(
        icon: Icons.music_note_outlined,
        text: 'This pattern has no notes yet. Add notes in Piano Roll.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pattern notes',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < pattern.notes.length; index++)
          _PatternNoteRow(
            index: index,
            note: pattern.notes[index],
            selected:
                pattern.notes[index].id == selectedNoteId ||
                (selectedNoteId == null && index == 0),
            performance: performance,
            fretboardState: fretboardState,
            onSelected: () => onSelected(pattern.notes[index].id),
          ),
      ],
    );
  }
}

class _PatternNoteRow extends StatelessWidget {
  const _PatternNoteRow({
    required this.index,
    required this.note,
    required this.selected,
    required this.performance,
    required this.fretboardState,
    required this.onSelected,
  });

  final int index;
  final NotePatternNote note;
  final bool selected;
  final WriterMelodyPerformance performance;
  final FretboardState fretboardState;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final position = performance.fretboardPositionsByNoteId[note.id];
    final validPosition =
        position != null &&
        isValidFretboardNotePosition(
          midiNote: note.midiNote,
          position: position,
          state: fretboardState,
        );
    final tuning = tunings[fretboardState.currentTuning]!;
    final mappedLabel = performance.instrument == HarmonyLaneInstrument.piano
        ? 'Piano key MIDI ${note.midiNote}'
        : validPosition
        ? 'String ${position.stringIndex + 1} (${tuning.strings[position.stringIndex].note}), fret ${position.fret}'
        : 'Choose a playable position';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? MuzicianTheme.sky.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onSelected,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Semantics(
                    label:
                        'Pattern note ${index + 1}, '
                        '${midiToNoteWithOctave(note.midiNote)}, '
                        'MIDI ${note.midiNote}',
                    selected: selected,
                    child: ExcludeSemantics(
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? MuzicianTheme.sky
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: selected
                                ? MuzicianTheme.scaffoldBg
                                : MuzicianTheme.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${midiToNoteWithOctave(note.midiNote)}  ·  MIDI ${note.midiNote}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mappedLabel,
                          style: TextStyle(
                            color:
                                performance.instrument ==
                                        HarmonyLaneInstrument.piano ||
                                    validPosition
                                ? MuzicianTheme.textSecondary
                                : MuzicianTheme.orange,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (performance.instrument == HarmonyLaneInstrument.fretboard)
                    const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PositionChip extends StatelessWidget {
  const _PositionChip({
    required this.position,
    required this.state,
    required this.selected,
    required this.onPressed,
  });

  final FretboardNotePosition position;
  final FretboardState state;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tuning = tunings[state.currentTuning]!;
    final string = tuning.strings[position.stringIndex];
    final label =
        'String ${position.stringIndex + 1} (${string.note}), '
        'fret ${position.fret}';
    return Semantics(
      button: true,
      selected: selected,
      label: '$label${selected ? ', selected' : ''}',
      child: ActionChip(
        avatar: selected ? const Icon(Icons.check, size: 16) : null,
        label: Text(label),
        onPressed: onPressed,
        labelStyle: TextStyle(
          color: selected ? MuzicianTheme.sky : MuzicianTheme.textPrimary,
          fontSize: 12,
        ),
        backgroundColor: selected
            ? MuzicianTheme.sky.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        side: BorderSide(
          color: selected
              ? MuzicianTheme.sky.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.12),
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Row(
      children: [
        Icon(icon, color: MuzicianTheme.sky, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}
