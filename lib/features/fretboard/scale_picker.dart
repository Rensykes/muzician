/// ScalePicker – root note + scale type selector that highlights pitch classes
/// across the fretboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';

const _rootNotes = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

enum _ScaleCategory { common, modes, extended }

const _scaleGroups = <_ScaleCategory, List<(String name, String label)>>{
  _ScaleCategory.common: [
    ('major', 'Major'),
    ('minor', 'Minor'),
    ('major pentatonic', 'Pent. Maj'),
    ('minor pentatonic', 'Pent. Min'),
    ('blues', 'Blues'),
  ],
  _ScaleCategory.modes: [
    ('dorian', 'Dorian'),
    ('phrygian', 'Phrygian'),
    ('lydian', 'Lydian'),
    ('mixolydian', 'Mixolydian'),
    ('locrian', 'Locrian'),
  ],
  _ScaleCategory.extended: [
    ('harmonic minor', 'Harm. Min'),
    ('melodic minor', 'Mel. Min'),
    ('whole tone', 'Whole Tone'),
    ('diminished', 'Diminished'),
  ],
};

const _catLabel = {
  _ScaleCategory.common: 'Common',
  _ScaleCategory.modes: 'Modes',
  _ScaleCategory.extended: 'Extended',
};

const _catColor = {
  _ScaleCategory.common: MuzicianTheme.sky,
  _ScaleCategory.modes: MuzicianTheme.violet,
  _ScaleCategory.extended: MuzicianTheme.emerald,
};

// Scale interval definitions in semitones from root
const _scaleIntervals = <String, List<int>>{
  'major': [0, 2, 4, 5, 7, 9, 11],
  'minor': [0, 2, 3, 5, 7, 8, 10],
  'major pentatonic': [0, 2, 4, 7, 9],
  'minor pentatonic': [0, 3, 5, 7, 10],
  'blues': [0, 3, 5, 6, 7, 10],
  'dorian': [0, 2, 3, 5, 7, 9, 10],
  'phrygian': [0, 1, 3, 5, 7, 8, 10],
  'lydian': [0, 2, 4, 6, 7, 9, 11],
  'mixolydian': [0, 2, 4, 5, 7, 9, 10],
  'locrian': [0, 1, 3, 5, 6, 8, 10],
  'harmonic minor': [0, 2, 3, 5, 7, 8, 11],
  'melodic minor': [0, 2, 3, 5, 7, 9, 11],
  'whole tone': [0, 2, 4, 6, 8, 10],
  'diminished': [0, 2, 3, 5, 6, 8, 9, 11],
};

const _chromatic = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

List<String> _getScaleNotes(String root, String scaleName) {
  final rootIdx = _chromatic.indexOf(root);
  if (rootIdx < 0) return [];
  final intervals = _scaleIntervals[scaleName];
  if (intervals == null) return [];
  return intervals.map((i) => _chromatic[(rootIdx + i) % 12]).toList();
}

class ScalePicker extends ConsumerStatefulWidget {
  const ScalePicker({super.key});

  @override
  ConsumerState<ScalePicker> createState() => _ScalePickerState();
}

class _ScalePickerState extends ConsumerState<ScalePicker> {
  String? _selectedRoot;
  String? _selectedScale;
  _ScaleCategory _activeCategory = _ScaleCategory.common;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final pendingScale = ref.watch(pendingScaleProvider);

    // Sync from detection panel
    if (pendingScale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Find category
        var cat = _ScaleCategory.common;
        for (final entry in _scaleGroups.entries) {
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
        final notes = _getScaleNotes(pendingScale.root, pendingScale.scaleName);
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
    final scalesForCategory = _scaleGroups[_activeCategory] ?? [];
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
                        '$_selectedRoot ${_scaleGroups.values.expand((v) => v).firstWhere((s) => s.$1 == _selectedScale, orElse: () => (_selectedScale!, _selectedScale!)).$2}',
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
            itemCount: _rootNotes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final note = _rootNotes[i];
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
            children: _ScaleCategory.values.map((cat) {
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
                        _catLabel[cat]!,
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
    final scaleNotes = _getScaleNotes(root, scaleName);
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
      builder: (ctx) => _ScaleConflictDialog(conflictingNotes: conflicts),
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

// ─── Scale Conflict Dialog ─────────────────────────────────────────────────────

class _ScaleConflictDialog extends StatelessWidget {
  final List<String> conflictingNotes;
  const _ScaleConflictDialog({required this.conflictingNotes});

  @override
  Widget build(BuildContext context) {
    final noteStr = conflictingNotes.join(', ');
    final isPlural = conflictingNotes.length > 1;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Notes outside the key',
        style: TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        '${isPlural ? 'Notes' : 'Note'} $noteStr '
        '${isPlural ? 'are' : 'is'} outside this scale. '
        'Remove ${isPlural ? 'them' : 'it'} to apply the scale highlight?',
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Remove & Apply',
            style: TextStyle(
              color: MuzicianTheme.sky,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
