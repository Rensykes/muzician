/// Shared building blocks for the Fretboard and Piano chord pickers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';

/// Header row: section title on the left, active-chord badge on the right.
class ChordPickerHeader extends ConsumerWidget {
  final String title;
  final String? root;
  final String quality;
  const ChordPickerHeader({
    super.key,
    required this.title,
    required this.root,
    required this.quality,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: StudioPalette.of(context).textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        if (root != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: StudioPalette.of(context).violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatChordSymbol(
                ChordDetectionResult(root: root!, quality: quality),
                spelling: spelling,
              ),
              style: TextStyle(
                color: StudioPalette.of(context).violet,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// Horizontal row of the 12 chromatic root pills.
class RootPillRow extends ConsumerWidget {
  final String? selectedRoot;
  final Color accent;
  final ValueChanged<String> onTap;
  final EdgeInsetsGeometry padding;
  const RootPillRow({
    super.key,
    required this.selectedRoot,
    required this.accent,
    required this.onTap,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chromaticNotes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final root = chromaticNotes[i];
          final active = selectedRoot == root;
          return SizedBox(
            height: 44,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(root);
                },
                child: Center(
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: active
                          ? accent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: active
                            ? accent.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.1),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      formatRootChoiceLabel(root, spelling: spelling),
                      style: TextStyle(
                        color: active
                            ? accent
                            : StudioPalette.of(context).textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal row of diatonic chord chips for the active key. Renders one
/// chip per scale degree (Roman numeral + chord symbol) and reports taps
/// back as `(root, quality)` so the picker can populate itself.
class DiatonicChordsRow extends ConsumerWidget {
  final List<DiatonicChord> chords;
  final String? selectedRoot;
  final String selectedQuality;
  final Color accent;
  final void Function(String root, String quality) onTap;
  final EdgeInsetsGeometry padding;
  const DiatonicChordsRow({
    super.key,
    required this.chords,
    required this.selectedRoot,
    required this.selectedQuality,
    required this.accent,
    required this.onTap,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    // Two stacked text lines plus their 1px gap need about 31 logical pixels
    // at 1×. Chip padding and border add another 13px.
    final scaledChipHeight = textScaler.scale(31) + 13;
    final rowHeight = scaledChipHeight > 46 ? scaledChipHeight : 46.0;
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chords.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = chords[i];
          final active = selectedRoot == c.root && selectedQuality == c.quality;
          return SizedBox(
            height: rowHeight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(c.root, c.quality);
                },
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: active
                          ? accent.withValues(alpha: 0.18)
                          : StudioPalette.of(
                              context,
                            ).emerald.withValues(alpha: 0.06),
                      border: Border.all(
                        color: active
                            ? accent.withValues(alpha: 0.5)
                            : StudioPalette.of(
                                context,
                              ).emerald.withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          c.romanNumeral,
                          style: TextStyle(
                            color: active
                                ? accent
                                : StudioPalette.of(context).emerald,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${formatRootChoiceLabel(c.root, spelling: spelling)}${c.quality}',
                          style: TextStyle(
                            color: active
                                ? accent
                                : StudioPalette.of(context).textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Header label shown above the [DiatonicChordsRow], e.g. `"DIATONIC · C major"`.
class DiatonicChordsHeader extends StatelessWidget {
  final String keyLabel;
  const DiatonicChordsHeader({super.key, required this.keyLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.stacked_line_chart,
          size: 12,
          color: StudioPalette.of(context).emerald.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'DIATONIC · ${keyLabel.toUpperCase()}',
            style: TextStyle(
              color: StudioPalette.of(context).emerald.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal row of chord-quality pills.
class QualityPillRow extends StatelessWidget {
  final List<(String symbol, String label)> qualities;
  final String selectedQuality;
  final Color accent;
  final ValueChanged<String> onTap;
  final EdgeInsetsGeometry padding;
  const QualityPillRow({
    super.key,
    required this.qualities,
    required this.selectedQuality,
    required this.accent,
    required this.onTap,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: qualities.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (symbol, label) = qualities[i];
          final active = selectedQuality == symbol;
          return SizedBox(
            height: 44,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap(symbol);
                },
                child: Center(
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: active
                          ? accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: active
                            ? accent.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? accent
                            : StudioPalette.of(context).textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Result of detecting the first chord, used by the sync helper.
typedef DetectedChord = ({String root, String quality})?;

/// Shared listener block: live-syncs root/quality from detection while not
/// committed, drops the commit on manual edit, consumes pendingChord, and
/// publishes activeChord. Call [installChordSync] from the picker's build.
mixin ChordPickerSync<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Picker supplies how it reads the first detected chord from current notes.
  DetectedChord detectFirstChordFromState();

  /// Picker mutates its own selection here.
  void applyDetectedChord(DetectedChord chord, {required bool committed});

  /// Picker's current (root, quality) for publishing to activeChord.
  ({String root, String quality})? get currentActiveChord;

  /// Live commit flag. Read on every listener fire so the [selectedNotes]
  /// guard never uses a stale build-time snapshot.
  bool get isChordCommitted;

  void installChordSync(InstrumentBinding binding) {
    ref.listen(binding.selectedNotes, (_, _) {
      if (isChordCommitted) return;
      applyDetectedChord(detectFirstChordFromState(), committed: false);
    });
    ref.listen(binding.manualEdit, (_, _) {
      applyDetectedChord(detectFirstChordFromState(), committed: false);
      ref.read(binding.chordCommitted.notifier).state = false;
    });
    final pending = ref.watch(binding.pendingChord);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        applyDetectedChord((
          root: pending.root,
          quality: pending.quality,
        ), committed: true);
        ref.read(binding.chordCommitted.notifier).state = true;
        ref.read(binding.pendingChord.notifier).state = null;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = currentActiveChord;
      final cur = ref.read(binding.activeChord);
      if (cur?.root != next?.root || cur?.quality != next?.quality) {
        ref.read(binding.activeChord.notifier).state = next;
      }
    });
  }
}

/// Compact Studio controls keep the native voicing previews close to the tabs.
class StudioChordSelectors extends ConsumerWidget {
  const StudioChordSelectors({
    super.key,
    required this.root,
    required this.quality,
    required this.qualities,
    required this.onRootChanged,
    required this.onQualityChanged,
  });

  final String? root;
  final String quality;
  final List<(String, String)> qualities;
  final ValueChanged<String> onRootChanged;
  final ValueChanged<String> onQualityChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = StudioPalette.of(context);
    final spelling = ref.watch(settingsProvider.select((s) => s.noteSpelling));
    Widget selector({
      required String label,
      required String? value,
      required List<DropdownMenuItem<String>> items,
      required ValueChanged<String> onChanged,
    }) => Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.glassBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(label),
          isExpanded: true,
          dropdownColor: p.dialogBg,
          style: TextStyle(color: p.textPrimary, fontSize: 13),
          borderRadius: BorderRadius.circular(8),
          items: items,
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: selector(
            label: 'Root',
            value: root,
            items: [
              for (final note in chromaticNotes)
                DropdownMenuItem(
                  value: note,
                  child: Text(formatRootChoiceLabel(note, spelling: spelling)),
                ),
            ],
            onChanged: onRootChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: selector(
            label: 'Quality',
            value: quality,
            items: [
              for (final (symbol, label) in qualities)
                DropdownMenuItem(
                  value: symbol,
                  child: Text(
                    symbol.isEmpty
                        ? 'Major'
                        : symbol == 'm'
                        ? 'Minor'
                        : label,
                  ),
                ),
            ],
            onChanged: onQualityChanged,
          ),
        ),
      ],
    );
  }
}
