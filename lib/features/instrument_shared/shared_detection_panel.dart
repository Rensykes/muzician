/// SharedDetectionPanel – displays tapped pitch classes and detects matching
/// chords and scales using music_notes. Includes a "Clear" action.
///
/// Instrument-agnostic: driven entirely by an [InstrumentBinding]. Verbatim
/// port of the former fretboard NoteDetectionPanel (keeps the "No exact match"
/// hint) with binding substitutions and chord chips standardized to violet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../models/harmonic_analysis.dart';
import '../../models/project_config.dart';
import '../../models/save_system.dart';
import '../../schema/rules/songwriter_rules.dart'
    show isWriterEligibleNativeSelection;
import '../../store/project_config_sync.dart';
import '../../store/save_system_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../ui/core/update_project_key_dialog.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';
import 'writer_handoff.dart';

class SharedDetectionPanel extends ConsumerStatefulWidget {
  final InstrumentBinding binding;
  final VoidCallback? onChordPanelRequested;
  final VoidCallback? onHandoffCompleted;

  /// Lets the enclosing workspace own vertical scrolling and content height.
  final bool embedded;

  const SharedDetectionPanel({
    super.key,
    required this.binding,
    this.onChordPanelRequested,
    this.onHandoffCompleted,
    this.embedded = false,
  });

  @override
  ConsumerState<SharedDetectionPanel> createState() =>
      _SharedDetectionPanelState();
}

class _SharedDetectionPanelState extends ConsumerState<SharedDetectionPanel> {
  String? _activeScaleChip;

  @override
  Widget build(BuildContext context) {
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final selectedFolder = ref.watch(selectedProjectProvider);
    final projectKey = ref.watch(activeProjectKeyProvider);
    final isProject = selectedFolder?.kind == SaveFolderKind.project;
    if (isProject) {
      _activeScaleChip = projectKey == null
          ? null
          : '${projectKey.root} ${projectKey.scaleName}';
    }

    final selectedNotes = ref.watch(widget.binding.selectedNotes);
    final focusedNotes = ref.watch(widget.binding.focusedNotes);
    final exactNotes = ref.watch(widget.binding.exactNotes);
    final eligibilityState = widget.binding.eligibilityState;
    if (eligibilityState != null) ref.watch(eligibilityState);
    final handoffSnapshot = widget.binding.captureSnapshot(ref);
    final canHandoff =
        exactNotes.isNotEmpty &&
        isWriterEligibleNativeSelection(handoffSnapshot);
    final handoffUnavailableReason = handoffSnapshot is FretboardSnapshot
        ? handoffSnapshot.inputMode == FretboardInputMode.free
              ? 'Switch to Chord mode and keep one note per string to add this selection to Writer.'
              : 'Chord mode requires one valid note per string. Remove extra or invalid positions to add this selection to Writer.'
        : null;
    final actions = widget.binding.selectionActions(ref);

    ref.listen(widget.binding.highlightedNotes, (_, next) {
      if (next.isEmpty && _activeScaleChip != null) {
        setState(() => _activeScaleChip = null);
      }
    });
    ref.listen(selectedProjectProvider, (_, next) {
      if (next?.kind != SaveFolderKind.project) {
        setState(() => _activeScaleChip = null);
        return;
      }
      final config = next?.projectConfig;
      final rootPc = config?.keyRootPc;
      final scaleName = config?.keyScaleName;
      setState(() {
        _activeScaleChip =
            rootPc == null ||
                rootPc < 0 ||
                rootPc >= chromaticNotes.length ||
                scaleName == null
            ? null
            : '${chromaticNotes[rootPc]} $scaleName';
      });
    });

    final hasNotes = selectedNotes.isNotEmpty;

    // Detection runs on the same threshold the empty-state branch checks
    // (>= 2 distinct pitch classes), so the two never drift. exactNotes carries
    // the per-cell/per-key midi info the detectors need.
    final canDetect = selectedNotes.length >= 2 && exactNotes.isNotEmpty;
    final chordResults = canDetect
        ? detectChordResultsFromExactNotes(exactNotes)
        : const <ChordDetectionResult>[];
    final scaleResults = canDetect
        ? detectScaleResultsFromExactNotes(exactNotes)
        : const <ScaleDetectionResult>[];
    final hasResults = chordResults.isNotEmpty || scaleResults.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
      layoutBuilder: widget.embedded
          ? (child, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?child],
            )
          : AnimatedSwitcher.defaultLayoutBuilder,
      transitionBuilder: (child, animation) {
        final slide =
            Tween<Offset>(
              begin: const Offset(0, -0.12),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: hasNotes
          ? _content(
              key: const ValueKey(true),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'DETECTION',
                          style: TextStyle(
                            color: StudioPalette.of(context).textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),

                      TextButton(
                        onPressed: () => actions.clearSelectedNotes(),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Selected notes chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Notes',
                        style: TextStyle(
                          color: StudioPalette.of(context).textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'tap to focus',
                        style: TextStyle(
                          color: StudioPalette.of(context).textMuted,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: selectedNotes.map((note) {
                        final isFocused = focusedNotes.contains(note);
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            actions.toggleFocusedNote(note);
                          },
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            alignment: Alignment.center,
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: isFocused
                                  ? StudioPalette.of(context).sky
                                  : StudioPalette.of(
                                      context,
                                    ).sky.withValues(alpha: 0.15),
                              border: Border.all(
                                color: StudioPalette.of(
                                  context,
                                ).sky.withValues(alpha: 0.65),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              formatRootChoiceLabel(note, spelling: spelling),
                              style: TextStyle(
                                color: isFocused
                                    ? StudioPalette.of(context).onAccent
                                    : StudioPalette.of(context).sky,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Results
                  if (selectedNotes.length < 2)
                    Text(
                      'Tap at least 2 notes to detect.',
                      style: TextStyle(
                        color: StudioPalette.of(context).textMuted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (hasResults) ...[
                    if (chordResults.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Chords',
                            style: TextStyle(
                              color: StudioPalette.of(context).textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'tap to select voicing',
                            style: TextStyle(
                              color: StudioPalette.of(context).textMuted,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: chordResults.map((result) {
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(widget.binding.pendingChord.notifier)
                                    .state = (
                                  root: result.root,
                                  quality: result.quality,
                                );
                                ref
                                    .read(widget.binding.activeChord.notifier)
                                    .state = (
                                  root: result.root,
                                  quality: result.quality,
                                );
                                widget.onChordPanelRequested?.call();
                              },
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                alignment: Alignment.center,
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: StudioPalette.of(
                                    context,
                                  ).violet.withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: StudioPalette.of(
                                      context,
                                    ).violet.withValues(alpha: 0.45),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  formatChordSymbol(result, spelling: spelling),
                                  style: TextStyle(
                                    color: StudioPalette.of(
                                      context,
                                    ).textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    if (scaleResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Scales',
                            style: TextStyle(
                              color: StudioPalette.of(context).textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'tap to highlight',
                            style: TextStyle(
                              color: StudioPalette.of(context).textMuted,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: scaleResults.map((result) {
                            final chipKey =
                                '${result.root} ${result.scaleName}';
                            final isActive = _activeScaleChip == chipKey;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _tryApplyScale(
                                  result.root,
                                  result.scaleName,
                                  spelling,
                                );
                              },
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                alignment: Alignment.center,
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: isActive
                                      ? StudioPalette.of(context).emerald
                                      : StudioPalette.of(
                                          context,
                                        ).emerald.withValues(alpha: 0.10),
                                  border: Border.all(
                                    color: StudioPalette.of(context).emerald
                                        .withValues(
                                          alpha: isActive ? 1.0 : 0.35,
                                        ),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  formatScaleLabel(result, spelling: spelling),
                                  style: TextStyle(
                                    color: isActive
                                        ? StudioPalette.of(context).onAccent
                                        : StudioPalette.of(context).textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      'No exact match — try adding more notes.',
                      style: TextStyle(
                        color: StudioPalette.of(context).textMuted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (exactNotes.isNotEmpty &&
                      widget.onHandoffCompleted != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('addInstrumentSelectionToWriter'),
                        onPressed: canHandoff
                            ? () {
                                HapticFeedback.lightImpact();
                                startWriterHandoff(
                                  context: context,
                                  ref: ref,
                                  binding: widget.binding,
                                  chordResults: chordResults,
                                  onTransferComplete:
                                      widget.onHandoffCompleted!,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: const Text('Add to Writer'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: StudioPalette.of(context).sky,
                          side: BorderSide(
                            color: StudioPalette.of(
                              context,
                            ).sky.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                    if (!canHandoff && handoffUnavailableReason != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        handoffUnavailableReason,
                        key: const Key('writerHandoffUnavailableReason'),
                        style: TextStyle(
                          color: StudioPalette.of(context).textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(key: ValueKey(false)),
    );
  }

  Widget _content({
    required Key key,
    required EdgeInsets padding,
    required Widget child,
  }) {
    if (widget.embedded) {
      return Padding(key: key, padding: padding, child: child);
    }
    return SingleChildScrollView(key: key, padding: padding, child: child);
  }

  Future<void> _tryApplyScale(
    String root,
    String scaleName,
    NoteSpelling spelling,
  ) async {
    final chipKey = '$root $scaleName';
    final selectedFolder = ref.read(selectedProjectProvider);
    if (selectedFolder?.kind == SaveFolderKind.project) {
      final projectKey = ref.read(activeProjectKeyProvider);
      final config = selectedFolder!.projectConfig ?? const ProjectConfig();
      if (projectKey?.root == root && projectKey?.scaleName == scaleName) {
        if (_activeScaleChip != chipKey) {
          setState(() => _activeScaleChip = chipKey);
          return;
        }
        final cleared = await requestProjectKeyChange(
          context,
          ref,
          keyRootPc: null,
          keyScaleName: null,
          expectedProjectId: selectedFolder.id,
          expectedConfig: config,
        );
        if (!mounted) return;
        if (cleared) {
          setState(() => _activeScaleChip = null);
          ref.read(widget.binding.activeScale.notifier).state = null;
          ref.read(widget.binding.pendingScale.notifier).state = null;
        }
        return;
      }

      final changed = await requestProjectKeyChange(
        context,
        ref,
        keyRootPc: chromaticNotes.indexOf(root),
        keyScaleName: scaleName,
        expectedProjectId: selectedFolder.id,
        expectedConfig: config,
      );
      if (!mounted) return;
      if (changed) {
        setState(() => _activeScaleChip = chipKey);
        ref.read(widget.binding.activeScale.notifier).state = (
          root: root,
          scaleName: scaleName,
        );
        ref.read(widget.binding.pendingScale.notifier).state = null;
      } else {
        final confirmedKey = ref.read(activeProjectKeyProvider);
        setState(() {
          _activeScaleChip = confirmedKey == null
              ? null
              : '${confirmedKey.root} ${confirmedKey.scaleName}';
        });
      }
      return;
    }

    final expectedFolderId = selectedFolder?.id;
    final expectedFolderKind = selectedFolder?.kind;
    if (_activeScaleChip == chipKey) {
      setState(() => _activeScaleChip = null);
      widget.binding.selectionActions(ref).setHighlightedNotes([]);
      ref.read(widget.binding.activeScale.notifier).state = null;
      ref.read(widget.binding.pendingScale.notifier).state = null;
      return;
    }
    final scaleNotes = getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final conflicts = ref
        .read(widget.binding.selectedNotes)
        .where((n) => !scaleNotes.contains(n))
        .toList();
    if (conflicts.isEmpty) {
      setState(() => _activeScaleChip = chipKey);
      widget.binding.selectionActions(ref).setHighlightedNotes(scaleNotes);
      ref.read(widget.binding.pendingScale.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      ref.read(widget.binding.activeScale.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showStudioDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(
        conflictingNotes: conflicts
            .map((note) => formatRootChoiceLabel(note, spelling: spelling))
            .toList(),
      ),
    );
    final currentFolder = ref.read(selectedProjectProvider);
    if (!mounted ||
        currentFolder?.id != expectedFolderId ||
        currentFolder?.kind != expectedFolderKind) {
      return;
    }
    if (confirmed == true) {
      widget.binding.selectionActions(ref).removeNotesByPitchClass(conflicts);
      setState(() => _activeScaleChip = chipKey);
      widget.binding.selectionActions(ref).setHighlightedNotes(scaleNotes);
      ref.read(widget.binding.pendingScale.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      ref.read(widget.binding.activeScale.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
    }
  }
}
