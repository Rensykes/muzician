/// PianoScalePicker – root + scale type selector for piano highlighting.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../utils/note_utils.dart';

class PianoScalePicker extends ConsumerStatefulWidget {
  const PianoScalePicker({super.key});

  @override
  ConsumerState<PianoScalePicker> createState() => _PianoScalePickerState();
}

class _PianoScalePickerState extends ConsumerState<PianoScalePicker> {
  String? _selectedRoot;
  String? _selectedScale;
  ScaleCategory _activeCategory = ScaleCategory.common;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(pianoProvider.notifier);
    final state = ref.watch(pianoProvider);
    // Sync from detection panel: consume pianoPendingScaleProvider.
    final pendingScale = ref.watch(pianoPendingScaleProvider);
    if (pendingScale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
        final notes = getScaleNotes(pendingScale.root, pendingScale.scaleName);
        if (notes.isNotEmpty) notifier.setHighlightedNotes(notes);
        ref.read(pianoPendingScaleProvider.notifier).state = null;
      });
    }
    // Reset pills if highlight was cleared from outside (e.g. out-of-key guard).
    ref.listen(pianoProvider.select((s) => s.highlightedNotes), (prev, next) {
      if (next.isEmpty && (prev?.isNotEmpty ?? false)) {
        setState(() {
          _selectedRoot = null;
          _selectedScale = null;
        });
      }
    });
    final isActive =
        state.highlightedNotes.isNotEmpty &&
        _selectedRoot != null &&
        _selectedScale != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Scale',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (isActive)
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else
                const Text(
                  'Pick root + scale',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Root pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chromaticNotes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: active
                          ? MuzicianTheme.sky.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: active
                            ? MuzicianTheme.sky.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.14),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      note,
                      style: TextStyle(
                        color: active
                            ? MuzicianTheme.sky
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Category tabs
          Row(
            children: ScaleCategory.values.map((cat) {
              final isTab = cat == _activeCategory;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isTab ? MuzicianTheme.sky : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        scaleCategoryLabels[cat]!,
                        style: TextStyle(
                          color: isTab
                              ? MuzicianTheme.sky
                              : const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Scale pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: (scaleGroups[_activeCategory] ?? []).length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final scales = scaleGroups[_activeCategory]!;
                final (name, label) = scales[i];
                final active = _selectedScale == name;
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: active
                          ? MuzicianTheme.sky.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: active
                            ? MuzicianTheme.sky.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.14),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? MuzicianTheme.sky
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _tryApplyScale(String root, String scaleName) async {
    final scaleNotes = getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final currentSelected = ref.read(pianoProvider).selectedNotes;
    final conflicts = currentSelected
        .where((n) => !scaleNotes.contains(n))
        .toList();
    if (conflicts.isEmpty) {
      setState(() {
        _selectedRoot = root;
        _selectedScale = scaleName;
      });
      ref.read(pianoProvider.notifier).setHighlightedNotes(scaleNotes);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(conflictingNotes: conflicts),
    );
    if (confirmed == true) {
      ref.read(pianoProvider.notifier).removeNotesByPitchClass(conflicts);
      setState(() {
        _selectedRoot = root;
        _selectedScale = scaleName;
      });
      ref.read(pianoProvider.notifier).setHighlightedNotes(scaleNotes);
    }
  }
}


