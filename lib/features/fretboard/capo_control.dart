/// CapoControl – compact stepper for setting a capo position (0–11).
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';

const _maxCapo = 11;

class CapoControl extends ConsumerWidget {
  const CapoControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capo = ref.watch(fretboardProvider.select((s) => s.capo));
    final notifier = ref.read(fretboardProvider.notifier);
    final isActive = capo > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 36,
            child: Text(
              'CAPO',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Stepper
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepperBtn('−', capo > 0, () {
                notifier.setCapo(math.max(0, capo - 1));
              }),
              SizedBox(
                width: 42,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      capo == 0 ? 'Off' : '$capo',
                      style: TextStyle(
                        color: isActive
                            ? MuzicianTheme.orange
                            : const Color(0xFF475569),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (isActive)
                      Text(
                        'fret',
                        style: TextStyle(
                          color: const Color(0xFF92400E),
                          fontSize: 8,
                          letterSpacing: 0.5,
                        ),
                      ),
                  ],
                ),
              ),
              _stepperBtn('+', capo < _maxCapo, () {
                notifier.setCapo(math.min(_maxCapo, capo + 1));
              }),
            ],
          ),
          const SizedBox(width: 12),
          // Dot indicators 1–11
          Expanded(
            child: Row(
              children: List.generate(_maxCapo, (i) {
                final fret = i + 1;
                final isPast = fret < capo;
                final isCurrent = fret == capo;
                return GestureDetector(
                  onTap: () => notifier.setCapo(capo == fret ? 0 : fret),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Container(
                      width: isCurrent ? 8 : 6,
                      height: isCurrent ? 8 : 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent
                            ? MuzicianTheme.orange
                            : isPast
                            ? MuzicianTheme.orange.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: isCurrent
                              ? MuzicianTheme.orange
                              : isPast
                              ? MuzicianTheme.orange.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn(String label, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.25,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF475569),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
