/// LandscapePianoModal – full-screen landscape presentation for the piano.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import 'piano_keyboard.dart';

class LandscapePianoModal extends ConsumerWidget {
  final VoidCallback onDismiss;

  const LandscapePianoModal({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenSize = MediaQuery.of(context).size;
    final screenW = screenSize.width;
    final screenH = screenSize.height;
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);

    const scale = 0.88;
    final lsW = math.max(screenW, screenH) * scale;
    final lsH = math.min(screenW, screenH) * scale;
    final offsetX = (screenW - lsW) / 2;
    final offsetY = (screenH - lsH) / 2;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: onDismiss,
            child: Container(color: const Color(0xB8000000)),
          ),
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
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: const PianoKeyboard(),
                      ),
                    ),
                    // Mode pills
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _modePill(
                            'All',
                            PianoViewMode.pitchClass,
                            state.viewMode,
                            notifier,
                          ),
                          const SizedBox(width: 8),
                          _modePill(
                            'Exact',
                            PianoViewMode.exact,
                            state.viewMode,
                            notifier,
                          ),
                          const SizedBox(width: 8),
                          _modePill(
                            'Focus',
                            PianoViewMode.focus,
                            state.viewMode,
                            notifier,
                          ),
                          const SizedBox(width: 8),
                          _modePill(
                            'Solo',
                            PianoViewMode.exactFocus,
                            state.viewMode,
                            notifier,
                          ),
                        ],
                      ),
                    ),
                    // Dismiss
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: onDismiss,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.white.withValues(alpha: 0.1),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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

  Widget _modePill(
    String label,
    PianoViewMode mode,
    PianoViewMode current,
    PianoNotifier notifier,
  ) {
    final active = current == mode;
    return GestureDetector(
      onTap: () => notifier.setViewMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
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
            color: active ? MuzicianTheme.sky : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
