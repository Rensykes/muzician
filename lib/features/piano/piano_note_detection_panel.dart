/// PianoNoteDetectionPanel – detects chords/scales from selected piano keys.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';

class PianoNoteDetectionPanel extends ConsumerWidget {
  const PianoNoteDetectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);

    if (state.selectedNotes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 14,
              color: MuzicianTheme.textDim,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap keys on the keyboard to detect chords & scales.',
                style: TextStyle(
                  color: MuzicianTheme.textDim,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final detection = detectChordsAndScales(state.selectedNotes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          // Notes chips
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
                    children: state.selectedNotes
                        .map(
                          (n) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: MuzicianTheme.sky.withValues(alpha: 0.15),
                              border: Border.all(
                                color: MuzicianTheme.sky.withValues(
                                  alpha: 0.45,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              n,
                              style: const TextStyle(
                                color: MuzicianTheme.sky,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.selectedNotes.length < 2)
            const Text(
              'Tap at least 2 notes to detect.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            if (detection.chords.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    'Chords',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
                  children: detection.chords
                      .map(
                        (c) => GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(pianoPendingChordProvider.notifier)
                                .state = (
                              root: _parseRoot(c),
                              quality: _parseQuality(c),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: MuzicianTheme.emerald.withValues(
                                alpha: 0.12,
                              ),
                              border: Border.all(
                                color: MuzicianTheme.emerald.withValues(
                                  alpha: 0.45,
                                ),
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
                        ),
                      )
                      .toList(),
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
                  children: detection.scales
                      .map(
                        (s) => GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final parts = s.split(' ');
                            if (parts.length >= 2) {
                              ref
                                  .read(pianoPendingScaleProvider.notifier)
                                  .state = (
                                root: parts[0],
                                scaleName: parts.sublist(1).join(' '),
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: MuzicianTheme.violet.withValues(
                                alpha: 0.12,
                              ),
                              border: Border.all(
                                color: MuzicianTheme.violet.withValues(
                                  alpha: 0.45,
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
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _parseRoot(String chord) {
    if (chord.length > 1 && chord[1] == '#') return chord.substring(0, 2);
    return chord.substring(0, 1);
  }

  String _parseQuality(String chord) {
    if (chord.length > 1 && chord[1] == '#') return chord.substring(2);
    return chord.substring(1);
  }
}
