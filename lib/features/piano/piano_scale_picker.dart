/// PianoScalePicker – root + scale type selector for piano highlighting.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';

const _rootNotes = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
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

const _chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

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

List<String> _getScaleNotes(String root, String scaleName) {
  final rootIdx = _chromatic.indexOf(root);
  if (rootIdx < 0) return [];
  final intervals = _scaleIntervals[scaleName];
  if (intervals == null) return [];
  return intervals.map((i) => _chromatic[(rootIdx + i) % 12]).toList();
}

class PianoScalePicker extends ConsumerStatefulWidget {
  const PianoScalePicker({super.key});

  @override
  ConsumerState<PianoScalePicker> createState() => _PianoScalePickerState();
}

class _PianoScalePickerState extends ConsumerState<PianoScalePicker> {
  String? _selectedRoot;
  String? _selectedScale;
  _ScaleCategory _activeCategory = _ScaleCategory.common;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(pianoProvider.notifier);
    final state = ref.watch(pianoProvider);
    // Reset pills if highlight was cleared from outside (e.g. out-of-key guard).
    ref.listen(
      pianoProvider.select((s) => s.highlightedNotes),
      (prev, next) {
        if (next.isEmpty && (prev?.isNotEmpty ?? false)) {
          setState(() {
            _selectedRoot = null;
            _selectedScale = null;
          });
        }
      },
    );
    final isActive = state.highlightedNotes.isNotEmpty &&
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
              const Text('Scale',
                  style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14), width: 0.5),
                    ),
                    child: const Text('Clear',
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                )
              else
                const Text('Pick root + scale',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          // Root pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _rootNotes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
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
                    child: Text(note,
                        style: TextStyle(
                          color: active
                              ? MuzicianTheme.sky
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Category tabs
          Row(
            children: _ScaleCategory.values.map((cat) {
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
                        _catLabel[cat]!,
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
              itemCount: (_scaleGroups[_activeCategory] ?? []).length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final scales = _scaleGroups[_activeCategory]!;
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
                        horizontal: 10, vertical: 6),
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
                    child: Text(label,
                        style: TextStyle(
                          color: active
                              ? MuzicianTheme.sky
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
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
    final scaleNotes = _getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final currentSelected = ref.read(pianoProvider).selectedNotes;
    final conflicts =
        currentSelected.where((n) => !scaleNotes.contains(n)).toList();
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
      builder: (ctx) => _ScaleConflictDialog(conflictingNotes: conflicts),
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
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove & Apply',
              style: TextStyle(
                  color: MuzicianTheme.sky,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
