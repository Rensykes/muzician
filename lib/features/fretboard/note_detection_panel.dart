/// NoteDetectionPanel – displays tapped pitch classes and detects matching
/// chords and scales using music_notes. Includes a "Clear" action.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';

({String root, String quality})? _parseChordString(String chordStr) {
  if (chordStr.isEmpty) return null;
  String root;
  String quality;
  if (chordStr.length > 1 && chordStr[1] == '#') {
    root = chordStr.substring(0, 2);
    quality = chordStr.substring(2);
  } else {
    root = chordStr.substring(0, 1);
    quality = chordStr.substring(1);
  }
  return (root: toSharp(root), quality: quality);
}

({String root, String scaleName})? _parseScaleString(String scaleStr) {
  final parts = scaleStr.split(' ');
  if (parts.length < 2) return null;
  final root = toSharp(parts[0]);
  final scaleName = parts.sublist(1).join(' ');
  return (root: root, scaleName: scaleName);
}

class NoteDetectionPanel extends ConsumerWidget {
  const NoteDetectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);

    if (state.selectedNotes.isEmpty) return const SizedBox.shrink();

    final detection = detectChordsAndScales(state.selectedNotes);
    final hasResults =
        detection.chords.isNotEmpty || detection.scales.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'DETECTION',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => notifier.clearSelectedNotes(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
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
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Selected notes chips
          Row(
            children: [
              const SizedBox(
                width: 36,
                child: Text(
                  'Notes',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: state.selectedNotes.map((note) {
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: MuzicianTheme.sky.withValues(alpha: 0.15),
                          border: Border.all(
                            color: MuzicianTheme.sky.withValues(alpha: 0.45),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          note,
                          style: const TextStyle(
                            color: MuzicianTheme.sky,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Results
          if (state.selectedNotes.length < 2)
            const Text(
              'Tap at least 2 notes to detect.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (hasResults) ...[
            if (detection.chords.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    'Chords',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'tap to select voicing',
                    style: TextStyle(
                      color: Color(0xFF334155),
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
                  children: detection.chords.map((c) {
                    return GestureDetector(
                      onTap: () {
                        final parsed = _parseChordString(c);
                        if (parsed == null) return;
                        HapticFeedback.lightImpact();
                        ref.read(pendingChordProvider.notifier).state = (
                          root: parsed.root,
                          quality: parsed.quality,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0x1FC084FC),
                          border: Border.all(
                            color: const Color(0x66C084FC),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          c,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
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
            if (detection.scales.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Scales',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'tap to highlight',
                    style: TextStyle(
                      color: Color(0xFF334155),
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
                  children: detection.scales.map((s) {
                    return GestureDetector(
                      onTap: () {
                        final parsed = _parseScaleString(s);
                        if (parsed == null) return;
                        HapticFeedback.lightImpact();
                        ref.read(pendingScaleProvider.notifier).state = (
                          root: parsed.root,
                          scaleName: parsed.scaleName,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: MuzicianTheme.emerald.withValues(alpha: 0.10),
                          border: Border.all(
                            color: MuzicianTheme.emerald.withValues(
                              alpha: 0.35,
                            ),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          s,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
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
            const Text(
              'No exact match — try adding more notes.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
