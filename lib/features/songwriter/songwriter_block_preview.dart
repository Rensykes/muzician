import 'package:flutter/material.dart';
import '../../theme/muzician_theme.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_library_match_rules.dart';
import '../../schema/rules/songwriter_third_above_rules.dart';
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../ui/save_card_label.dart';
import '../../ui/save_previews/save_preview_thumbnail.dart';
import '../_mockup_shell.dart';

void showBlockPreviewSheet(BuildContext context, InstrumentSnapshot snapshot) {
  final label = saveCardLabel(snapshot);

  showWidgetSheet(
    context: context,
    title: label.text ?? snapshot.instrument,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
  );
}

void showBrokenReferenceSheet(
  BuildContext context, {
  required VoidCallback onDelete,
  VoidCallback? onRelink,
}) {
  showWidgetSheet(
    context: context,
    title: 'Broken Reference',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'This block references a deleted save.',
            style: TextStyle(color: MuzicianTheme.textSecondary),
          ),
        ),
        if (onRelink != null)
          ListTile(
            leading: const Icon(Icons.link, color: MuzicianTheme.textSecondary),
            title: const Text('Re-link to another save',
                style: TextStyle(color: MuzicianTheme.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              onRelink();
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: MuzicianTheme.red),
          title: const Text('Delete block',
              style: TextStyle(color: MuzicianTheme.textPrimary)),
          onTap: () {
            Navigator.pop(context);
            onDelete();
          },
        ),
      ],
    ),
  );
}

/// Opens the harmony-block sheet with three tabs:
/// - **Voicings**: horizontal strip of CAGED voicing cards (C v1).
/// - **Harmony**: one 3rd-above card or an empty state.
/// - **Library**: saves from the same folder that match the chord or key.
/// Tapping a card invokes the matching onAccept callback and closes the sheet.
void showHarmonyBlockSheet(
  BuildContext context, {
  required SongBlock block,
  required List<VoicingSuggestion> voicings,
  required ThirdAboveSuggestion? thirdAbove,
  required List<LibraryMatch> chordMatches,
  required List<LibraryMatch> scaleMatches,
  required void Function(VoicingSuggestion) onAcceptVoicing,
  required void Function(ThirdAboveSuggestion) onAcceptThirdAbove,
  required void Function(String saveId) onAcceptLibrary,
}) {
  final hasChord = block.chordRootPc != null && block.chordQuality != null;
  final title = block.chordSymbol ?? (hasChord ? '?' : 'Harmony');
  final numeral = block.romanNumeral;

  showWidgetSheet(
    context: context,
    title: '$title ${numeral ?? ""}'.trim(),
    child: DefaultTabController(
      length: 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.chordNotes.isNotEmpty) ...[
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
            const SizedBox(height: 12),
          ],
          const TabBar(
            tabs: [
              Tab(text: 'Voicings'),
              Tab(text: 'Harmony'),
              Tab(text: 'Library'),
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
                    Navigator.pop(context);
                    onAcceptVoicing(v);
                  },
                ),
                _HarmonyTab(
                  hasChord: hasChord,
                  thirdAbove: thirdAbove,
                  onAccept: (s) {
                    Navigator.pop(context);
                    onAcceptThirdAbove(s);
                  },
                ),
                _LibraryTab(
                  chordMatches: chordMatches,
                  scaleMatches: scaleMatches,
                  onAccept: (id) {
                    Navigator.pop(context);
                    onAcceptLibrary(id);
                  },
                ),
              ],
            ),
          ),
        ],
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
          border: Border.all(color: MuzicianTheme.glassBorder),
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
              style: const TextStyle(fontSize: 11, color: MuzicianTheme.textPrimary),
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
          border: Border.all(color: MuzicianTheme.glassBorder),
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
              style: const TextStyle(fontSize: 11, color: MuzicianTheme.textPrimary),
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

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.chordMatches,
    required this.scaleMatches,
    required this.onAccept,
  });
  final List<LibraryMatch> chordMatches;
  final List<LibraryMatch> scaleMatches;
  final void Function(String saveId) onAccept;

  @override
  Widget build(BuildContext context) {
    if (chordMatches.isEmpty && scaleMatches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text("No matching saves in this song's folder yet."),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chordMatches.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Matches this chord',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chordMatches.length,
                separatorBuilder: (context, idx) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = chordMatches[i];
                  return _LibraryMatchCard(
                    key: Key('libraryCard_${m.entry.id}'),
                    match: m,
                    onTap: () => onAccept(m.entry.id),
                  );
                },
              ),
            ),
          ],
          if (scaleMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Fits this key',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: scaleMatches.length,
                separatorBuilder: (context, idx) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = scaleMatches[i];
                  return _LibraryMatchCard(
                    key: Key('libraryCard_${m.entry.id}'),
                    match: m,
                    onTap: () => onAccept(m.entry.id),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryMatchCard extends StatelessWidget {
  const _LibraryMatchCard({
    super.key,
    required this.match,
    required this.onTap,
  });
  final LibraryMatch match;
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
          border: Border.all(color: MuzicianTheme.glassBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SavePreviewThumbnail(
              snapshot: match.entry.snapshot,
              width: 84,
              height: 60,
            ),
            const SizedBox(height: 4),
            Text(
              match.entry.name,
              style: const TextStyle(fontSize: 11, color: MuzicianTheme.textPrimary),
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
