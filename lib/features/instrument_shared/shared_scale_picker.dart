/// SharedScalePicker – binding-parameterized root note + scale type selector
/// that highlights pitch-class rows across any instrument grid. Verbatim port
/// of the Piano Roll scale picker, generalized over [ScalePickerBinding].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../models/project_config.dart';
import '../../models/save_system.dart';
import '../../schema/rules/save_system_rules.dart';
import '../../store/project_config_sync.dart';
import '../../store/save_system_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../ui/core/update_project_key_dialog.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';

const _catColor = {
  ScaleCategory.common: MuzicianTheme.sky,
  ScaleCategory.modes: MuzicianTheme.violet,
  ScaleCategory.extended: MuzicianTheme.emerald,
};

class SharedScalePicker extends ConsumerStatefulWidget {
  final ScalePickerBinding binding;

  const SharedScalePicker({super.key, required this.binding});

  @override
  ConsumerState<SharedScalePicker> createState() => _SharedScalePickerState();
}

class _SharedScalePickerState extends ConsumerState<SharedScalePicker> {
  String? _selectedRoot;
  String? _selectedScale;
  ScaleCategory _activeCategory = ScaleCategory.common;
  bool _initialSyncDone = false;

  bool _samePitchClassSet(List<String> a, List<String> b) {
    final left = a.toSet();
    final right = b.toSet();
    return left.length == right.length && left.containsAll(right);
  }

  @override
  Widget build(BuildContext context) {
    final highlightedNotes = ref.watch(widget.binding.highlightedNotes);
    final pendingScale = ref.watch(widget.binding.pendingScale);
    final activeScaleRaw = ref.watch(widget.binding.activeScale);
    final projectKey = ref.watch(activeProjectKeyProvider);
    final activeScale = activeScaleRaw ?? projectKey;
    final isProjectLocked = projectKey != null;
    final binding = widget.binding;
    final chordOffKey = binding is InstrumentBinding
        ? ref.watch(binding.chordOffKey)
        : false;
    final chipColor = chordOffKey && isProjectLocked
        ? MuzicianTheme.orange
        : MuzicianTheme.emerald;

    // Re-run initial sync when the project key changes (e.g. user switched
    // projects between sheet opens), so the pills reflect the new locked key.
    ref.listen(activeProjectKeyProvider, (_, _) {
      _initialSyncDone = false;
    });

    // Restore from committed active state once per widget lifecycle.
    if (!_initialSyncDone && activeScale != null && pendingScale == null) {
      final notes = getScaleNotes(activeScale.root, activeScale.scaleName);
      final highlightLooksStale =
          highlightedNotes.isNotEmpty &&
          notes.isNotEmpty &&
          !_samePitchClassSet(highlightedNotes, notes);
      _initialSyncDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (highlightLooksStale) {
          ref.read(widget.binding.activeScale.notifier).state = null;
          setState(() {
            _selectedRoot = null;
            _selectedScale = null;
          });
          return;
        }
        var cat = ScaleCategory.common;
        for (final entry in scaleGroups.entries) {
          if (entry.value.any((s) => s.$1 == activeScale.scaleName)) {
            cat = entry.key;
            break;
          }
        }
        setState(() {
          _selectedRoot = activeScale.root;
          _selectedScale = activeScale.scaleName;
          _activeCategory = cat;
        });
        if (notes.isNotEmpty) {
          widget.binding.actions(ref).setHighlightedNotes(notes);
        }
      });
    }

    // Sync from detection panel
    if (pendingScale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        var cat = ScaleCategory.common;
        for (final entry in scaleGroups.entries) {
          if (entry.value.any((s) => s.$1 == pendingScale.scaleName)) {
            cat = entry.key;
            break;
          }
        }
        setState(() {
          _selectedRoot = pendingScale.root;
          _selectedScale = pendingScale.scaleName;
          _activeCategory = cat;
          _initialSyncDone = true;
        });
        final notes = getScaleNotes(pendingScale.root, pendingScale.scaleName);
        if (notes.isNotEmpty) {
          widget.binding.actions(ref).setHighlightedNotes(notes);
        }
        ref.read(widget.binding.activeScale.notifier).state = pendingScale;
        ref.read(widget.binding.pendingScale.notifier).state = null;
      });
    }

    // Reset pills if highlight was cleared from outside.
    ref.listen(widget.binding.highlightedNotes, (prev, next) {
      if (next.isEmpty && (prev?.isNotEmpty ?? false)) {
        setState(() {
          _selectedRoot = null;
          _selectedScale = null;
          _initialSyncDone = false;
        });
        ref.read(widget.binding.activeScale.notifier).state = null;
      }
    });

    final scalesForCategory = scaleGroups[_activeCategory] ?? [];
    final isActive =
        highlightedNotes.isNotEmpty &&
        _selectedRoot != null &&
        _selectedScale != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              const Text(
                'SCALE',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: chipColor.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatScaleLabel(
                          ScaleDetectionResult(
                            root: _selectedRoot!,
                            scaleName: _selectedScale!,
                          ),
                        ),
                        style: TextStyle(
                          color: chipColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isProjectLocked) ...[
                        const SizedBox(width: 6),
                        Icon(
                          chordOffKey
                              ? Icons.warning_amber_rounded
                              : Icons.lock_outline_rounded,
                          size: 12,
                          color: chipColor,
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _selectedRoot = null;
                              _selectedScale = null;
                              _initialSyncDone = false;
                            });
                            widget.binding.actions(ref).setHighlightedNotes([]);
                            ref
                                    .read(widget.binding.activeScale.notifier)
                                    .state =
                                null;
                          },
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: chipColor.withValues(alpha: 0.2),
                            ),
                            child: Center(
                              child: Text(
                                '✕',
                                style: TextStyle(
                                  color: chipColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                const Text(
                  'Pick root + scale to highlight',
                  style: TextStyle(color: Color(0xFF334155), fontSize: 11),
                ),
            ],
          ),
        ),
        // Root pills
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: chromaticNotes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final note = chromaticNotes[i];
              final active = note == _selectedRoot;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final newRoot = note == _selectedRoot ? null : note;
                  if (newRoot == null) {
                    setState(() => _selectedRoot = null);
                    widget.binding.actions(ref).setHighlightedNotes([]);
                  } else if (_selectedScale != null) {
                    _tryApplyScale(newRoot, _selectedScale!);
                  } else {
                    setState(() => _selectedRoot = newRoot);
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minWidth: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: active
                        ? MuzicianTheme.emerald.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.emerald
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    note,
                    style: TextStyle(
                      color: active
                          ? MuzicianTheme.emerald
                          : const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Category tabs
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: ScaleCategory.values.map((cat) {
              final isTab = cat == _activeCategory;
              final c = _catColor[cat]!;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isTab ? c : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        scaleCategoryLabels[cat]!,
                        style: TextStyle(
                          color: isTab ? c : const Color(0xFF475569),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Scale pills
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: scalesForCategory.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final (name, label) = scalesForCategory[i];
              final active = name == _selectedScale;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final newScale = name == _selectedScale ? null : name;
                  if (newScale == null) {
                    setState(() => _selectedScale = null);
                    widget.binding.actions(ref).setHighlightedNotes([]);
                  } else if (_selectedRoot != null) {
                    _tryApplyScale(_selectedRoot!, newScale);
                  } else {
                    setState(() => _selectedScale = newScale);
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: active
                        ? MuzicianTheme.emerald.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.emerald
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: active
                          ? MuzicianTheme.emerald
                          : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _tryApplyScale(String root, String scaleName) async {
    final scaleNotes = getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final projectKey = ref.read(activeProjectKeyProvider);
    if (projectKey != null) {
      if (projectKey.root == root && projectKey.scaleName == scaleName) {
        setState(() {
          _selectedRoot = root;
          _selectedScale = scaleName;
        });
        return;
      }
      await _promoteToProjectKey(root, scaleName);
      return;
    }
    final scaleSet = scaleNotes.toSet();
    final conflicts = ref
        .read(widget.binding.selectedPitchClasses)
        .toSet()
        .where((pc) => !scaleSet.contains(pc))
        .toList();
    if (conflicts.isEmpty) {
      setState(() {
        _selectedRoot = root;
        _selectedScale = scaleName;
      });
      widget.binding.actions(ref).setHighlightedNotes(scaleNotes);
      ref.read(widget.binding.activeScale.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(conflictingNotes: conflicts),
    );
    if (confirmed == true) {
      widget.binding.actions(ref).removeNotesByPitchClass(conflicts);
      setState(() {
        _selectedRoot = root;
        _selectedScale = scaleName;
      });
      widget.binding.actions(ref).setHighlightedNotes(scaleNotes);
      ref.read(widget.binding.activeScale.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
    }
  }

  Future<void> _promoteToProjectKey(String root, String scaleName) async {
    final folder = ref.read(selectedProjectProvider);
    if (folder == null || folder.kind != SaveFolderKind.project) return;
    final saveState = ref.read(saveSystemProvider);
    final affected = getSavesInSubtree(
      saveState.folders,
      saveState.saves,
      folder.id,
    ).length;
    final rootPc = chromaticNotes.indexOf(root);
    if (rootPc < 0) return;
    final currentLabel = formatScaleLabel(
      ScaleDetectionResult(
        root: _selectedRoot ?? root,
        scaleName: _selectedScale ?? scaleName,
      ),
    );
    final projectKey = ref.read(activeProjectKeyProvider);
    final fromLabel = projectKey != null
        ? formatScaleLabel(
            ScaleDetectionResult(
              root: projectKey.root,
              scaleName: projectKey.scaleName,
            ),
          )
        : currentLabel;
    final newLabel = formatScaleLabel(
      ScaleDetectionResult(root: root, scaleName: scaleName),
    );
    if (!mounted) return;
    final confirmed = await UpdateProjectKeyDialog.ask(
      context,
      currentLabel: fromLabel,
      newLabel: newLabel,
      affectedSaves: affected,
    );
    if (!confirmed) return;
    final current = folder.projectConfig ?? const ProjectConfig();
    final next = current.copyWith(
      keyRootPc: rootPc,
      keyScaleName: scaleName,
    );
    await ref
        .read(saveSystemProvider.notifier)
        .applyProjectConfig(folder.id, next, retrofit: true);
  }
}
