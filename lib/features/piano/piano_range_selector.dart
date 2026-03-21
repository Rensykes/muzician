/// PianoRangeSelector – selects a keyboard range preset (49/61/88-key).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano.dart';
import '../../schema/rules/piano_rules.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';

const _rangeOrder = [PianoRangeName.key49, PianoRangeName.key61, PianoRangeName.key88];

class PianoRangeSelector extends ConsumerWidget {
  const PianoRangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRange = ref.watch(pianoProvider.select((s) => s.currentRange));
    final notifier = ref.read(pianoProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RANGE',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _rangeOrder.map((range) {
            final active = currentRange == range;
            final rangeData = pianoRanges[range]!;
            return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  notifier.setRange(range);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: active
                        ? MuzicianTheme.sky.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.sky.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.16),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    rangeData.displayName,
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
          }).toList(),
        ),
      ],
    );
  }
}
