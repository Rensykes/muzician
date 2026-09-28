import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/muzician_theme.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/save_system_rules.dart';
import '../../schema/rules/songwriter_library_match_rules.dart';
import '../../schema/rules/songwriter_third_above_rules.dart';
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../store/songwriter_store.dart';
import '../../ui/core/muzician_dialog.dart';
import '../../ui/save_card_label.dart';
import '../../ui/save_previews/save_preview_thumbnail.dart';
import '../_mockup_shell.dart';

SaveEntry? writerSaveEntryForBlock(SaveSystemState state, SongBlock block) {
  final projectId = state.selectedProjectId;
  final saveId = block.saveId;
  if (projectId == null || saveId == null) return null;
  return resolveSaveInProject(state, projectId, saveId);
}

Future<String?> showWriterSaveNameDialog(
  BuildContext context, {
  required String initialName,
  required String title,
}) => showDialog<String>(
  context: context,
  builder: (_) => _WriterSaveNameDialog(initialName: initialName, title: title),
);

Future<void> renameWriterBlockSave(
  BuildContext context,
  WidgetRef ref,
  SaveEntry entry,
) async {
  final name = await showWriterSaveNameDialog(
    context,
    initialName: entry.name,
    title: 'Rename save',
  );
  if (name == null || !context.mounted) return;
  if (!isValidSaveName(name)) {
    _showWriterSaveFeedback(context, 'Enter a name of up to 80 characters.');
    return;
  }
  if (!ref
      .read(songwriterProvider.notifier)
      .renameLinkedSave(saveId: entry.id, name: name)) {
    _showWriterSaveFeedback(context, 'This Writer save could not be renamed.');
  }
}

Future<void> makeWriterBlockUnique(
  BuildContext context,
  WidgetRef ref, {
  required SongSection section,
  required SongLane lane,
  required SongBlock block,
  required SaveEntry entry,
}) async {
  final initialName = _copyName(entry.name);
  final name = await showWriterSaveNameDialog(
    context,
    initialName: initialName,
    title: 'Make block unique',
  );
  if (name == null || !context.mounted) return;
  if (!isValidSaveName(name)) {
    _showWriterSaveFeedback(context, 'Enter a name of up to 80 characters.');
    return;
  }
  final madeUnique = ref
      .read(songwriterProvider.notifier)
      .makeBlockUnique(
        sectionId: section.id,
        laneId: lane.id,
        blockId: block.id,
        snapshot: entry.snapshot,
        saveName: name,
      );
  if (!madeUnique) {
    _showWriterSaveFeedback(context, 'This block could not be made unique.');
  }
}

Widget writerLinkedBlockActionsMenu(
  BuildContext context,
  WidgetRef ref, {
  required SongSection section,
  required SongLane lane,
  required SongBlock block,
  required SaveEntry entry,
}) => Semantics(
  label: 'Actions for ${entry.name}',
  explicitChildNodes: true,
  child: PopupMenuButton<String>(
    key: Key('writerBlockActions_${block.id}'),
    tooltip: 'Actions for ${entry.name}',
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    iconSize: 16,
    icon: const Icon(Icons.more_vert, color: MuzicianTheme.textPrimary),
    onSelected: (action) {
      if (action == 'rename') {
        renameWriterBlockSave(context, ref, entry);
      } else if (action == 'unique') {
        makeWriterBlockUnique(
          context,
          ref,
          section: section,
          lane: lane,
          block: block,
          entry: entry,
        );
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        key: Key('writerRename_${block.id}'),
        value: 'rename',
        child: const Text('Rename'),
      ),
      PopupMenuItem(
        key: Key('writerMakeUnique_${block.id}'),
        value: 'unique',
        child: const Text('Make Unique'),
      ),
    ],
  ),
);

Widget writerBrokenReferenceAction(
  BuildContext context, {
  required SongBlock block,
  required VoidCallback onDelete,
}) => IconButton(
  key: Key('writerBrokenReference_${block.id}'),
  tooltip: 'Broken save reference',
  visualDensity: VisualDensity.compact,
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
  iconSize: 15,
  color: MuzicianTheme.red,
  icon: const Icon(Icons.link_off),
  onPressed: () => showBrokenReferenceSheet(context, onDelete: onDelete),
);

String _copyName(String name) {
  const suffix = ' copy';
  final maxLength = 80 - suffix.length;
  return '${name.substring(0, name.length.clamp(0, maxLength))}$suffix';
}

void _showWriterSaveFeedback(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _WriterSaveNameDialog extends StatefulWidget {
  const _WriterSaveNameDialog({required this.initialName, required this.title});

  final String initialName;
  final String title;

  @override
  State<_WriterSaveNameDialog> createState() => _WriterSaveNameDialogState();
}

class _WriterSaveNameDialogState extends State<_WriterSaveNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MuzicianDialog(
    title: widget.title,
    content: TextField(
      key: const Key('writerBlockNameField'),
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      style: const TextStyle(color: MuzicianTheme.textPrimary),
      decoration: const InputDecoration(labelText: 'Save name'),
    ),
    actions: [
      MuzicianDialogButton(
        'Cancel',
        buttonKey: const Key('writerBlockNameCancel'),
        onPressed: () => Navigator.pop(context),
      ),
      MuzicianDialogButton(
        'Save',
        buttonKey: const Key('writerBlockNameSave'),
        emphasis: MuzicianDialogEmphasis.primary,
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
      ),
    ],
  );
}

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
            title: const Text(
              'Re-link to another save',
              style: TextStyle(color: MuzicianTheme.textPrimary),
            ),
            onTap: () {
              Navigator.pop(context);
              onRelink();
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: MuzicianTheme.red),
          title: const Text(
            'Delete block',
            style: TextStyle(color: MuzicianTheme.textPrimary),
          ),
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
  required void Function(VoicingSuggestion) onAcceptVoicing,
  required void Function(ThirdAboveSuggestion) onAcceptThirdAbove,
  required void Function(String saveId) onAcceptLibrary,
  bool showLibrary = true,
  VoidCallback? onEditChord,
  String editChordLabel = 'Edit chord & lyrics',
}) {
  final hasChord = block.chordRootPc != null && block.chordQuality != null;
  final title = block.chordSymbol ?? (hasChord ? '?' : 'Harmony');
  final numeral = block.romanNumeral;

  showWidgetSheet(
    context: context,
    title: '$title ${numeral ?? ""}'.trim(),
    child: DefaultTabController(
      length: showLibrary ? 3 : 2,
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
          TabBar(
            tabs: [
              const Tab(text: 'Voicings'),
              const Tab(text: 'Harmony'),
              if (showLibrary) const Tab(text: 'Library'),
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
                if (showLibrary)
                  _LibraryTab(
                    chordMatches: chordMatches,
                    onAccept: (id) {
                      Navigator.pop(context);
                      onAcceptLibrary(id);
                    },
                  ),
              ],
            ),
          ),
          if (onEditChord != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('editChordButton'),
                onPressed: () {
                  Navigator.pop(context);
                  onEditChord();
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(editChordLabel),
              ),
            ),
          ],
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
    return GestureDetector(
      onTap: onTap,
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
              style: const TextStyle(
                fontSize: 11,
                color: MuzicianTheme.textPrimary,
              ),
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
    return GestureDetector(
      onTap: onTap,
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
              style: const TextStyle(
                fontSize: 11,
                color: MuzicianTheme.textPrimary,
              ),
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
  const _LibraryTab({required this.chordMatches, required this.onAccept});

  /// Only exact chord-note matches are shown. When there are none, the tab
  /// shows a short hint and no cards — saves that merely fit the key are not
  /// surfaced here.
  final List<LibraryMatch> chordMatches;
  final void Function(String saveId) onAccept;

  @override
  Widget build(BuildContext context) {
    if (chordMatches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_music_outlined,
                size: 28,
                color: MuzicianTheme.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              Text(
                'No saved voicing matches these notes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Save a voicing with these exact notes to see it here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MuzicianTheme.textMuted.withValues(alpha: 0.8),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    return GestureDetector(
      onTap: onTap,
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
              style: const TextStyle(
                fontSize: 11,
                color: MuzicianTheme.textPrimary,
              ),
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
