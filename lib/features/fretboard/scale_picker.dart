/// ScalePicker – root note + scale type selector that highlights pitch classes
/// across the fretboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../utils/note_utils.dart';

const _catColor = {
  ScaleCategory.common: MuzicianTheme.sky,
  ScaleCategory.modes: MuzicianTheme.violet,
  ScaleCategory.extended: MuzicianTheme.emerald,
};

class ScalePicker extends ConsumerStatefulWidget {
  const ScalePicker({super.key});

  @override
  ConsumerState<ScalePicker> createState() => _ScalePickerState();
}

class _ScalePickerState extends ConsumerState<ScalePicker> {
  String? _selectedRoot;
  String? _selectedScale;
  ScaleCategory _activeCategory = ScaleCategory.common;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final pendingScale = ref.watch(pendingScaleProvider);

    // Sync from detection panel
    if (pendingScale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Find category
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
        });
        // Apply highlight
        final notes = getScaleNotes(pendingScale.root, pendingScale.scaleName);
        if (notes.isNotEmpty) notifier.setHighlightedNotes(notes);
        ref.read(pendingScaleProvider.notifier).state = null;
      });
    }

    // Reset pills if highlight was cleared from outside (e.g. out-of-key guard).
    ref.listen(fretboardProvider.select((s) => s.highlightedNotes), (
      prev,
      next,
    ) {
      if (next.isEmpty && (prev?.isNotEmpty ?? false)) {
        setState(() {
          _selectedRoot = null;
          _selectedScale = null;
        });
      }
    });
    final activeColor = _catColor[_activeCategory]!;
    final scalesForCategory = scaleGroups[_activeCategory] ?? [];
    final isActive =
        state.highlightedNotes.isNotEmpty &&
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
                    color: MuzicianTheme.sky.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: MuzicianTheme.sky.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_selectedRoot ${scaleGroups.values.expand((v) => v).firstWhere((s) => s.$1 == _selectedScale, orElse: () => (_selectedScale!, _selectedScale!)).$2}',
                        style: const TextStyle(
                          color: MuzicianTheme.sky,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _selectedRoot = null;
                            _selectedScale = null;
                          });
                          notifier.setHighlightedNotes([]);
                        },
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MuzicianTheme.sky.withValues(alpha: 0.2),
                          ),
                          child: const Center(
                            child: Text(
                              '✕',
                              style: TextStyle(
                                color: MuzicianTheme.sky,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
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
                    notifier.setHighlightedNotes([]);
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
                        ? MuzicianTheme.sky.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.sky
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    note,
                    style: TextStyle(
                      color: active
                          ? MuzicianTheme.sky
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
                    notifier.setHighlightedNotes([]);
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
                        ? activeColor.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? activeColor
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: active ? activeColor : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _tryApplyScale(String root, String scaleName) async {
    final scaleNotes = getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final currentSelected = ref.read(fretboardProvider).selectedNotes;
    final conflicts = currentSelected
        .where((n) => !scaleNotes.contains(n))
        .toList();
    if (conflicts.isEmpty) {
      setState(() {
        _selectedRoot = root;
        _selectedScale = scaleName;
      });
      ref.read(fretboardProvider.notifier).setHighlightedNotes(scaleNotes);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(conflictingNotes: conflicts),
    );
    if (confirmed == true) {
      ref.read(fretboardProvider.notifier).removeNotesByPitchClass(conflicts);
      setState(() {
        _selectedRoot = root;
        _selectedScale = scaleName;
      });
      ref.read(fretboardProvider.notifier).setHighlightedNotes(scaleNotes);
    }
  }
}


