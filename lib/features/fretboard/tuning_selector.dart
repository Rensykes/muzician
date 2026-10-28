/// TuningSelector – category tabs + horizontal tuning pill selector.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../utils/note_utils.dart';

const _categories = [
  TuningCategory.standard,
  TuningCategory.metal,
  TuningCategory.midwestEmo,
];

Color _categoryColor(BuildContext context, TuningCategory category) =>
    switch (category) {
      TuningCategory.standard => StudioPalette.of(context).sky,
      TuningCategory.metal => StudioPalette.of(context).red,
      TuningCategory.midwestEmo => StudioPalette.of(context).violet,
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
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final notifier = ref.read(fretboardProvider.notifier);
    final color = _categoryColor(context, _activeCategory);
    final bg = color.withValues(alpha: 0.12);
    final studio = StudioPalette.of(context).isStudio;

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
              final c = _categoryColor(context, cat);
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeCategory = cat),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
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
                          color: isTab
                              ? c
                              : StudioPalette.of(context).textMuted,
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
        SizedBox(height: studio ? 4 : 10),
        // Tuning pills
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: studio ? 0 : 16),
            itemCount: visibleTunings.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = visibleTunings[i];
              final isActive = t.name == state.currentTuning;
              return GestureDetector(
                onTap: () => notifier.setTuning(t.name),
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(studio ? 6 : 20),
                    color: isActive ? bg : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: isActive
                          ? color
                          : Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    formatTuningName(t, spelling),
                    style: TextStyle(
                      color: isActive
                          ? color
                          : StudioPalette.of(context).textMuted,
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
        if (!studio) const SizedBox(height: 12),
      ],
    );
  }
}

String formatTuningName(Tuning tuning, NoteSpelling spelling) {
  if (tuning.name == TuningName.ebStandard) {
    return '${formatRootChoiceLabel('Eb', spelling: spelling)} Standard';
  }
  return tuning.displayName;
}
