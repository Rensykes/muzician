import 'package:flutter/material.dart';
import '../../theme/muzician_theme.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../utils/note_utils.dart';
import 'chord_wheel.dart';

const _qualities = <(String value, String label)>[
  ('', 'maj'),
  ('m', 'min'),
  ('7', '7'),
  ('maj7', 'maj7'),
  ('m7', 'm7'),
  ('dim', 'dim'),
  ('aug', 'aug'),
  ('sus2', 'sus2'),
  ('sus4', 'sus4'),
  ('m7b5', 'm7b5'),
  ('dim7', 'dim7'),
];

/// Opens the harmony chord picker. Returns a ready-to-add [SongBlock], or null
/// if dismissed. Two modes:
///  - **Key set:** primary picker is the diatonic [ChordWheel]; the
///    root+quality grid hides behind an "Other chord" expander for borrowed
///    or altered chords.
///  - **No key:** the root+quality grid is shown directly.
Future<SongBlock?> showHarmonyChordSheet(
  BuildContext context, {
  required int startBar,
  required int spanBars,
  required int? keyRoot,
  required String? keyScaleName,
}) {
  return showModalBottomSheet<SongBlock>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: SingleChildScrollView(
        child: _HarmonySheet(
          startBar: startBar,
          spanBars: spanBars,
          keyRoot: keyRoot,
          keyScaleName: keyScaleName,
        ),
      ),
    ),
  );
}

class _HarmonySheet extends StatefulWidget {
  const _HarmonySheet({
    required this.startBar,
    required this.spanBars,
    required this.keyRoot,
    required this.keyScaleName,
  });
  final int startBar;
  final int spanBars;
  final int? keyRoot;
  final String? keyScaleName;

  @override
  State<_HarmonySheet> createState() => _HarmonySheetState();
}

class _HarmonySheetState extends State<_HarmonySheet> {
  bool _showManual = false;
  int? _rootPc;

  bool get _hasKey => widget.keyRoot != null && widget.keyScaleName != null;

  void _commitTriad(DiatonicTriad triad) {
    final block = makeHarmonyBlock(
      startBar: widget.startBar,
      spanBars: widget.spanBars,
      chordSymbol: triad.symbol,
      chordQuality: triad.quality,
      chordRootPc: triad.rootPc,
      chordNotes: triad.notes,
      romanNumeral: triad.romanNumeral,
    );
    Navigator.pop(context, block);
  }

  void _commitManual(String quality) {
    final rootPc = _rootPc;
    if (rootPc == null) return;
    final rootName = chromaticNotes[rootPc];
    final block = makeHarmonyBlock(
      startBar: widget.startBar,
      spanBars: widget.spanBars,
      chordSymbol: '$rootName$quality',
      chordQuality: quality,
      chordRootPc: rootPc,
      chordNotes: getChordNotes(rootName, quality),
      romanNumeral: romanNumeralFor(
        rootPc,
        quality,
        widget.keyRoot,
        widget.keyScaleName,
      ),
    );
    Navigator.pop(context, block);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasKey) ...[
            SizedBox(
              height: 240,
              child: ChordWheel(
                keyRootPc: widget.keyRoot!,
                scaleName: widget.keyScaleName!,
                onPick: _commitTriad,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showManual = !_showManual),
              child: Row(
                children: [
                  Icon(
                    _showManual ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text('Other chord'),
                ],
              ),
            ),
          ],
          if (!_hasKey || _showManual) ...[
            const SizedBox(height: 8),
            _manualPicker(),
          ],
        ],
      ),
    );
  }

  Widget _manualPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Root',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var pc = 0; pc < 12; pc++)
              _GlassPickerChip(
                key: Key('harmonyRoot_$pc'),
                label: chromaticNotes[pc],
                selected: _rootPc == pc,
                onTap: () => setState(() => _rootPc = pc),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Quality',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final q in _qualities)
              _GlassPickerChip(
                key: Key('harmonyQuality_${q.$1}'),
                label: q.$2,
                selected: false,
                enabled: _rootPc != null,
                onTap: _rootPc == null ? null : () => _commitManual(q.$1),
              ),
          ],
        ),
      ],
    );
  }
}

class _GlassPickerChip extends StatelessWidget {
  const _GlassPickerChip({
    super.key,
    required this.label,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.30)
                : MuzicianTheme.glassBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? MuzicianTheme.textPrimary : MuzicianTheme.textDim,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
