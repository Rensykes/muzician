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
import '../../store/project_config_sync.dart';
import '../../store/save_system_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../ui/core/update_project_key_dialog.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';

Color _categoryColor(BuildContext context, ScaleCategory category) =>
    switch (category) {
      ScaleCategory.common => StudioPalette.of(context).sky,
      ScaleCategory.modes => StudioPalette.of(context).violet,
      ScaleCategory.extended => StudioPalette.of(context).emerald,
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
  int _scaleSyncRevision = 0;

  void _clearLocalScale() {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedRoot = null;
      _selectedScale = null;
      _initialSyncDone = false;
    });
    widget.binding.actions(ref).setHighlightedNotes([]);
    ref.read(widget.binding.activeScale.notifier).state = null;
  }

  bool _samePitchClassSet(List<String> a, List<String> b) {
    final left = a.toSet();
    final right = b.toSet();
    return left.length == right.length && left.containsAll(right);
  }

  @override
  Widget build(BuildContext context) {
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final highlightedNotes = ref.watch(widget.binding.highlightedNotes);
    final pendingScale = ref.watch(widget.binding.pendingScale);
    final activeScaleRaw = ref.watch(widget.binding.activeScale);
    final selectedFolder = ref.watch(selectedProjectProvider);
    final projectKey = ref.watch(activeProjectKeyProvider);
    final isProject = selectedFolder?.kind == SaveFolderKind.project;
    final activeScale = isProject ? projectKey : activeScaleRaw;
    final isProjectLocked = isProject && projectKey != null;
    final binding = widget.binding;
    final chordOffKey = binding is InstrumentBinding
        ? ref.watch(binding.chordOffKey)
        : false;
    final chipColor = chordOffKey && isProjectLocked
        ? StudioPalette.of(context).orange
        : StudioPalette.of(context).emerald;

    // Re-run initial sync when the selected project changes, including when
    // both the old and new projects have no key.
    ref.listen(selectedProjectProvider, (_, _) {
      _scaleSyncRevision++;
      _initialSyncDone = false;
      final folder = ref.read(selectedProjectProvider);
      final key = ref.read(activeProjectKeyProvider);
      setState(() {
        _selectedRoot = key?.root;
        _selectedScale = key?.scaleName;
        if (folder?.kind == SaveFolderKind.project && key == null) {
          _selectedRoot = null;
          _selectedScale = null;
        }
      });
    });

    // Restore from committed active state once per widget lifecycle.
    if (!_initialSyncDone && activeScale != null && pendingScale == null) {
      final notes = getScaleNotes(activeScale.root, activeScale.scaleName);
      final highlightLooksStale =
          highlightedNotes.isNotEmpty &&
          notes.isNotEmpty &&
          !_samePitchClassSet(highlightedNotes, notes);
      final expectedFolderId = selectedFolder?.id;
      final expectedProjectKey = projectKey;
      final expectedRevision = ++_scaleSyncRevision;
      _initialSyncDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (expectedRevision != _scaleSyncRevision ||
            ref.read(selectedProjectProvider)?.id != expectedFolderId ||
            ref.read(activeProjectKeyProvider) != expectedProjectKey) {
          return;
        }
        if (highlightLooksStale && !isProject) {
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
      final expectedFolderId = selectedFolder?.id;
      final expectedRevision = ++_scaleSyncRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            expectedRevision != _scaleSyncRevision ||
            ref.read(selectedProjectProvider)?.id != expectedFolderId) {
          return;
        }
        if (isProject) {
          // Detection results are a local preview. A project key can change
          // only through the confirmed ProjectConfig path.
          ref.read(widget.binding.pendingScale.notifier).state = null;
          return;
        }
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
              Text(
                'SCALE',
                style: TextStyle(
                  color: StudioPalette.of(context).textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              if (isActive)
                Flexible(
                  child: Container(
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
                        Flexible(
                          child: Text(
                            formatScaleLabel(
                              ScaleDetectionResult(
                                root: _selectedRoot!,
                                scaleName: _selectedScale!,
                              ),
                              spelling: spelling,
                            ),
                            style: TextStyle(
                              color: chipColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
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
                          const SizedBox(width: 2),
                          IconButton(
                            key: const Key('sharedScaleClearProjectKey'),
                            tooltip: 'Clear project key',
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _clearProjectKey,
                            icon: const Icon(Icons.close_rounded, size: 16),
                          ),
                        ] else ...[
                          const SizedBox(width: 6),
                          Semantics(
                            key: const Key('sharedScaleLocalClear'),
                            button: true,
                            label: 'Clear scale selection',
                            onTap: _clearLocalScale,
                            child: ExcludeSemantics(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _clearLocalScale,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
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
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Pick root + scale to highlight',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: StudioPalette.of(context).textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Root pills
        SizedBox(
          height: 44,
          child: ListView.separated(
            key: const Key('sharedScaleRootList'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: chromaticNotes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final note = chromaticNotes[i];
              final active = note == _selectedRoot;
              return ConstrainedBox(
                key: ValueKey('sharedScaleRoot_$note'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final newRoot = note == _selectedRoot ? null : note;
                    if (newRoot == null) {
                      if (isProject && projectKey != null) {
                        setState(() => _selectedRoot = projectKey.root);
                      } else {
                        setState(() => _selectedRoot = null);
                        widget.binding.actions(ref).setHighlightedNotes([]);
                      }
                    } else if (_selectedScale != null) {
                      _tryApplyScale(newRoot, _selectedScale!, spelling);
                    } else {
                      setState(() => _selectedRoot = newRoot);
                    }
                  },
                  child: Center(
                    child: Container(
                      key: ValueKey('sharedScaleRootArtwork_$note'),
                      constraints: const BoxConstraints(minWidth: 42),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: active
                            ? StudioPalette.of(
                                context,
                              ).emerald.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: active
                              ? StudioPalette.of(context).emerald
                              : Colors.white.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        formatRootChoiceLabel(note, spelling: spelling),
                        style: TextStyle(
                          color: active
                              ? StudioPalette.of(context).emerald
                              : StudioPalette.of(context).textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
              final c = _categoryColor(context, cat);
              void selectCategory() => setState(() => _activeCategory = cat);

              return Expanded(
                child: Semantics(
                  key: ValueKey('sharedScaleCategory_${cat.name}'),
                  button: true,
                  selected: isTab,
                  label: scaleCategoryLabels[cat]!,
                  onTap: selectCategory,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selectCategory,
                      child: SizedBox(
                        height: 44,
                        child: DecoratedBox(
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
                                color: isTab
                                    ? c
                                    : StudioPalette.of(context).textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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
          height: 44,
          child: ListView.separated(
            key: const Key('sharedScaleTypeList'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: scalesForCategory.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final (name, label) = scalesForCategory[i];
              final active = name == _selectedScale;
              return ConstrainedBox(
                key: ValueKey('sharedScaleType_$name'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final newScale = name == _selectedScale ? null : name;
                    if (newScale == null) {
                      if (isProject && projectKey != null) {
                        setState(() => _selectedScale = projectKey.scaleName);
                      } else {
                        setState(() => _selectedScale = null);
                        widget.binding.actions(ref).setHighlightedNotes([]);
                      }
                    } else if (_selectedRoot != null) {
                      _tryApplyScale(_selectedRoot!, newScale, spelling);
                    } else {
                      setState(() => _selectedScale = newScale);
                    }
                  },
                  child: Center(
                    child: Container(
                      key: ValueKey('sharedScaleTypeArtwork_$name'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: active
                            ? StudioPalette.of(
                                context,
                              ).emerald.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: active
                              ? StudioPalette.of(context).emerald
                              : Colors.white.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: active
                              ? StudioPalette.of(context).emerald
                              : StudioPalette.of(context).textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Future<void> _tryApplyScale(
    String root,
    String scaleName,
    NoteSpelling spelling,
  ) async {
    final scaleNotes = getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final folder = ref.read(selectedProjectProvider);
    if (folder?.kind == SaveFolderKind.project) {
      final projectKey = ref.read(activeProjectKeyProvider);
      if (projectKey?.root == root && projectKey?.scaleName == scaleName) {
        setState(() {
          _selectedRoot = root;
          _selectedScale = scaleName;
        });
        return;
      }
      final config = folder!.projectConfig ?? const ProjectConfig();
      final applied = await requestProjectKeyChange(
        context,
        ref,
        keyRootPc: chromaticNotes.indexOf(root),
        keyScaleName: scaleName,
        expectedProjectId: folder.id,
        expectedConfig: config,
      );
      if (!mounted) return;
      if (applied) {
        setState(() {
          _selectedRoot = root;
          _selectedScale = scaleName;
          _initialSyncDone = false;
        });
      } else {
        final confirmedKey = ref.read(activeProjectKeyProvider);
        setState(() {
          _selectedRoot = confirmedKey?.root;
          _selectedScale = confirmedKey?.scaleName;
          _initialSyncDone = false;
        });
      }
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
        currentFolder?.id != folder?.id ||
        currentFolder?.kind != folder?.kind) {
      return;
    }
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

  Future<void> _clearProjectKey() async {
    final folder = ref.read(selectedProjectProvider);
    if (folder == null || folder.kind != SaveFolderKind.project) return;
    final config = folder.projectConfig ?? const ProjectConfig();
    await requestProjectKeyChange(
      context,
      ref,
      keyRootPc: null,
      keyScaleName: null,
      expectedProjectId: folder.id,
      expectedConfig: config,
    );
  }
}
