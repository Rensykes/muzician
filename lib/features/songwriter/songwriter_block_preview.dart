import 'package:flutter/material.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_third_above_rules.dart';
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

/// Opens the harmony-block sheet with two tabs:
/// - **Voicings**: horizontal strip of CAGED voicing cards (C v1).
/// - **Harmony**: one 3rd-above card or an empty state.
/// Tapping a card invokes the matching onAccept callback and closes the sheet.
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> voicings,
  required ThirdAboveSuggestion? thirdAbove,
  required void Function(VoicingSuggestion) onAcceptVoicing,
  required void Function(ThirdAboveSuggestion) onAcceptThirdAbove,
}) {
  final hasChord = block.chordRootPc != null && block.chordQuality != null;
  final title = block.chordSymbol ?? (hasChord ? '?' : 'Harmony');
  final numeral = block.romanNumeral;

  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note, size: 24),
                  const SizedBox(width: 8),
                  Text(title,
                      style: Theme.of(sheetCtx).textTheme.titleMedium),
                  if (numeral != null) ...[
                    const SizedBox(width: 8),
                    Text(numeral,
                        style: Theme.of(sheetCtx)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey)),
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
              const SizedBox(height: 12),
              const TabBar(
                tabs: [
                  Tab(text: 'Voicings'),
                  Tab(text: 'Harmony'),
                ],
              ),
              SizedBox(
                height: 170,
                child: TabBarView(
                  children: [
                    _VoicingsTab(
                      hasChord: hasChord,
                      voicings: voicings,
                      onAccept: (v) {
                        Navigator.pop(sheetCtx);
                        onAcceptVoicing(v);
                      },
                    ),
                    _HarmonyTab(
                      hasChord: hasChord,
                      thirdAbove: thirdAbove,
                      onAccept: (s) {
                        Navigator.pop(sheetCtx);
                        onAcceptThirdAbove(s);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VoicingsTab extends StatelessWidget {
  const _VoicingsTab({
    required this.hasChord,
    required this.voicings,
    required this.onAccept,
  });
  final bool hasChord;
  final List<VoicingSuggestion> voicings;
  final void Function(VoicingSuggestion) onAccept;

  @override
  Widget build(BuildContext context) {
    if (!hasChord) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set a chord to see voicings'),
      );
    }
    if (voicings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No voicings available for this chord '
          '(v1: major/minor triads only)',
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: voicings.length,
      separatorBuilder: (context, idx) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final s = voicings[i];
        return _VoicingCard(
          key: Key('voicingCard_${s.shape.name}'),
          suggestion: s,
          onTap: () => onAccept(s),
        );
      },
    );
  }
}

class _HarmonyTab extends StatelessWidget {
  const _HarmonyTab({
    required this.hasChord,
    required this.thirdAbove,
    required this.onAccept,
  });
  final bool hasChord;
  final ThirdAboveSuggestion? thirdAbove;
  final void Function(ThirdAboveSuggestion) onAccept;

  @override
  Widget build(BuildContext context) {
    if (!hasChord) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set a chord to see harmony'),
      );
    }
    final s = thirdAbove;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set a key to see harmony suggestions'),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: _ThirdAboveCard(
        key: const Key('thirdAboveCard'),
        suggestion: s,
        onTap: () => onAccept(s),
      ),
    );
  }
}

class _ThirdAboveCard extends StatelessWidget {
  const _ThirdAboveCard({
    super.key,
    required this.suggestion,
    required this.onTap,
  });
  final ThirdAboveSuggestion suggestion;
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
              snapshot: thirdAboveToSnapshot(suggestion),
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
