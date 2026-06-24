/// Picker for the built-in drum [drumPresets] library, grouped by category.
library;

import 'package:flutter/material.dart';

import '../../schema/rules/drum_presets.dart';
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';

/// Shows the drum library. Calls [onPick] with the chosen preset and closes.
Future<void> showDrumLibrarySheet({
  required BuildContext context,
  required void Function(DrumPreset preset) onPick,
}) {
  return showWidgetSheet(
    context: context,
    title: 'Drum Library',
    child: _DrumLibraryBody(onPick: onPick),
  );
}

class _DrumLibraryBody extends StatelessWidget {
  const _DrumLibraryBody({required this.onPick});
  final void Function(DrumPreset preset) onPick;

  /// Categories in first-seen order across [drumPresets].
  List<String> get _orderedCategories {
    final seen = <String>[];
    for (final p in drumPresets) {
      if (!seen.contains(p.category)) seen.add(p.category);
    }
    return seen;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _orderedCategories;
    // SingleChildScrollView + min Column scrolls when the sheet bounds it and
    // sizes to content otherwise — robust regardless of the sheet's layout.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(
                category,
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final preset
                in drumPresets.where((p) => p.category == category))
              _PresetTile(
                preset: preset,
                onTap: () {
                  onPick(preset);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.onTap});
  final DrumPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final voices = preset.hits.entries.where((e) => e.value.isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: MuzicianTheme.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('preset_${preset.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.graphic_eq,
                  size: 16,
                  color: MuzicianTheme.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    preset.name,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$voices voices',
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
