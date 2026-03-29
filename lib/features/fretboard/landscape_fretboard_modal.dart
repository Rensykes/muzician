/// LandscapeFretboardModal – renders the fretboard full-screen in simulated
/// landscape by rotating the content 90°.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import 'fretboard.dart';

const _viewSegments = <(FretboardViewMode, String, String)>[
  (FretboardViewMode.exact, 'Exact', 'Only tapped positions'),
  (FretboardViewMode.exactFocus, 'Solo', 'Exact positions, all others hidden'),
];

class LandscapeFretboardModal extends ConsumerWidget {
  final VoidCallback onDismiss;

  const LandscapeFretboardModal({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenSize = MediaQuery.of(context).size;
    final screenW = screenSize.width;
    final screenH = screenSize.height;
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);

    const scale = 0.88;
    final lsW = math.max(screenW, screenH) * scale;
    final lsH = math.min(screenW, screenH) * scale;
    final offsetX = (screenW - lsW) / 2;
    final offsetY = (screenH - lsH) / 2;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Scrim
          GestureDetector(
            onTap: onDismiss,
            child: Container(color: const Color(0xB8000000)),
          ),
          // Rotated container
          Positioned(
            left: offsetX,
            top: offsetY,
            child: Transform.rotate(
              angle: math.pi / 2,
              child: Container(
                width: lsW,
                height: lsH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0A0A1E),
                      Color(0xFF1A1034),
                      Color(0xFF16213E),
                      Color(0xFF0F3460),
                    ],
                    stops: [0.0, 0.3, 0.7, 1.0],
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Fretboard
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: const GuitarFretboard(),
                      ),
                    ),
                    // Dismiss button
                    Positioned(
                      top: 12,
                      right: 14,
                      child: GestureDetector(
                        onTap: onDismiss,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '✕',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Legend
    Positioned(
                      bottom: 12,
                      left: 18,
                      child: Row(
                        children: [
                          _legendDot(MuzicianTheme.sky, 'Natural'),
                          const SizedBox(width: 14),
                          _legendDot(const Color(0xFFC084FC), 'Accidental'),
                        ],
                      ),
                    ),
                    // View mode control
                    Positioned(
                      bottom: 10,
                      right: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.selectedNotes.isNotEmpty)
                            Text(
                              '${state.selectedNotes.length} note${state.selectedNotes.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: MuzicianTheme.sky,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: _viewSegments.map((seg) {
                                final (mode, label, _) = seg;
                                final active = state.viewMode == mode;
                                return GestureDetector(
                                  onTap: () => notifier.setViewMode(mode),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 5,
                                    ),
                                    color: active
                                        ? MuzicianTheme.sky.withValues(
                                            alpha: 0.20,
                                          )
                                        : Colors.transparent,
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: active
                                            ? MuzicianTheme.sky
                                            : const Color(0xFF475569),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _viewSegments
                                .firstWhere((s) => s.$1 == state.viewMode)
                                .$3,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
        ),
      ],
    );
  }
}
