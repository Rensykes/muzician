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
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: _HarmonySheet(
        startBar: startBar,
        spanBars: spanBars,
        keyRoot: keyRoot,
        keyScaleName: keyScaleName,
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
        const Text('Root'),
        Wrap(
          spacing: 6,
          children: [
            for (var pc = 0; pc < 12; pc++)
              ChoiceChip(
                key: Key('harmonyRoot_$pc'),
                label: Text(chromaticNotes[pc]),
                selected: _rootPc == pc,
                onSelected: (_) => setState(() => _rootPc = pc),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Quality'),
        Wrap(
          spacing: 6,
          children: [
            for (final q in _qualities)
              ActionChip(
                key: Key('harmonyQuality_${q.$1}'),
                label: Text(q.$2),
                onPressed: _rootPc == null ? null : () => _commitManual(q.$1),
              ),
          ],
        ),
      ],
    );
  }
}
