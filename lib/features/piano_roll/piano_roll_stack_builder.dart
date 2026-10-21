library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll_composer.dart';
import '../../models/piano_roll_stack_builder.dart';
import '../../store/piano_roll_stack_builder_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../utils/note_utils.dart';

const _inversionLabels = <String>['Root', '1st', '2nd', '3rd'];

const _durationOptions = <(String label, int ticks)>[
  ('1/16', 1),
  ('1/8', 2),
  ('1/4', 4),
  ('1/2', 8),
  ('1/1', 16),
];

class PianoRollStackBuilder extends ConsumerStatefulWidget {
  final bool dismissOnAdd;

  const PianoRollStackBuilder({super.key, this.dismissOnAdd = false});

  @override
  ConsumerState<PianoRollStackBuilder> createState() =>
      _PianoRollStackBuilderState();
}

class _PianoRollStackBuilderState extends ConsumerState<PianoRollStackBuilder> {
  /// null = wizard closed, -1 = adding new note, >=0 = editing note at index
  int? _wizardIndex;
  int _wizardPc = 0;
  int _wizardOctave = 4;

  int get _wizardMidi => (_wizardOctave + 1) * 12 + _wizardPc;
  bool get _wizardActive => _wizardIndex != null;

  void _openWizard(int? index, {int? initialMidi}) {
    setState(() {
      _wizardIndex = index;
      _wizardPc = initialMidi != null ? initialMidi % 12 : 0;
      _wizardOctave = initialMidi != null ? (initialMidi ~/ 12) - 1 : 4;
    });
  }

  void _closeWizard() {
    setState(() {
      _wizardIndex = null;
    });
  }

  void _confirmWizard(
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    final midi = _wizardMidi;
    var success = false;
    if (_wizardIndex == -1) {
      success = notifier.addAbsoluteNote(midi, spelling: spelling);
    } else if (_wizardIndex != null && _wizardIndex! >= 0) {
      success = notifier.replaceNoteAt(_wizardIndex!, midi, spelling: spelling);
    }
    if (success) {
      _closeWizard();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final builderState = ref.watch(pianoRollStackBuilderProvider);
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final notifier = ref.read(pianoRollStackBuilderProvider.notifier);

    if (StudioPalette.of(context).isStudio) {
      return _buildStudio(builderState, notifier, spelling);
    }

    return Container(
      decoration: StudioPalette.of(context).isStudio
          ? null
          : BoxDecoration(
              color: StudioPalette.of(context).glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: StudioPalette.of(context).glassBorder),
            ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(builderState, spelling),
            const SizedBox(height: 8),
            _buildTabRow(builderState, notifier),
            Divider(color: StudioPalette.of(context).glassBorder, height: 1),
            const SizedBox(height: 8),
            if (builderState.activeView == PianoRollStackBuilderView.canonical)
              _buildCanonicalBody(builderState, notifier, spelling)
            else
              _buildAdvancedBody(builderState, notifier, spelling),
            if (builderState.errorMessage != null) ...[
              const SizedBox(height: 6),
              _buildError(builderState.errorMessage!, notifier),
            ],
            const SizedBox(height: 8),
            _buildPreview(builderState, spelling),
            const SizedBox(height: 8),
            _buildAddStackButton(notifier, spelling),
          ],
        ),
      ),
    );
  }

  Widget _buildStudio(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    final p = StudioPalette.of(context);
    final canonical = state.activeView == PianoRollStackBuilderView.canonical;
    final recognition = state.recognition;
    return SingleChildScrollView(
      key: const ValueKey('studio-stack-builder'),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (label, view) in [
                ('Chord', PianoRollStackBuilderView.canonical),
                ('Custom', PianoRollStackBuilderView.advanced),
              ])
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      if (view == PianoRollStackBuilderView.canonical) {
                        _closeWizard();
                      }
                      notifier.switchView(view);
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: state.activeView == view
                          ? p.onAccent
                          : p.textSecondary,
                      backgroundColor: state.activeView == view
                          ? p.sky
                          : p.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(label),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (canonical)
            Row(
              children: [
                Expanded(
                  child: _studioChoice<String>(
                    label: 'Root',
                    value: recognition.recognizedRoot ?? 'C',
                    choices: [
                      for (final root in chromaticNotes)
                        (root, formatRootChoiceLabel(root, spelling: spelling)),
                    ],
                    onSelected: notifier.setCanonicalRoot,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _studioChoice<String>(
                    label: 'Quality',
                    value: recognition.recognizedQuality ?? '',
                    choices: [
                      for (final e in qualityLabelBySymbol.entries)
                        (e.key, e.value),
                    ],
                    onSelected: notifier.setCanonicalQuality,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _studioChoice<int>(
                    label: 'Inversion',
                    value: recognition.recognizedInversionIndex ?? 0,
                    choices: [
                      for (final (i, label) in _inversionLabels.indexed)
                        (i, label),
                    ],
                    onSelected: notifier.setCanonicalInversion,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _studioChoice<int>(
                    label: 'Duration',
                    value: state.durationTicks,
                    choices: [
                      for (final (label, ticks) in _durationOptions)
                        (ticks, label),
                    ],
                    onSelected: notifier.setDurationTicks,
                  ),
                ),
              ],
            )
          else ...[
            _buildHeader(state, spelling),
            const SizedBox(height: 8),
            _buildAdvancedBody(state, notifier, spelling),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 6),
            _buildError(state.errorMessage!, notifier),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('studio-add-stack'),
            onPressed: () {
              HapticFeedback.mediumImpact();
              final added = notifier.addStack(spelling: spelling);
              if (added && widget.dismissOnAdd) {
                Navigator.of(context).maybePop();
              }
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: p.sky,
              foregroundColor: p.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_rounded, size: 18),
                const SizedBox(width: 6),
                const Text('Add stack'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.midiNotes
                        .map(
                          (midi) =>
                              formatMidiNoteLabel(midi, spelling: spelling),
                        )
                        .join(' · '),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studioChoice<T>({
    required String label,
    required T value,
    required List<(T, String)> choices,
    required ValueChanged<T> onSelected,
  }) {
    final p = StudioPalette.of(context);
    final selected = choices.where((choice) => choice.$1 == value).firstOrNull;
    return Semantics(
      label: '$label: ${selected?.$2 ?? 'Custom'}',
      button: true,
      child: InkWell(
        key: ValueKey('studio-stack-${label.toLowerCase()}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          final choice = await showStudioDialog<T>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: Row(
                children: [
                  Expanded(child: Text(label)),
                  IconButton(
                    tooltip: 'Close $label',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              children: [
                for (final (item, name) in choices)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(dialogContext).pop(item),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(name)),
                        if (item == value)
                          const Icon(Icons.check_rounded, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          );
          if (mounted && choice != null) onSelected(choice);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label == 'Inversion'
                          ? 'Inv.'
                          : label == 'Duration'
                          ? 'Length'
                          : label,
                      style: TextStyle(color: p.textMuted, fontSize: 11),
                    ),
                    Text(
                      selected?.$2 ?? 'Custom',
                      style: TextStyle(color: p.textPrimary, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more_rounded, color: p.textSecondary, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(PianoRollStackBuilderState state, NoteSpelling spelling) {
    final r = state.recognition;
    final parts = <String>[];

    if (r.isRecognized && r.recognizedRoot != null) {
      final displayRoot = formatRootChoiceLabel(
        r.recognizedRoot!,
        spelling: spelling,
      );
      final qualityLabel =
          qualityLabelBySymbol[r.recognizedQuality ?? ''] ?? '';
      parts.add('$displayRoot $qualityLabel');

      if (r.recognizedInversionIndex != null &&
          r.recognizedInversionIndex! > 0) {
        final idx = r.recognizedInversionIndex!.clamp(
          0,
          _inversionLabels.length - 1,
        );
        parts.add('${_inversionLabels[idx]} inv');
      }

      if (r.isCustomVoicing) {
        parts.add('Custom voicing');
      }
    } else if (!r.isRecognized && state.midiNotes.isNotEmpty) {
      parts.add('Unrecognized custom stack');
    } else {
      parts.add('No notes');
    }

    return Text(
      parts.join(' • '),
      style: TextStyle(
        color: StudioPalette.of(context).textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ── Tab row ──────────────────────────────────────────────────────────────

  Widget _buildTabRow(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
  ) {
    return SizedBox(
      height: StudioPalette.of(context).isStudio ? 44 : 34,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _TabPill(
              label: 'Canonico',
              active: state.activeView == PianoRollStackBuilderView.canonical,
              onTap: () {
                _closeWizard();
                notifier.switchView(PianoRollStackBuilderView.canonical);
              },
            ),
            const SizedBox(width: 8),
            _TabPill(
              label: 'Avanzato',
              active: state.activeView == PianoRollStackBuilderView.advanced,
              onTap: () {
                notifier.switchView(PianoRollStackBuilderView.advanced);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Canonical body ───────────────────────────────────────────────────────

  Widget _buildCanonicalBody(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    final r = state.recognition;
    final currentRoot = r.recognizedRoot ?? 'C';
    final currentQuality = r.recognizedQuality ?? '';
    final currentInv = r.recognizedInversionIndex ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionLabel('Root'),
        const SizedBox(height: 4),
        SizedBox(
          height: StudioPalette.of(context).isStudio ? 44 : 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chromaticNotes.map((root) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Pill(
                    label: formatRootChoiceLabel(root, spelling: spelling),
                    active: root == currentRoot,
                    onTap: () => notifier.setCanonicalRoot(root),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionLabel('Quality'),
        const SizedBox(height: 4),
        SizedBox(
          height: StudioPalette.of(context).isStudio ? 44 : 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: qualityLabelBySymbol.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Pill(
                    label: e.value,
                    active: e.key == currentQuality,
                    onTap: () => notifier.setCanonicalQuality(e.key),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionLabel('Inversion'),
        const SizedBox(height: 4),
        SizedBox(
          height: StudioPalette.of(context).isStudio ? 44 : 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_inversionLabels.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Pill(
                    label: _inversionLabels[i],
                    active: i == currentInv,
                    onTap: () => notifier.setCanonicalInversion(i),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionLabel('Duration'),
        const SizedBox(height: 4),
        SizedBox(
          height: StudioPalette.of(context).isStudio ? 44 : 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _durationOptions.map((d) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Pill(
                    label: d.$1,
                    active: state.durationTicks == d.$2,
                    onTap: () => notifier.setDurationTicks(d.$2),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Advanced body ────────────────────────────────────────────────────────

  Widget _buildAdvancedBody(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    if (_wizardActive) {
      return _buildAdvancedWizardBody(state, notifier, spelling);
    }

    return _buildAdvancedDefaultBody(state, notifier, spelling);
  }

  Widget _buildAdvancedDefaultBody(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionLabel('Notes'),
        const SizedBox(height: 4),
        if (state.midiNotes.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No notes',
              style: TextStyle(
                color: StudioPalette.of(context).textMuted,
                fontSize: 12,
              ),
            ),
          )
        else
          ...List.generate(state.midiNotes.length, (i) {
            final midi = state.midiNotes[i];
            final noteName = formatMidiNoteLabel(midi, spelling: spelling);
            final isEditing = _wizardIndex == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _NoteRow(
                noteName: noteName,
                isEditing: false,
                onEdit: isEditing
                    ? null
                    : () => _openWizard(i, initialMidi: midi),
                onRemove: () {
                  _closeWizard();
                  notifier.removeNoteAt(i);
                },
              ),
            );
          }),
        const SizedBox(height: 8),
        _buildAddNoteButton(notifier),
        const SizedBox(height: 8),
        _sectionLabel('Degree shortcuts'),
        const SizedBox(height: 4),
        SizedBox(
          height: StudioPalette.of(context).isStudio ? 44 : 36,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(9, (i) {
                final degree = (i + 1).toString();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _DegreePill(
                    label: degree,
                    onTap: () => notifier.insertDegreeShortcut(
                      degree,
                      spelling: spelling,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedWizardBody(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    final isAdd = _wizardIndex == -1;
    final title = isAdd ? 'Add note' : 'Edit note';
    final detail = isAdd
        ? '${state.midiNotes.length} notes in stack'
        : 'Editing ${formatMidiNoteLabel(state.midiNotes[_wizardIndex!], spelling: spelling)}';

    return Column(
      key: const ValueKey('stack-builder-advanced-wizard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: StudioPalette.of(context).textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      color: StudioPalette.of(context).textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _closeWizard,
              child: Container(
                width: StudioPalette.of(context).isStudio ? 44 : 32,
                height: StudioPalette.of(context).isStudio ? 44 : 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      (StudioPalette.of(context).isStudio
                              ? StudioPalette.of(context).textPrimary
                              : Colors.white)
                          .withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: StudioPalette.of(context).glassBorder,
                  ),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: StudioPalette.of(context).textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildNoteWizard(notifier, spelling),
      ],
    );
  }

  Widget _buildAddNoteButton(PianoRollStackBuilderNotifier notifier) {
    return GestureDetector(
      onTap: () => _openWizard(-1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: StudioPalette.of(context).violet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: StudioPalette.of(context).violet.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_rounded,
              size: 14,
              color: StudioPalette.of(context).violet,
            ),
            SizedBox(width: 4),
            Text(
              'Add note',
              style: TextStyle(
                color: StudioPalette.of(context).violet,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Inline wizard ────────────────────────────────────────────────────────

  Widget _buildNoteWizard(
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    final noteName = formatMidiNoteLabel(_wizardMidi, spelling: spelling);

    return Container(
      key: const ValueKey('stack-builder-note-wizard-card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            (StudioPalette.of(context).isStudio
                    ? StudioPalette.of(context).textPrimary
                    : Colors.white)
                .withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StudioPalette.of(context).glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Note',
            style: TextStyle(
              color: StudioPalette.of(context).textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(chromaticNotes.length, (i) {
                final note = chromaticNotes[i];
                final active = _wizardPc == i;
                return GestureDetector(
                  onTap: () => setState(() => _wizardPc = i),
                  child: Container(
                    constraints: BoxConstraints.tightFor(
                      width: 52,
                      height: StudioPalette.of(context).isStudio ? 44 : 36,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? StudioPalette.of(
                              context,
                            ).sky.withValues(alpha: 0.16)
                          : (StudioPalette.of(context).isStudio
                                    ? StudioPalette.of(context).textPrimary
                                    : Colors.white)
                                .withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active
                            ? StudioPalette.of(context).sky
                            : StudioPalette.of(context).glassBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        formatRootChoiceLabel(note, spelling: spelling),
                        style: TextStyle(
                          color: active
                              ? StudioPalette.of(context).sky
                              : StudioPalette.of(context).textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Octave',
            style: TextStyle(
              color: StudioPalette.of(context).textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(7, (i) {
                final oct = i + 2;
                final active = _wizardOctave == oct;
                return GestureDetector(
                  onTap: () => setState(() => _wizardOctave = oct),
                  child: Container(
                    width: StudioPalette.of(context).isStudio ? 44 : 36,
                    height: StudioPalette.of(context).isStudio ? 44 : 34,
                    decoration: BoxDecoration(
                      color: active
                          ? StudioPalette.of(
                              context,
                            ).teal.withValues(alpha: 0.16)
                          : (StudioPalette.of(context).isStudio
                                    ? StudioPalette.of(context).textPrimary
                                    : Colors.white)
                                .withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active
                            ? StudioPalette.of(context).teal
                            : StudioPalette.of(context).glassBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$oct',
                        style: TextStyle(
                          color: active
                              ? StudioPalette.of(context).teal
                              : StudioPalette.of(context).textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // Live preview
          Center(
            child: Text(
              noteName,
              style: TextStyle(
                color: StudioPalette.of(context).textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Confirm / Cancel
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _closeWizard,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (StudioPalette.of(context).isStudio
                                ? StudioPalette.of(context).textPrimary
                                : Colors.white)
                            .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: StudioPalette.of(context).glassBorder,
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: StudioPalette.of(context).textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _confirmWizard(notifier, spelling),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: StudioPalette.of(
                      context,
                    ).sky.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: StudioPalette.of(
                        context,
                      ).sky.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Confirm',
                    style: TextStyle(
                      color: StudioPalette.of(context).sky,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────

  Widget _buildError(String message, PianoRollStackBuilderNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: StudioPalette.of(context).orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: StudioPalette.of(context).orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: StudioPalette.of(context).orange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: StudioPalette.of(context).orange,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => notifier.clearError(),
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: StudioPalette.of(context).orange,
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  Widget _buildPreview(
    PianoRollStackBuilderState state,
    NoteSpelling spelling,
  ) {
    if (state.midiNotes.isEmpty) return const SizedBox.shrink();
    final preview = state.midiNotes
        .map((midi) => formatMidiNoteLabel(midi, spelling: spelling))
        .join(', ');
    return Text(
      preview,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: StudioPalette.of(context).textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  // ── Add Stack button ─────────────────────────────────────────────────────

  Widget _buildAddStackButton(
    PianoRollStackBuilderNotifier notifier,
    NoteSpelling spelling,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        final added = notifier.addStack(spelling: spelling);
        if (added && widget.dismissOnAdd) {
          Navigator.of(context).maybePop();
        }
      },
      child: Container(
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: StudioPalette.of(context).violet.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: StudioPalette.of(context).violet.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_rounded,
              size: 16,
              color: StudioPalette.of(context).violet,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Add Stack',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: StudioPalette.of(context).violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: StudioPalette.of(context).textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Private sub-widgets ──────────────────────────────────────────────────────

class _TabPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? StudioPalette.of(context).sky.withValues(alpha: 0.16)
              : (StudioPalette.of(context).isStudio
                        ? StudioPalette.of(context).textPrimary
                        : Colors.white)
                    .withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? StudioPalette.of(context).sky.withValues(alpha: 0.45)
                : StudioPalette.of(context).glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? StudioPalette.of(context).sky
                : StudioPalette.of(context).textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? StudioPalette.of(context).sky.withValues(alpha: 0.16)
              : (StudioPalette.of(context).isStudio
                        ? StudioPalette.of(context).textPrimary
                        : Colors.white)
                    .withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? StudioPalette.of(context).sky.withValues(alpha: 0.45)
                : (StudioPalette.of(context).isStudio
                          ? StudioPalette.of(context).textPrimary
                          : Colors.white)
                      .withValues(alpha: 0.16),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? StudioPalette.of(context).sky
                : StudioPalette.of(context).textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DegreePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DegreePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minWidth: StudioPalette.of(context).isStudio ? 44 : 32,
          minHeight: StudioPalette.of(context).isStudio ? 44 : 32,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: StudioPalette.of(context).teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: StudioPalette.of(context).teal.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: StudioPalette.of(context).teal,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final String noteName;
  final bool isEditing;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  const _NoteRow({
    required this.noteName,
    this.isEditing = false,
    this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isEditing
            ? StudioPalette.of(context).sky.withValues(alpha: 0.08)
            : (StudioPalette.of(context).isStudio
                      ? StudioPalette.of(context).textPrimary
                      : Colors.white)
                  .withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing
              ? StudioPalette.of(context).sky.withValues(alpha: 0.3)
              : StudioPalette.of(context).glassBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              noteName,
              style: TextStyle(
                color: isEditing
                    ? StudioPalette.of(context).sky
                    : StudioPalette.of(context).textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (onEdit != null)
            Semantics(
              button: true,
              label: 'Edit $noteName',
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  width: StudioPalette.of(context).isStudio ? 44 : 32,
                  height: StudioPalette.of(context).isStudio ? 44 : 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: StudioPalette.of(
                      context,
                    ).sky.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: StudioPalette.of(context).sky,
                  ),
                ),
              ),
            ),
          if (onEdit != null) const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'Remove $noteName',
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: StudioPalette.of(context).isStudio ? 44 : 32,
                height: StudioPalette.of(context).isStudio ? 44 : 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: StudioPalette.of(
                    context,
                  ).orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: StudioPalette.of(context).orange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
