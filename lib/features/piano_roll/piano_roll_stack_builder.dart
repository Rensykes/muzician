library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll_composer.dart';
import '../../models/piano_roll_stack_builder.dart';
import '../../store/piano_roll_stack_builder_store.dart';
import '../../theme/muzician_theme.dart';
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

  void _confirmWizard(PianoRollStackBuilderNotifier notifier) {
    final midi = _wizardMidi;
    var success = false;
    if (_wizardIndex == -1) {
      success = notifier.addAbsoluteNote(midi);
    } else if (_wizardIndex != null && _wizardIndex! >= 0) {
      success = notifier.replaceNoteAt(_wizardIndex!, midi);
    }
    if (success) {
      _closeWizard();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final builderState = ref.watch(pianoRollStackBuilderProvider);
    final notifier = ref.read(pianoRollStackBuilderProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(builderState),
            const SizedBox(height: 8),
            _buildTabRow(builderState, notifier),
            Divider(color: MuzicianTheme.glassBorder, height: 1),
            const SizedBox(height: 8),
            if (builderState.activeView == PianoRollStackBuilderView.canonical)
              _buildCanonicalBody(builderState, notifier)
            else
              _buildAdvancedBody(builderState, notifier),
            if (builderState.errorMessage != null) ...[
              const SizedBox(height: 6),
              _buildError(builderState.errorMessage!, notifier),
            ],
            const SizedBox(height: 8),
            _buildPreview(builderState),
            const SizedBox(height: 8),
            _buildAddStackButton(notifier),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(PianoRollStackBuilderState state) {
    final r = state.recognition;
    final parts = <String>[];

    if (r.isRecognized && r.recognizedRoot != null) {
      final displayRoot = formatRootChoiceLabel(r.recognizedRoot!);
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
      style: const TextStyle(
        color: MuzicianTheme.textPrimary,
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
      height: 34,
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
          height: 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chromaticNotes.map((root) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Pill(
                    label: formatRootChoiceLabel(root),
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
          height: 32,
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
          height: 32,
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
          height: 32,
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
  ) {
    if (_wizardActive) {
      return _buildAdvancedWizardBody(state, notifier);
    }

    return _buildAdvancedDefaultBody(state, notifier);
  }

  Widget _buildAdvancedDefaultBody(
    PianoRollStackBuilderState state,
    PianoRollStackBuilderNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionLabel('Notes'),
        const SizedBox(height: 4),
        if (state.midiNotes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No notes',
              style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 12),
            ),
          )
        else
          ...List.generate(state.midiNotes.length, (i) {
            final midi = state.midiNotes[i];
            final noteName = formatMidiNoteLabel(midi);
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
          height: 36,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(9, (i) {
                final degree = (i + 1).toString();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _DegreePill(
                    label: degree,
                    onTap: () => notifier.insertDegreeShortcut(degree),
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
  ) {
    final isAdd = _wizardIndex == -1;
    final title = isAdd ? 'Add note' : 'Edit note';
    final detail = isAdd
        ? '${state.midiNotes.length} notes in stack'
        : 'Editing ${formatMidiNoteLabel(state.midiNotes[_wizardIndex!])}';

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
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: MuzicianTheme.textMuted,
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
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MuzicianTheme.glassBorder),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: MuzicianTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildNoteWizard(notifier),
      ],
    );
  }

  Widget _buildAddNoteButton(PianoRollStackBuilderNotifier notifier) {
    return GestureDetector(
      onTap: () => _openWizard(-1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MuzicianTheme.violet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: MuzicianTheme.violet.withValues(alpha: 0.3),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 14, color: MuzicianTheme.violet),
            SizedBox(width: 4),
            Text(
              'Add note',
              style: TextStyle(
                color: MuzicianTheme.violet,
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

  Widget _buildNoteWizard(PianoRollStackBuilderNotifier notifier) {
    final noteName = formatMidiNoteLabel(_wizardMidi);

    return Container(
      key: const ValueKey('stack-builder-note-wizard-card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Note',
            style: TextStyle(
              color: MuzicianTheme.textMuted,
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
                    constraints: const BoxConstraints.tightFor(
                      width: 52,
                      height: 36,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? MuzicianTheme.sky.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active
                            ? MuzicianTheme.sky
                            : MuzicianTheme.glassBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        formatRootChoiceLabel(note),
                        style: TextStyle(
                          color: active
                              ? MuzicianTheme.sky
                              : MuzicianTheme.textSecondary,
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
          const Text(
            'Octave',
            style: TextStyle(
              color: MuzicianTheme.textMuted,
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
                    width: 36,
                    height: 34,
                    decoration: BoxDecoration(
                      color: active
                          ? MuzicianTheme.teal.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active
                            ? MuzicianTheme.teal
                            : MuzicianTheme.glassBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$oct',
                        style: TextStyle(
                          color: active
                              ? MuzicianTheme.teal
                              : MuzicianTheme.textSecondary,
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
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
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
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MuzicianTheme.glassBorder),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _confirmWizard(notifier),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.sky.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: MuzicianTheme.sky.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      color: MuzicianTheme.sky,
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
        color: MuzicianTheme.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MuzicianTheme.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: MuzicianTheme.orange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: MuzicianTheme.orange,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => notifier.clearError(),
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: MuzicianTheme.orange,
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  Widget _buildPreview(PianoRollStackBuilderState state) {
    if (state.midiNotes.isEmpty) return const SizedBox.shrink();
    final preview = state.midiNotes.map(formatMidiNoteLabel).join(', ');
    return Text(
      preview,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: MuzicianTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  // ── Add Stack button ─────────────────────────────────────────────────────

  Widget _buildAddStackButton(PianoRollStackBuilderNotifier notifier) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        final added = notifier.addStack();
        if (added && widget.dismissOnAdd) {
          Navigator.of(context).maybePop();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: MuzicianTheme.violet.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: MuzicianTheme.violet.withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 16, color: MuzicianTheme.violet),
            SizedBox(width: 6),
            Text(
              'Add Stack',
              style: TextStyle(
                color: MuzicianTheme.violet,
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
      style: const TextStyle(
        color: MuzicianTheme.textMuted,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? MuzicianTheme.sky.withValues(alpha: 0.45)
                : MuzicianTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? MuzicianTheme.sky : MuzicianTheme.textSecondary,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? MuzicianTheme.sky.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.16),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? MuzicianTheme.sky : MuzicianTheme.textSecondary,
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
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: MuzicianTheme.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: MuzicianTheme.teal.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: MuzicianTheme.teal,
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
            ? MuzicianTheme.sky.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing
              ? MuzicianTheme.sky.withValues(alpha: 0.3)
              : MuzicianTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              noteName,
              style: TextStyle(
                color: isEditing
                    ? MuzicianTheme.sky
                    : MuzicianTheme.textPrimary,
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
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MuzicianTheme.sky.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: MuzicianTheme.sky,
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
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MuzicianTheme.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: MuzicianTheme.orange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
