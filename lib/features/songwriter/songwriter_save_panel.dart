import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_config.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/save_system_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';
import '../../utils/note_utils.dart';

/// Writer's named Song versions and reusable Section blocks.
///
/// Whole-project loads are restricted to SongwriterProjectSnapshot entries.
/// Section blocks are browsed independently so a Writer-native block can
/// never be loaded as a project.
class SongwriterSavePanel extends ConsumerStatefulWidget {
  /// Optional host-owned handoff. When omitted, this panel offers a compact
  /// section and bar picker and inserts the selected root Writer block.
  final ValueChanged<SaveEntry>? onUseInWriter;

  /// Tab to show when the panel opens: 0 for Song versions, 1 for Section blocks.
  final int initialTabIndex;

  const SongwriterSavePanel({
    super.key,
    this.onUseInWriter,
    this.initialTabIndex = 0,
  }) : assert(initialTabIndex >= 0 && initialTabIndex < 2);

  @override
  ConsumerState<SongwriterSavePanel> createState() =>
      _SongwriterSavePanelState();
}

class _SongwriterSavePanelState extends ConsumerState<SongwriterSavePanel> {
  static const _sectionBlockInstruments = {
    'writer_block',
    'fretboard',
    'piano',
    'piano_roll',
  };

  Future<void> _useInWriter(SaveEntry entry) async {
    final callback = widget.onUseInWriter;
    if (callback != null) {
      callback(entry);
      return;
    }
    final snapshot = entry.snapshot;
    if (snapshot is! WriterBlockSnapshot) return;

    final sections = ref.read(songwriterProvider).sections;
    if (sections.isEmpty) {
      _showFeedback('Add a Writer section before using this block.');
      return;
    }
    final destination = await _chooseDestination(
      sections,
      laneKind: snapshot.laneKind,
    );
    if (destination == null || !mounted) return;

    final inserted = ref
        .read(songwriterProvider.notifier)
        .insertWriterBlockFromSave(
          saveId: entry.id,
          sectionId: destination.sectionId,
          laneKind: snapshot.laneKind,
          startBar: destination.startBar,
          laneId: destination.laneId,
          anchorLaneId: destination.anchorLaneId,
        );
    if (!inserted) {
      _showFeedback('That bar is occupied or this Writer save is unavailable.');
      return;
    }
    HapticFeedback.mediumImpact();
    _showFeedback('Added ${entry.name} to Writer.');
  }

  Future<bool> _loadWriterVersion(SaveEntry entry) async {
    final snapshot = entry.snapshot;
    if (snapshot is! SongwriterProjectSnapshot) return false;
    final saveState = ref.read(saveSystemProvider);
    final projectId = saveState.selectedProjectId;
    if (projectId == null) return false;
    final folder = saveState.folders
        .where((candidate) => candidate.id == projectId)
        .firstOrNull;
    final current = folder?.projectConfig ?? const ProjectConfig();
    final differences = <String>[];
    if (snapshot.config.tempo != current.tempo) {
      differences.add('Tempo: ${snapshot.config.tempo} → ${current.tempo} BPM');
    }
    if (snapshot.config.beatsPerBar != current.beatsPerBar ||
        snapshot.config.beatUnit != current.beatUnit) {
      differences.add(
        'Meter: ${snapshot.config.beatsPerBar}/${snapshot.config.beatUnit} → '
        '${current.beatsPerBar}/${current.beatUnit}',
      );
    }
    if (snapshot.config.keyRoot != current.keyRootPc ||
        snapshot.config.keyScaleName != current.keyScaleName) {
      String keyLabel(int? root, String? scale) {
        if (root == null) return 'No key';
        final note = chromaticNotes[root % chromaticNotes.length];
        return scale == null ? note : '$note $scale';
      }

      differences.add(
        'Key: ${keyLabel(snapshot.config.keyRoot, snapshot.config.keyScaleName)}'
        ' → ${keyLabel(current.keyRootPc, current.keyScaleName)}',
      );
    }
    if (differences.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => MuzicianDialog(
          title: 'Project settings differ',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This version was saved with different settings. Loading it '
                'keeps the current project settings:',
              ),
              const SizedBox(height: 10),
              for (final difference in differences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $difference'),
                ),
            ],
          ),
          actions: [
            MuzicianDialogButton(
              'Cancel',
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            MuzicianDialogButton(
              'Load version',
              emphasis: MuzicianDialogEmphasis.primary,
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return false;
    }
    try {
      await ref
          .read(songwriterProvider.notifier)
          .loadProject(snapshot, saveId: entry.id);
    } catch (_) {
      if (mounted) {
        _showFeedback(
          'Could not finish loading this version. Any pending write will be recovered on next launch.',
        );
      }
      return false;
    }
    return mounted;
  }

  Future<_WriterDestination?> _chooseDestination(
    List<SongSection> sections, {
    required SongLaneKind laneKind,
  }) {
    var sectionId = sections.first.id;
    String? laneId = _matchingLanes(sections.first, laneKind).firstOrNull?.id;
    String? startBarError;
    var startBarText = '1';
    return showDialog<_WriterDestination>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final section = sections.firstWhere(
            (item) => item.id == sectionId,
            orElse: () => sections.first,
          );
          final matchingLanes = _matchingLanes(section, laneKind);
          final selectedLane = matchingLanes
              .where((lane) => lane.id == laneId)
              .firstOrNull;
          return MuzicianDialog(
            title: 'Use in Writer',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('writerSaveDestinationSection'),
                  initialValue: section.id,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [
                    for (var i = 0; i < sections.length; i++)
                      DropdownMenuItem(
                        value: sections[i].id,
                        child: Text(
                          sections[i].label?.trim().isNotEmpty == true
                              ? sections[i].label!.trim()
                              : 'Section ${i + 1}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final nextSection = sections.firstWhere(
                      (item) => item.id == value,
                    );
                    setDialogState(() {
                      sectionId = value;
                      startBarError = null;
                      laneId = _matchingLanes(
                        nextSection,
                        laneKind,
                      ).firstOrNull?.id;
                    });
                  },
                ),
                const SizedBox(height: 10),
                if (matchingLanes.isEmpty)
                  InputDecorator(
                    key: ValueKey('writerSaveDestinationLane_${section.id}'),
                    decoration: const InputDecoration(labelText: 'Lane'),
                    child: Text(
                      'New ${_laneKindLabel(laneKind)} lane will be created',
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('writerSaveDestinationLane_${section.id}'),
                    initialValue: selectedLane?.id ?? matchingLanes.first.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Lane'),
                    items: [
                      for (var i = 0; i < matchingLanes.length; i++)
                        DropdownMenuItem(
                          value: matchingLanes[i].id,
                          child: Text(
                            _laneDisplayName(matchingLanes[i], i, laneKind),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => laneId = value);
                      }
                    },
                  ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('writerSaveDestinationBar'),
                  initialValue: startBarText,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Start bar (1–${section.lengthBars})',
                    errorText: startBarError,
                  ),
                  onChanged: (value) {
                    startBarText = value;
                    if (startBarError != null) {
                      setDialogState(() => startBarError = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              MuzicianDialogButton(
                'Cancel',
                onPressed: () => Navigator.pop(dialogContext),
              ),
              MuzicianDialogButton(
                'Add block',
                emphasis: MuzicianDialogEmphasis.primary,
                buttonKey: const Key('confirmUseWriterSave'),
                onPressed: () {
                  final bar = int.tryParse(startBarText);
                  if (bar == null || bar < 1 || bar > section.lengthBars) {
                    setDialogState(
                      () => startBarError =
                          'Enter a bar from 1 to ${section.lengthBars}.',
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    _WriterDestination(
                      sectionId: section.id,
                      startBar: bar - 1,
                      laneId: selectedLane?.id,
                      anchorLaneId: laneKind == SongLaneKind.guitarStrum
                          ? selectedLane?.anchorLaneId
                          : null,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<SongLane> _matchingLanes(SongSection section, SongLaneKind laneKind) =>
      section.lanes.where((lane) => lane.kind == laneKind).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  String _laneDisplayName(SongLane lane, int index, SongLaneKind laneKind) {
    final label = lane.label?.trim();
    if (label != null && label.isNotEmpty) return '$label (lane ${index + 1})';
    return '${_laneKindLabel(laneKind)} lane ${index + 1}';
  }

  String _laneKindLabel(SongLaneKind laneKind) => switch (laneKind) {
    SongLaneKind.harmony => 'Harmony',
    SongLaneKind.save => 'Voicing',
    SongLaneKind.drum => 'Drum',
    SongLaneKind.audio => 'Audio',
    SongLaneKind.melody => 'Melody',
    SongLaneKind.guitarStrum => 'Guitar strum',
  };

  void _showFeedback(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedProjectProvider);
    final saveState = ref.watch(saveSystemProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      return const ProjectRequiredPlaceholder(
        message: 'Songwriter needs a real project.\nDump is not allowed here.',
        allowDump: false,
      );
    }
    final notifier = ref.read(songwriterProvider.notifier);

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          TabBar(
            labelColor: MuzicianTheme.sky,
            unselectedLabelColor: MuzicianTheme.textSecondary,
            indicatorColor: MuzicianTheme.sky,
            tabs: const [
              Tab(text: 'Song versions'),
              Tab(text: 'Section blocks'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SaveBrowserPanel(
                  rootFolderId: selected.id,
                  instrumentFilter: 'songwriter',
                  captureSnapshot: () => notifier.materializeCurrentContent(),
                  onLoadEntry: _loadWriterVersion,
                  onSaved: (saveId) => notifier.bindNamedSave(saveId),
                ),
                SaveBrowserPanel(
                  rootFolderId: selected.id,
                  allowedInstruments: _sectionBlockInstruments,
                  onRenameLinkedSave: (saveId, name) =>
                      notifier.renameLinkedSave(saveId: saveId, name: name),
                  onUseInWriter: _useInWriter,
                  canUseInWriter: (entry) =>
                      isFolderInProject(
                        saveState.folders,
                        entry.folderId,
                        selected.id,
                      ) &&
                      entry.snapshot is WriterBlockSnapshot,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WriterDestination {
  final String sectionId;
  final int startBar;
  final String? laneId;
  final String? anchorLaneId;

  const _WriterDestination({
    required this.sectionId,
    required this.startBar,
    this.laneId,
    this.anchorLaneId,
  });
}

@visibleForTesting
SongwriterProjectSnapshot songwriterCaptureForTest(ProviderContainer c) =>
    c.read(songwriterProvider);
