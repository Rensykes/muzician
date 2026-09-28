library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/harmonic_analysis.dart';
import '../../models/harmony_lane_instrument.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart'
    show saveAnchorLane, tileLaneBlocks;
import '../../schema/rules/save_system_rules.dart'
    show isFolderInProject, isValidSaveName, resolveSaveInProject;
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import '../../ui/project_picker_sheet.dart';
import '../../utils/note_utils.dart';
import 'instrument_binding.dart';

Future<void> startWriterHandoff({
  required BuildContext context,
  required WidgetRef ref,
  required InstrumentBinding binding,
  required List<ChordDetectionResult> chordResults,
  required VoidCallback onTransferComplete,
  SaveEntry? reuseSave,
}) async {
  final String? initialProjectId = _selectedWriterProjectId(ref);
  if (reuseSave != null) {
    final current = initialProjectId == null
        ? null
        : resolveSaveInProject(
            ref.read(saveSystemProvider),
            initialProjectId,
            reuseSave.id,
          );
    final instrument = binding.captureSnapshot(ref).instrument;
    final isHarmonySave = reuseSave.snapshot is HarmonyChordSnapshot;
    if (initialProjectId == null ||
        current == null ||
        (isHarmonySave
            ? !isFolderInProject(
                ref.read(saveSystemProvider).folders,
                current.folderId,
                initialProjectId,
              )
            : current.folderId != initialProjectId) ||
        current.snapshot.instrument != instrument) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This save is no longer available in the selected project.',
          ),
        ),
      );
      return;
    }
  }

  _WriterTransferChoice? choice;
  if (reuseSave == null) {
    final exactNotes = ref.read(binding.exactNotes);
    choice = await showModalBottomSheet<_WriterTransferChoice>(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      isScrollControlled: true,
      builder: (sheetContext) => _WriterTransferChoices(
        chordResults: chordResults,
        canAddVoicing: exactNotes.isNotEmpty,
        onChoose: (choice) => Navigator.of(sheetContext).pop(choice),
      ),
    );
    if (choice == null || !context.mounted) return;
  }

  final payload = reuseSave != null
      ? reuseSave.snapshot is HarmonyChordSnapshot
            ? _WriterTransferPayload.harmonySave(
                reuseSave.snapshot as HarmonyChordSnapshot,
                reuseSaveId: reuseSave.id,
                initialName: reuseSave.name,
              )
            : _WriterTransferPayload.voicing(
                reuseSave.snapshot,
                reuseSaveId: reuseSave.id,
                initialName: reuseSave.name,
              )
      : choice!.isHarmony
      ? _WriterTransferPayload.harmony(
          result: choice.chord!,
          selectedPitchNames: ref
              .read(binding.exactNotes)
              .map((note) => note.pitchClass)
              .toList(),
          sourceHarmonyInstrument: HarmonyLaneInstrument.fromJson(
            binding.captureSnapshot(ref).instrument,
          )!,
        )
      : _WriterTransferPayload.voicing(binding.captureSnapshot(ref));

  var projectId = initialProjectId;
  if (projectId == null) {
    if (reuseSave != null) return;
    await ProjectPickerSheet.show(context, allowDump: false);
    if (!context.mounted) return;
    projectId = _selectedWriterProjectId(ref);
    if (projectId == null) return;
  }

  var project = ref.read(songwriterProvider);
  String? initialSectionId = project.sections.isEmpty
      ? null
      : project.sections.first.id;
  if (project.sections.isEmpty) {
    final createSection = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Start a Writer section?',
        content: const Text(
          'Writer needs a section before this selection can be placed. '
          'Create the default eight-bar section?',
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          MuzicianDialogButton(
            'Create section',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (createSection != true || !context.mounted) return;
    if (_selectedWriterProjectId(ref) != projectId) {
      await _showDestinationChanged(context);
      return;
    }
    initialSectionId = null;
  }

  while (context.mounted) {
    final target = await showModalBottomSheet<WriterBarTarget>(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      isScrollControlled: true,
      builder: (_) => _WriterDestinationPicker(
        laneKind: payload.laneKind,
        initialSectionId: initialSectionId,
        harmonyInstrument: payload.harmonyInstrument,
      ),
    );
    if (target == null || !context.mounted) return;
    if (_selectedWriterProjectId(ref) != projectId) {
      await _showDestinationChanged(context);
      return;
    }

    final current = ref.read(songwriterProvider);
    final section = target.sectionId == null
        ? null
        : current.sections.where((s) => s.id == target.sectionId).firstOrNull;
    final sectionLengthBars =
        section?.lengthBars ?? target.stagedSectionLengthBars;
    if (target.startBar >= sectionLengthBars ||
        (section == null && !target.createSection)) {
      return;
    }
    final lane = target.laneId != null
        ? section?.lanes
              .where((candidate) => candidate.id == target.laneId)
              .firstOrNull
        : payload.laneKind == SongLaneKind.harmony
        ? null
        : section?.lanes
              .where(
                (candidate) =>
                    candidate.kind == payload.laneKind &&
                    _saveLaneMatchesHandoffTarget(
                      section,
                      candidate,
                      harmonyInstrument: payload.harmonyInstrument,
                      expectedAnchorLaneId: target.anchorLaneId,
                      defaultHarmonyInstrument: ref
                          .read(songwriterProvider.notifier)
                          .projectDefaultHarmonyInstrumentForSelectedProject,
                    ),
              )
              .firstOrNull;
    final occupiedPlacement = lane == null || section == null
        ? null
        : tileLaneBlocks(lane, sectionLengthBars: section.lengthBars)
              .where(
                (block) =>
                    block.startBar <= target.startBar &&
                    target.startBar < block.endBar,
              )
              .firstOrNull;
    final occupiedSource = occupiedPlacement == null
        ? null
        : lane!.blocks
              .where((block) => block.id == occupiedPlacement.id)
              .firstOrNull;
    final isRepeatedPlacement =
        occupiedPlacement != null &&
        occupiedSource != null &&
        occupiedPlacement.startBar != occupiedSource.startBar;

    String? replaceBlockId;
    if (occupiedPlacement != null && occupiedSource != null) {
      final action = await _showOccupiedBarDialog(
        context,
        barNumber: target.startBar + 1,
        block: occupiedPlacement,
        isRepeatedPlacement: isRepeatedPlacement,
      );
      if (!context.mounted) return;
      if (_selectedWriterProjectId(ref) != projectId) {
        await _showDestinationChanged(context);
        return;
      }
      if (action == _OccupiedBarAction.chooseAnother) {
        initialSectionId = target.sectionId;
        continue;
      }
      if (action != _OccupiedBarAction.replace) return;
      final confirmed = await _confirmReplaceOccupiedBar(
        context,
        barNumber: target.startBar + 1,
        sourceStartBar: occupiedSource.startBar,
        isRepeatedPlacement: isRepeatedPlacement,
      );
      if (!context.mounted) return;
      if (_selectedWriterProjectId(ref) != projectId) {
        await _showDestinationChanged(context);
        return;
      }
      if (!confirmed) return;
      replaceBlockId = occupiedSource.id;
    }

    if (_selectedWriterProjectId(ref) != projectId) {
      await _showDestinationChanged(context);
      return;
    }
    final saveName = payload.reuseSaveId != null
        ? null
        : await _showImportNameDialog(
            context,
            initialName: payload.chordSymbol ?? payload.initialName,
          );
    if (payload.reuseSaveId == null && saveName == null || !context.mounted) {
      return;
    }
    if (_selectedWriterProjectId(ref) != projectId) {
      await _showDestinationChanged(context);
      return;
    }
    if (payload.reuseSaveId != null) {
      final currentSave = resolveSaveInProject(
        ref.read(saveSystemProvider),
        projectId,
        payload.reuseSaveId!,
      );
      final currentHarmonySnapshot = currentSave?.snapshot;
      final compatibleLocation = payload.isHarmony
          ? currentSave != null &&
                isFolderInProject(
                  ref.read(saveSystemProvider).folders,
                  currentSave.folderId,
                  projectId,
                )
          : currentSave?.folderId == projectId;
      if (currentSave == null ||
          !compatibleLocation ||
          currentSave.snapshot.instrument != payload.snapshot!.instrument ||
          (payload.isHarmony &&
              (currentHarmonySnapshot is! HarmonyChordSnapshot ||
                  currentHarmonySnapshot.harmonyInstrument !=
                      payload.harmonyInstrument))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This save changed while you were choosing a Writer bar.',
            ),
          ),
        );
        return;
      }
    }
    final writer = ref.read(songwriterProvider.notifier);
    final inserted = payload.reuseSaveId != null && payload.isHarmony
        ? writer.insertWriterBlockFromSave(
            saveId: payload.reuseSaveId!,
            sectionId: target.sectionId,
            laneKind: SongLaneKind.harmony,
            startBar: target.startBar,
            laneId: target.laneId,
            replaceBlockId: replaceBlockId,
            expectedProjectId: projectId,
            createSectionIfMissing: target.createSection,
            stagedSectionId: target.stagedSectionId,
            stagedSectionLengthBars: target.stagedSectionLengthBars,
          )
        : writer.insertInstrumentSelectionAtBar(
            sectionId: target.sectionId,
            startBar: target.startBar,
            snapshot: payload.snapshot,
            chordSymbol: payload.chordSymbol,
            chordQuality: payload.chordQuality,
            chordRootPc: payload.chordRootPc,
            chordNotes: payload.chordNotes,
            replaceBlockId: replaceBlockId,
            saveName: saveName,
            reuseSaveId: payload.reuseSaveId,
            laneId: target.laneId,
            anchorLaneId: target.anchorLaneId,
            harmonyInstrument: payload.isHarmony
                ? payload.harmonyInstrument
                : null,
            expectedProjectId: projectId,
            createSectionIfMissing: target.createSection,
            stagedSectionId: target.stagedSectionId,
            stagedSectionLengthBars: target.stagedSectionLengthBars,
          );
    if (!inserted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That Writer bar changed. Choose a bar again.'),
          ),
        );
      }
      initialSectionId = target.sectionId;
      continue;
    }
    final insertedSection = ref
        .read(songwriterProvider)
        .sections
        .where((candidate) => candidate.id == target.sectionId)
        .firstOrNull;
    final title = payload.chordSymbol ?? 'Instrument voicing';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added $title to Writer · ${insertedSection?.label ?? 'Section'} · bar ${target.startBar + 1}',
        ),
      ),
    );
    onTransferComplete();
    return;
  }
}

String? _selectedWriterProjectId(WidgetRef ref) {
  final selectedId = ref.read(saveSystemProvider).selectedProjectId;
  if (selectedId == null) return null;
  final folder = ref
      .read(saveSystemProvider)
      .folders
      .where((folder) => folder.id == selectedId)
      .firstOrNull;
  return folder?.kind == SaveFolderKind.project ? selectedId : null;
}

Future<_OccupiedBarAction?> _showOccupiedBarDialog(
  BuildContext context, {
  required int barNumber,
  required SongBlock block,
  required bool isRepeatedPlacement,
}) => showDialog<_OccupiedBarAction>(
  context: context,
  builder: (dialogContext) => MuzicianDialog(
    title: 'Bar $barNumber is occupied',
    content: Text(
      'This bar contains ${block.chordSymbol ?? block.embedded?.instrument ?? 'a Writer block'}. '
      '${isRepeatedPlacement ? 'It is a repeated placement. ' : ''}'
      'Choose how to place the selection.',
    ),
    actions: [
      MuzicianDialogButton(
        'Cancel',
        onPressed: () =>
            Navigator.of(dialogContext).pop(_OccupiedBarAction.cancel),
      ),
      MuzicianDialogButton(
        'Choose another bar',
        onPressed: () =>
            Navigator.of(dialogContext).pop(_OccupiedBarAction.chooseAnother),
      ),
      MuzicianDialogButton(
        'Replace…',
        emphasis: MuzicianDialogEmphasis.destructive,
        onPressed: () =>
            Navigator.of(dialogContext).pop(_OccupiedBarAction.replace),
      ),
    ],
  ),
);

Future<bool> _confirmReplaceOccupiedBar(
  BuildContext context, {
  required int barNumber,
  required int sourceStartBar,
  required bool isRepeatedPlacement,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Replace the whole block?',
        content: Text(
          isRepeatedPlacement
              ? 'This repeated placement comes from the block at bar ${sourceStartBar + 1}. Replacing it changes every copy together while keeping the same repeat offsets.'
              : 'The block covering bar $barNumber will be replaced by the new selection.',
        ),
        actions: [
          MuzicianDialogButton(
            'Keep existing',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          MuzicianDialogButton(
            'Replace block',
            emphasis: MuzicianDialogEmphasis.destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _showDestinationChanged(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => MuzicianDialog(
      title: 'Destination changed',
      content: const Text(
        'The active project changed while you were choosing a Writer bar. '
        'This transfer was canceled.',
      ),
      actions: [
        MuzicianDialogButton(
          'OK',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

enum _OccupiedBarAction { replace, chooseAnother, cancel }

class _WriterTransferChoice {
  const _WriterTransferChoice.chord(this.chord) : snapshot = null;
  const _WriterTransferChoice.voicing(this.snapshot) : chord = null;

  final ChordDetectionResult? chord;
  final InstrumentSnapshot? snapshot;
  bool get isHarmony => chord != null;
}

class _WriterTransferPayload {
  const _WriterTransferPayload.harmony({
    required this.result,
    required this.selectedPitchNames,
    required this.sourceHarmonyInstrument,
  }) : snapshot = null,
       reuseSaveId = null,
       initialName = null;

  const _WriterTransferPayload.voicing(
    this.snapshot, {
    this.reuseSaveId,
    this.initialName,
  }) : result = null,
       selectedPitchNames = const [],
       sourceHarmonyInstrument = null;

  const _WriterTransferPayload.harmonySave(
    this.snapshot, {
    required this.reuseSaveId,
    required this.initialName,
  }) : result = null,
       selectedPitchNames = const [],
       sourceHarmonyInstrument = null;

  final ChordDetectionResult? result;
  final List<String> selectedPitchNames;
  final HarmonyLaneInstrument? sourceHarmonyInstrument;
  final InstrumentSnapshot? snapshot;
  final String? reuseSaveId;
  final String? initialName;

  bool get isHarmony => result != null || snapshot is HarmonyChordSnapshot;
  SongLaneKind get laneKind =>
      isHarmony ? SongLaneKind.harmony : SongLaneKind.save;
  HarmonyLaneInstrument? get harmonyInstrument {
    if (snapshot is HarmonyChordSnapshot) {
      return (snapshot as HarmonyChordSnapshot).harmonyInstrument;
    }
    if (sourceHarmonyInstrument != null) return sourceHarmonyInstrument;
    if (result != null || snapshot != null) {
      return HarmonyLaneInstrument.fromJson(snapshot?.instrument);
    }
    return null;
  }

  String? get chordSymbol => switch (snapshot) {
    HarmonyChordSnapshot(:final writerBlock) => writerBlock.chordSymbol,
    _ => result == null ? null : formatChordSymbol(result!),
  };
  String? get chordQuality => switch (snapshot) {
    HarmonyChordSnapshot(:final writerBlock) => writerBlock.chordQuality,
    _ => result?.quality,
  };
  int? get chordRootPc => switch (snapshot) {
    HarmonyChordSnapshot(:final writerBlock) => writerBlock.chordRootPc,
    _ => result == null ? null : chromaticNotes.indexOf(result!.root),
  };
  List<String> get chordNotes => switch (snapshot) {
    HarmonyChordSnapshot(:final writerBlock) => writerBlock.chordNotes,
    _ => selectedPitchNames,
  };
}

Future<String?> _showImportNameDialog(
  BuildContext context, {
  required String? initialName,
}) => showDialog<String>(
  context: context,
  builder: (_) => _WriterImportNameDialog(initialName: initialName),
);

class _WriterImportNameDialog extends StatefulWidget {
  const _WriterImportNameDialog({required this.initialName});

  final String? initialName;

  @override
  State<_WriterImportNameDialog> createState() =>
      _WriterImportNameDialogState();
}

class _WriterImportNameDialogState extends State<_WriterImportNameDialog> {
  late final TextEditingController _controller;
  late bool _valid;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialName?.trim().isNotEmpty == true
          ? widget.initialName!.trim()
          : 'Instrument voicing',
    );
    _valid = isValidSaveName(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MuzicianDialog(
    title: 'Name this Writer save',
    content: TextField(
      key: const Key('writerImportNameField'),
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(labelText: 'Block and save name'),
      onChanged: (value) => setState(() => _valid = isValidSaveName(value)),
      onSubmitted: (_) {
        if (_valid) {
          Navigator.of(context).pop(_controller.text.trim());
        }
      },
    ),
    actions: [
      MuzicianDialogButton(
        'Cancel',
        buttonKey: const Key('cancelWriterImportName'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      MuzicianDialogButton(
        'Add to Writer',
        buttonKey: const Key('confirmWriterImportName'),
        emphasis: MuzicianDialogEmphasis.primary,
        onPressed: _valid
            ? () => Navigator.of(context).pop(_controller.text.trim())
            : null,
      ),
    ],
  );
}

class _WriterTransferChoices extends StatelessWidget {
  const _WriterTransferChoices({
    required this.chordResults,
    required this.canAddVoicing,
    required this.onChoose,
  });

  final List<ChordDetectionResult> chordResults;
  final bool canAddVoicing;
  final ValueChanged<_WriterTransferChoice> onChoose;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Add to Writer',
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (chordResults.isNotEmpty) ...[
            const Text(
              'Detected harmony',
              style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 12),
            ),
            for (final chord in chordResults)
              ListTile(
                leading: const Icon(
                  Icons.music_note,
                  color: MuzicianTheme.violet,
                ),
                title: Text('Add ${formatChordSymbol(chord)} as harmony'),
                onTap: () => onChoose(_WriterTransferChoice.chord(chord)),
              ),
          ],
          if (canAddVoicing)
            ListTile(
              leading: const Icon(Icons.piano, color: MuzicianTheme.sky),
              title: const Text('Add exact voicing'),
              subtitle: const Text(
                'Keep the selected notes and instrument shape',
              ),
              onTap: () => onChoose(_WriterTransferChoice.voicing(null)),
            ),
          const SizedBox(height: 4),
          const Text(
            'Choose a Writer section and bar next.',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class WriterBarTarget {
  const WriterBarTarget({
    required this.sectionId,
    required this.startBar,
    this.laneId,
    this.anchorLaneId,
    this.createSection = false,
    this.stagedSectionId,
    this.stagedSectionLengthBars = 8,
  });

  final String? sectionId;
  final int startBar;
  final String? laneId;
  final String? anchorLaneId;
  final bool createSection;
  final String? stagedSectionId;
  final int stagedSectionLengthBars;
}

class _WriterDestinationPicker extends ConsumerWidget {
  const _WriterDestinationPicker({
    required this.laneKind,
    required this.initialSectionId,
    required this.harmonyInstrument,
  });

  final SongLaneKind laneKind;
  final String? initialSectionId;
  final HarmonyLaneInstrument? harmonyInstrument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(
      songwriterProvider.select((project) => project.sections),
    );
    final laneLabel = laneKind == SongLaneKind.harmony ? 'harmony' : 'save';
    final instrumentLabel = switch (harmonyInstrument) {
      HarmonyLaneInstrument.piano => 'Piano',
      HarmonyLaneInstrument.fretboard => 'Fretboard',
      null => null,
    };
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                'Choose a Writer section and bar',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: MuzicianTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'This selection will become a $laneLabel block. '
                'Choose the section, Harmony Lane and bar. Occupied bars '
                'already contain a block in that lane.',
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: sections.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: [
                        ExpansionTile(
                          key: const Key('writerHandoffNewSection'),
                          initiallyExpanded: true,
                          title: const Text(
                            'New eight-bar section',
                            style: TextStyle(
                              color: MuzicianTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            instrumentLabel == null
                                ? 'A section will be created with this block.'
                                : 'Starts with the project default Harmony Lane; a matching $instrumentLabel lane will be added if needed.',
                            style: const TextStyle(
                              color: MuzicianTheme.textMuted,
                            ),
                          ),
                          children: [
                            _barChoices(
                              context,
                              sectionId: null,
                              sectionLabel: 'New section',
                              laneId: null,
                              createSection: true,
                              lengthBars: 8,
                              occupied: const [],
                            ),
                          ],
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: sections.length,
                      itemBuilder: (context, index) {
                        final section = sections[index];
                        final sectionLabel =
                            section.label?.trim().isNotEmpty == true
                            ? section.label!.trim()
                            : 'Section ${section.order + 1}';
                        final matchingHarmonyLanes = harmonyInstrument == null
                            ? const <SongLane>[]
                            : section.lanes
                                  .where(
                                    (candidate) =>
                                        candidate.kind ==
                                            SongLaneKind.harmony &&
                                        candidate.harmonyInstrument ==
                                            harmonyInstrument,
                                  )
                                  .toList();
                        final defaultHarmonyInstrument = ref
                            .read(songwriterProvider.notifier)
                            .projectDefaultHarmonyInstrumentForSelectedProject;
                        final lanes = laneKind == SongLaneKind.harmony
                            ? matchingHarmonyLanes
                            : laneKind == SongLaneKind.save &&
                                  harmonyInstrument != null
                            ? section.lanes
                                  .where(
                                    (candidate) =>
                                        candidate.kind == SongLaneKind.save &&
                                        _saveLaneMatchesHandoffTarget(
                                          section,
                                          candidate,
                                          harmonyInstrument: harmonyInstrument,
                                          defaultHarmonyInstrument:
                                              defaultHarmonyInstrument,
                                        ),
                                  )
                                  .toList()
                            : section.lanes
                                  .where(
                                    (candidate) => candidate.kind == laneKind,
                                  )
                                  .take(1)
                                  .toList();
                        final needsHarmonyLane =
                            laneKind == SongLaneKind.harmony && lanes.isEmpty;
                        final needsCompatibleSaveLane =
                            laneKind == SongLaneKind.save &&
                            harmonyInstrument != null &&
                            lanes.isEmpty;
                        final laneChoices = <Widget>[
                          if (lanes.length == 1)
                            _laneBars(
                              context,
                              section: section,
                              sectionLabel: sectionLabel,
                              lane: lanes.single,
                              laneKind: laneKind,
                              harmonyInstrument: harmonyInstrument,
                            )
                          else
                            for (
                              var laneIndex = 0;
                              laneIndex < lanes.length;
                              laneIndex++
                            )
                              _laneChoice(
                                context,
                                section: section,
                                sectionLabel: sectionLabel,
                                lane: lanes[laneIndex],
                                laneKind: laneKind,
                                harmonyInstrument: harmonyInstrument,
                              ),
                          if (needsHarmonyLane)
                            _stagedHarmonyLaneChoice(
                              context,
                              section: section,
                              sectionLabel: sectionLabel,
                              laneKind: laneKind,
                              harmonyInstrument: harmonyInstrument,
                            ),
                          if (needsCompatibleSaveLane)
                            _stagedSaveLaneChoice(
                              context,
                              section: section,
                              sectionLabel: sectionLabel,
                              harmonyInstrument: harmonyInstrument!,
                              anchorLaneId:
                                  matchingHarmonyLanes.firstOrNull?.id,
                            ),
                          if (laneKind != SongLaneKind.harmony &&
                              lanes.isEmpty &&
                              !needsCompatibleSaveLane)
                            _barChoices(
                              context,
                              sectionId: section.id,
                              sectionLabel: sectionLabel,
                              laneId: null,
                              lengthBars: section.lengthBars,
                              occupied: const [],
                            ),
                        ];
                        return ExpansionTile(
                          key: Key('writerHandoffSection_${section.id}'),
                          initiallyExpanded:
                              section.id == initialSectionId ||
                              sections.length == 1,
                          title: Text(
                            sectionLabel,
                            style: const TextStyle(
                              color: MuzicianTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${section.lengthBars} bars',
                            style: const TextStyle(
                              color: MuzicianTheme.textMuted,
                            ),
                          ),
                          children: [...laneChoices],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _laneChoice(
    BuildContext context, {
    required SongSection section,
    required String sectionLabel,
    required SongLane lane,
    required SongLaneKind laneKind,
    required HarmonyLaneInstrument? harmonyInstrument,
  }) {
    final laneNumber =
        section.lanes
            .where((candidate) => candidate.kind == lane.kind)
            .toList()
            .indexWhere((candidate) => candidate.id == lane.id) +
        1;
    final laneLabel = lane.label?.trim().isNotEmpty == true
        ? lane.label!.trim()
        : laneKind == SongLaneKind.harmony
        ? '${_instrumentLabel(harmonyInstrument)} Harmony $laneNumber'
        : 'Save lane';
    return ExpansionTile(
      key: Key('writerHandoffLane_${section.id}_${lane.id}'),
      title: Text(
        laneLabel,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
      ),
      children: [
        _laneBars(
          context,
          section: section,
          sectionLabel: sectionLabel,
          lane: lane,
          laneKind: laneKind,
          harmonyInstrument: harmonyInstrument,
        ),
      ],
    );
  }

  Widget _laneBars(
    BuildContext context, {
    required SongSection section,
    required String sectionLabel,
    required SongLane lane,
    required SongLaneKind laneKind,
    required HarmonyLaneInstrument? harmonyInstrument,
  }) => _barChoices(
    context,
    sectionId: section.id,
    sectionLabel: sectionLabel,
    laneId: lane.id,
    anchorLaneId: laneKind == SongLaneKind.save
        ? saveAnchorLane(section, lane)?.id
        : null,
    lengthBars: section.lengthBars,
    occupied: tileLaneBlocks(lane, sectionLengthBars: section.lengthBars),
  );

  Widget _stagedHarmonyLaneChoice(
    BuildContext context, {
    required SongSection section,
    required String sectionLabel,
    required SongLaneKind laneKind,
    required HarmonyLaneInstrument? harmonyInstrument,
  }) => ExpansionTile(
    key: Key('writerHandoffNewHarmonyLane_${section.id}'),
    title: Text(
      'Create ${_instrumentLabel(harmonyInstrument)} Harmony Lane',
      style: const TextStyle(color: MuzicianTheme.textPrimary),
    ),
    subtitle: const Text(
      'This section has no Harmony Lane for this instrument.',
      style: TextStyle(color: MuzicianTheme.textMuted),
    ),
    children: [
      _barChoices(
        context,
        sectionId: section.id,
        sectionLabel: sectionLabel,
        laneId: null,
        lengthBars: section.lengthBars,
        occupied: const [],
      ),
    ],
  );

  Widget _stagedSaveLaneChoice(
    BuildContext context, {
    required SongSection section,
    required String sectionLabel,
    required HarmonyLaneInstrument harmonyInstrument,
    required String? anchorLaneId,
  }) => ExpansionTile(
    key: Key('writerHandoffNewSaveLane_${section.id}'),
    title: Text(
      'Create ${_instrumentLabel(harmonyInstrument)} Voicing lane',
      style: const TextStyle(color: MuzicianTheme.textPrimary),
    ),
    subtitle: const Text(
      'This section has no compatible Voicing lane.',
      style: TextStyle(color: MuzicianTheme.textMuted),
    ),
    children: [
      _barChoices(
        context,
        sectionId: section.id,
        sectionLabel: sectionLabel,
        laneId: null,
        anchorLaneId: anchorLaneId,
        lengthBars: section.lengthBars,
        occupied: const [],
      ),
    ],
  );

  Widget _barChoices(
    BuildContext context, {
    required String? sectionId,
    required String sectionLabel,
    required String? laneId,
    String? anchorLaneId,
    required int lengthBars,
    required List<SongBlock> occupied,
    bool createSection = false,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var bar = 0; bar < lengthBars; bar++)
          _WriterBarButton(
            sectionKey: sectionId ?? 'new',
            sectionLabel: sectionLabel,
            startBar: bar,
            occupied: occupied.any(
              (block) => block.startBar <= bar && bar < block.endBar,
            ),
            onTap: () => Navigator.of(context).pop(
              WriterBarTarget(
                sectionId: sectionId,
                startBar: bar,
                laneId: laneId,
                anchorLaneId: anchorLaneId,
                createSection: createSection,
                stagedSectionLengthBars: lengthBars,
              ),
            ),
          ),
      ],
    ),
  );
}

String _instrumentLabel(HarmonyLaneInstrument? instrument) =>
    switch (instrument) {
      HarmonyLaneInstrument.piano => 'Piano',
      HarmonyLaneInstrument.fretboard => 'Fretboard',
      null => 'Harmony',
    };

bool _saveLaneMatchesHandoffTarget(
  SongSection section,
  SongLane lane, {
  required HarmonyLaneInstrument? harmonyInstrument,
  required HarmonyLaneInstrument defaultHarmonyInstrument,
  String? expectedAnchorLaneId,
}) {
  final anchor = saveAnchorLane(section, lane);
  if (lane.anchorLaneId != null && anchor == null) return false;
  if (expectedAnchorLaneId != null && anchor?.id != expectedAnchorLaneId) {
    return false;
  }
  final laneInstrument = anchor?.harmonyInstrument ?? defaultHarmonyInstrument;
  return harmonyInstrument == null || laneInstrument == harmonyInstrument;
}

class _WriterBarButton extends StatelessWidget {
  const _WriterBarButton({
    required this.sectionKey,
    required this.sectionLabel,
    required this.startBar,
    required this.occupied,
    required this.onTap,
  });

  final String sectionKey;
  final String sectionLabel;
  final int startBar;
  final bool occupied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = occupied ? 'Occupied' : 'Available';
    return Semantics(
      button: true,
      label: '$sectionLabel, bar ${startBar + 1}, $status',
      child: TextButton(
        key: Key('writerHandoffBar_${sectionKey}_$startBar'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(104, 48),
          backgroundColor: occupied
              ? MuzicianTheme.orange.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          foregroundColor: MuzicianTheme.textPrimary,
          side: BorderSide(
            color: occupied
                ? MuzicianTheme.orange.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          occupied ? 'Bar ${startBar + 1} · Occupied' : 'Bar ${startBar + 1}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
