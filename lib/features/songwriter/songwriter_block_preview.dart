import 'package:flutter/material.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../ui/save_card_label.dart';
import '../../ui/save_previews/save_preview_thumbnail.dart';

void showBlockPreviewSheet(BuildContext context, InstrumentSnapshot snapshot) {
  final label = saveCardLabel(snapshot);
  final icon = saveInstrumentIcon(snapshot.instrument);

  showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.text ?? snapshot.instrument,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SavePreviewThumbnail(snapshot: snapshot, width: 200, height: 120),
            if (snapshot.selectedNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final note in snapshot.selectedNotes)
                    Chip(
                      label: Text(note),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

void showBrokenReferenceSheet(
  BuildContext context, {
  required VoidCallback onDelete,
  VoidCallback? onRelink,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('This block references a deleted save.'),
          ),
          if (onRelink != null)
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Re-link to another save'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onRelink();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete block'),
            onTap: () {
              Navigator.pop(sheetCtx);
              onDelete();
            },
          ),
        ],
      ),
    ),
  );
}

/// Opens the harmony-block sheet: chord header + horizontal strip of CAGED
/// voicing suggestions. Tapping a voicing card invokes [onAccept] and closes
/// the sheet. v1 covers major and minor triads only.
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> suggestions,
  required void Function(VoicingSuggestion) onAccept,
}) {
  final hasChord = block.chordRootPc != null && block.chordQuality != null;
  final title = block.chordSymbol ?? (hasChord ? '?' : 'Harmony');
  final numeral = block.romanNumeral;

  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.music_note, size: 24),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(sheetCtx).textTheme.titleMedium),
                if (numeral != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    numeral,
                    style: Theme.of(
                      sheetCtx,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ],
              ],
            ),
            if (block.chordNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final n in block.chordNotes)
                    Chip(
                      label: Text(n),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Suggested voicings',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (!hasChord)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Set a chord to see voicings'),
              )
            else if (suggestions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No voicings available for this chord '
                  '(v1: major/minor triads only)',
                ),
              )
            else
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = suggestions[i];
                    return _VoicingCard(
                      key: Key('voicingCard_${s.shape.name}'),
                      suggestion: s,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        onAccept(s);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _VoicingCard extends StatelessWidget {
  const _VoicingCard({
    super.key,
    required this.suggestion,
    required this.onTap,
  });
  final VoicingSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SavePreviewThumbnail(
              snapshot: voicingToSnapshot(suggestion),
              width: 84,
              height: 72,
            ),
            const SizedBox(height: 4),
            Text(
              suggestion.label,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
