/// Shared building blocks for the Fretboard and Piano chord pickers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';

/// Header row: section title on the left, active-chord badge on the right.
class ChordPickerHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (root != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: MuzicianTheme.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formatChordSymbol(
                ChordDetectionResult(root: root!, quality: quality),
              ),
              style: const TextStyle(
                color: MuzicianTheme.violet,
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
class RootPillRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chromaticNotes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final root = chromaticNotes[i];
          final active = selectedRoot == root;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap(root);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
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
                formatRootChoiceLabel(root),
                style: TextStyle(
                  color: active ? accent : const Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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
class DiatonicChordsRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chords.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = chords[i];
          final active = selectedRoot == c.root && selectedQuality == c.quality;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap(c.root, c.quality);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: active
                    ? accent.withValues(alpha: 0.18)
                    : MuzicianTheme.emerald.withValues(alpha: 0.06),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.5)
                      : MuzicianTheme.emerald.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    c.romanNumeral,
                    style: TextStyle(
                      color: active ? accent : MuzicianTheme.emerald,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${formatRootChoiceLabel(c.root)}${c.quality}',
                    style: TextStyle(
                      color: active ? accent : const Color(0xFFE2E8F0),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
          color: MuzicianTheme.emerald.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 6),
        Text(
          'DIATONIC · ${keyLabel.toUpperCase()}',
          style: TextStyle(
            color: MuzicianTheme.emerald.withValues(alpha: 0.9),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
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
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: qualities.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (symbol, label) = qualities[i];
          final active = selectedQuality == symbol;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap(symbol);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  color: active ? accent : const Color(0xFF475569),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
