/// Isolated Piano Roll editor host for one Writer melody pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/song_pattern_bridge_rules.dart' as bridge;
import '../../schema/rules/songwriter_rules.dart'
    show melodyMaxBars, quantizeMelodyPatternLength;
import '../../store/piano_roll_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/muzician_dialog.dart';
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
    builder: StudioRouteTheme.builder(
      context,
      (_) => _SongwriterMelodyPatternEditor(
        patternId: patternId,
        initialPlacement: initialPlacement,
      ),
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
  ProviderSubscription<PianoRollState>? _barSubscription;
  int? _barCount;
  int? _measureTicks;
  String? _draftName;

  @override
  void dispose() {
    _barSubscription?.close();
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
    _barCount = seedState.config.totalMeasures;
    _measureTicks = config.measureTicks;
    _draftName = pattern.name;
    final container = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _SeededPianoRollNotifier(seedState),
        ),
      ],
    );
    _barSubscription = container.listen(pianoRollProvider, (previous, next) {
      final measures = next.config.totalMeasures;
      final minimumBars = _lastNoteBar(next);
      final previousMinimumBars = previous == null
          ? null
          : _lastNoteBar(previous);
      if (!mounted) return;
      if (measures != _barCount || minimumBars != previousMinimumBars) {
        setState(() => _barCount = measures);
      }
    });
    _isolatedContainer = container;
  }

  int _lastNoteBar(PianoRollState state) {
    final measureTicks = _measureTicks ?? 1;
    if (measureTicks <= 0) return 1;
    var furthestEndTick = 0;
    for (final note in state.notes) {
      final endTick = note.startTick + note.durationTicks;
      if (endTick > furthestEndTick) furthestEndTick = endTick;
    }
    if (furthestEndTick <= 0) return 1;
    final bars = (furthestEndTick + measureTicks - 1) ~/ measureTicks;
    return bars.clamp(1, melodyMaxBars);
  }

  void _setBars(int bars) {
    final container = _isolatedContainer;
    if (container == null) return;
    final minimumBars = _lastNoteBar(container.read(pianoRollProvider));
    final nextBars = bars.clamp(minimumBars, melodyMaxBars);
    container.read(pianoRollProvider.notifier).setTotalMeasures(nextBars);
  }

  Future<void> _rename(NotePattern pattern) async {
    final name = await showStudioDialog<String>(
      context: context,
      builder: (_) =>
          _MelodyNameDialog(initialName: _draftName ?? pattern.name),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _draftName = name);
  }

  void _save(NotePattern pattern) {
    final state = _isolatedContainer!.read(pianoRollProvider);
    final measureTicks =
        _measureTicks ?? ref.read(songwriterProvider).config.measureTicks;
    final draftedName = (_draftName ?? pattern.name).trim();
    final updated = quantizeMelodyPatternLength(
      bridge.notePatternFromPianoRollState(
        state,
        patternId: pattern.id,
        patternName: draftedName.isEmpty ? pattern.name : draftedName,
        minimumLengthTicks: pattern.lengthTicks,
        highlightedNotesOverride: pattern.highlightedNotes,
      ),
      measureTicks,
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

  Widget _barsHeader(StudioPalette palette, PianoRollState state, int bars) {
    final minimumBars = _lastNoteBar(state);
    final valueStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.glassBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 2,
        children: [
          Text(
            'Bars',
            key: const Key('melodyBarsLabel'),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            key: const Key('melodyBarsDecrease'),
            onPressed: bars > minimumBars ? () => _setBars(bars - 1) : null,
            tooltip: 'Fewer bars',
            icon: const Icon(Icons.remove_rounded, size: 20),
            color: palette.textPrimary,
            disabledColor: palette.textDim,
          ),
          Text('$bars', key: const Key('melodyBarsValue'), style: valueStyle),
          IconButton(
            key: const Key('melodyBarsIncrease'),
            onPressed: bars < melodyMaxBars ? () => _setBars(bars + 1) : null,
            tooltip: 'More bars',
            icon: const Icon(Icons.add_rounded, size: 20),
            color: palette.textPrimary,
            disabledColor: palette.textDim,
          ),
        ],
      ),
    );
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
    final palette = StudioPalette.of(context);
    final rollState = _isolatedContainer!.read(pianoRollProvider);
    final bars = _barCount ?? rollState.config.totalMeasures;

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(
          _draftName ?? pattern.name,
          key: const Key('melodyEditorName'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('renameWriterMelodyPattern'),
            onPressed: () => _rename(pattern),
            tooltip: 'Rename melody',
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: palette.textSecondary,
          ),
          TextButton.icon(
            key: const Key('saveWriterMelodyPattern'),
            onPressed: () => _save(pattern),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save'),
            style: TextButton.styleFrom(foregroundColor: palette.sky),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: UncontrolledProviderScope(
        container: _isolatedContainer!,
        child: Column(
          children: [
            _barsHeader(palette, rollState, bars),
            const Expanded(
              child: PianoRollScreenV2(
                showScale: false,
                showSavePanels: false,
                showBackground: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MelodyNameDialog extends StatefulWidget {
  const _MelodyNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_MelodyNameDialog> createState() => _MelodyNameDialogState();
}

class _MelodyNameDialogState extends State<_MelodyNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    return MuzicianDialog(
      title: 'Rename melody',
      content: TextField(
        key: const Key('melodyNameField'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        style: TextStyle(color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: 'Melody name',
          hintStyle: TextStyle(color: palette.textMuted),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          buttonKey: const Key('melodyNameCancel'),
          onPressed: () => Navigator.pop(context),
        ),
        MuzicianDialogButton(
          'Save',
          emphasis: MuzicianDialogEmphasis.primary,
          buttonKey: const Key('melodyNameApply'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
