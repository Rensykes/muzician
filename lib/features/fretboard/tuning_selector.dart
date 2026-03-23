/// TuningSelector – category tabs + horizontal tuning pill selector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';

const _categories = [
  TuningCategory.standard,
  TuningCategory.metal,
  TuningCategory.midwestEmo,
];

const _catColor = {
  TuningCategory.standard: MuzicianTheme.sky,
  TuningCategory.metal: MuzicianTheme.red,
  TuningCategory.midwestEmo: MuzicianTheme.violet,
};

const _catBg = {
  TuningCategory.standard: Color(0x1F38BDF8),
  TuningCategory.metal: Color(0x1FF87171),
  TuningCategory.midwestEmo: Color(0x1FA78BFA),
};

const _catLabel = {
  TuningCategory.standard: 'Standard',
  TuningCategory.metal: 'Metal',
  TuningCategory.midwestEmo: 'Midwest Emo',
};

class TuningSelector extends ConsumerStatefulWidget {
  const TuningSelector({super.key});

  @override
  ConsumerState<TuningSelector> createState() => _TuningSelectorState();
}

class _TuningSelectorState extends ConsumerState<TuningSelector> {
  late TuningCategory _activeCategory;

  @override
  void initState() {
    super.initState();
    final currentName = ref.read(fretboardProvider).currentTuning;
    final tuning = tunings[currentName]!;
    _activeCategory = tuning.category;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final color = _catColor[_activeCategory]!;
    final bg = _catBg[_activeCategory]!;

    final allTunings = tunings.values.toList();
    final visibleTunings = allTunings
        .where((t) => t.category == _activeCategory)
        .toList();

    return Column(
      children: [
        // Category tabs
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: _categories.map((cat) {
              final isTab = cat == _activeCategory;
              final c = _catColor[cat]!;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        // Tuning pills
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visibleTunings.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = visibleTunings[i];
              final isActive = t.name == state.currentTuning;
              return GestureDetector(
                onTap: () => notifier.setTuning(t.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: isActive ? bg : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: isActive
                          ? color
                          : Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    t.displayName,
                    style: TextStyle(
                      color: isActive ? color : const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
