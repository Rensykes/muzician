/// PianoSavePanel – save/load panel for the Piano screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/piano_store.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../ui/project_required_placeholder.dart';
import '../../ui/save_browser_panel.dart';
import '../../schema/rules/save_system_rules.dart';
import '../instrument_shared/writer_handoff.dart';
import '../../theme/muzician_theme.dart';

/// A panel that lets the user save and load piano snapshots.
///
/// Only piano saves are shown. Mounting this widget inside a card
/// in the piano screen gives it the correct glassmorphism styling.
class PianoSavePanel extends ConsumerStatefulWidget {
  const PianoSavePanel({
    super.key,
    this.linkedEditSaveId,
    this.onDifferentSaveLoaded,
    this.onHandoffCompleted,
  });

  final String? linkedEditSaveId;
  final ValueChanged<String>? onDifferentSaveLoaded;
  final VoidCallback? onHandoffCompleted;

  @override
  ConsumerState<PianoSavePanel> createState() => _PianoSavePanelState();
}

class _PianoSavePanelState extends ConsumerState<PianoSavePanel> {
  String? _linkedEditSaveId;
  String? _linkedEditProjectId;
  bool _editTargetCleared = false;

  @override
  void initState() {
    super.initState();
    _linkedEditSaveId = widget.linkedEditSaveId;
    _linkedEditProjectId = ref.read(saveSystemProvider).selectedProjectId;
  }

  @override
  void didUpdateWidget(covariant PianoSavePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.linkedEditSaveId != oldWidget.linkedEditSaveId) {
      _linkedEditSaveId = widget.linkedEditSaveId;
      _linkedEditProjectId = ref.read(saveSystemProvider).selectedProjectId;
      _editTargetCleared = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveState = ref.watch(saveSystemProvider);
    ref.listen<String?>(
      saveSystemProvider.select((state) => state.selectedProjectId),
      (previous, next) {
        if (_linkedEditSaveId != null && _linkedEditProjectId != next) {
          setState(() {
            _linkedEditSaveId = null;
            _editTargetCleared = true;
          });
        }
      },
    );
    final selectedId = saveState.selectedProjectId;
    final selectedRoot = selectedId == null
        ? null
        : saveState.folders
              .where((folder) => folder.id == selectedId)
              .firstOrNull;
    final selectedProjectRoot =
        selectedRoot != null && isProjectRoot(selectedRoot);
    if (selectedId == null) {
      return const ProjectRequiredPlaceholder(
        message: 'Pick a project (or Dump)\nto save and load piano shapes.',
      );
    }
    final editTargetSaveId = _linkedEditSaveId;
    if (editTargetSaveId != null) {
      ref.listen<bool>(
        saveSystemProvider.select(
          (state) => getWriterLinksForSave(
            state,
            selectedId,
            editTargetSaveId,
          ).isNotEmpty,
        ),
        (previous, hasWriterLink) {
          if (!hasWriterLink && _linkedEditSaveId == editTargetSaveId) {
            setState(() {
              _linkedEditSaveId = null;
              _editTargetCleared = true;
            });
          }
        },
      );
    }
    final editSave = _editTargetCleared || _linkedEditSaveId == null
        ? null
        : resolveSaveInProject(saveState, selectedId, _linkedEditSaveId!);
    final editTargetIsLinked =
        _linkedEditSaveId != null &&
        getWriterLinksForSave(
          saveState,
          selectedId,
          _linkedEditSaveId!,
        ).isNotEmpty;
    final linkedEditEntry =
        editTargetIsLinked && editSave?.snapshot is PianoSnapshot
        ? editSave
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (linkedEditEntry != null) ...[
          _UpdateLinkedSaveButton(
            saveName: linkedEditEntry.name,
            onPressed: () {
              final updated = ref
                  .read(songwriterProvider.notifier)
                  .updateLinkedInstrumentSave(
                    saveId: linkedEditEntry.id,
                    snapshot: _captureSnapshot(ref),
                  );
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      updated
                          ? 'Updated ${linkedEditEntry.name} in Writer.'
                          : 'This linked Writer save is no longer available.',
                    ),
                  ),
                );
            },
          ),
          const SizedBox(height: 8),
        ],
        SaveBrowserPanel(
          rootFolderId: selectedId,
          instrumentFilter: 'piano',
          onRenameLinkedSave: (saveId, name) => ref
              .read(songwriterProvider.notifier)
              .renameLinkedSave(saveId: saveId, name: name),
          captureSnapshot: () => _captureSnapshot(ref),
          onLoad: (snap) => _loadSnapshot(ref, snap),
          onLoadSaveId: _onSaveLoaded,
          canUseInWriter: (save) =>
              selectedProjectRoot &&
              save.folderId == selectedId &&
              save.snapshot is PianoSnapshot,
          onUseInWriter: (save) => startWriterHandoff(
            context: context,
            ref: ref,
            binding: pianoBinding,
            chordResults: const [],
            onTransferComplete: () {
              if (widget.onHandoffCompleted == null) return;
              Navigator.of(context).maybePop();
              widget.onHandoffCompleted!();
            },
            reuseSave: save,
          ),
        ),
      ],
    );
  }

  void _onSaveLoaded(String saveId) {
    if (_linkedEditSaveId != null && saveId != _linkedEditSaveId) {
      setState(() {
        _linkedEditSaveId = null;
        _editTargetCleared = true;
      });
    }
    widget.onDifferentSaveLoaded?.call(saveId);
  }

  /// Builds a [PianoSnapshot] from the current store state.
  PianoSnapshot _captureSnapshot(WidgetRef ref) {
    final pianoState = ref.read(pianoProvider);
    final pendingChord = ref.read(pianoPendingChordProvider);
    final pendingScale = ref.read(pianoPendingScaleProvider);

    return PianoSnapshot(
      currentRange: pianoState.currentRange,
      selectedKeys: List.of(pianoState.selectedKeys),
      selectedNotes: List.of(pianoState.selectedNotes),
      viewMode: pianoState.viewMode,
      pendingChord: pendingChord != null
          ? PendingChord(
              root: pendingChord.root,
              quality: pendingChord.quality,
              symbol: '${pendingChord.root}${pendingChord.quality}',
            )
          : null,
      pendingScale: pendingScale != null
          ? PendingScale(
              root: pendingScale.root,
              scaleName: pendingScale.scaleName,
            )
          : null,
    );
  }

  /// Restores piano state from a snapshot.
  void _loadSnapshot(WidgetRef ref, InstrumentSnapshot snap) {
    loadPianoSnapshot(ref, snap);
  }
}

/// Loads all Piano and picker state from a canonical snapshot.
void loadPianoSnapshot(WidgetRef ref, InstrumentSnapshot snapshot) {
  if (snapshot is! PianoSnapshot) return;

  ref.read(pianoProvider.notifier).loadSnapshot(snapshot);
  if (snapshot.pendingChord != null) {
    ref.read(pianoPendingChordProvider.notifier).state = (
      root: snapshot.pendingChord!.root,
      quality: snapshot.pendingChord!.quality,
    );
    ref.read(pianoChordCommittedProvider.notifier).state = true;
  } else {
    ref.read(pianoPendingChordProvider.notifier).state = null;
    ref.read(pianoChordCommittedProvider.notifier).state = false;
  }

  if (snapshot.pendingScale != null) {
    ref.read(pianoPendingScaleProvider.notifier).state = (
      root: snapshot.pendingScale!.root,
      scaleName: snapshot.pendingScale!.scaleName,
    );
    ref.read(pianoActiveScaleProvider.notifier).state = (
      root: snapshot.pendingScale!.root,
      scaleName: snapshot.pendingScale!.scaleName,
    );
  } else {
    ref.read(pianoPendingScaleProvider.notifier).state = null;
    ref.read(pianoActiveScaleProvider.notifier).state = null;
  }
  if (snapshot.selectedKeys.isNotEmpty) {
    ref.read(pianoScrollToMidiProvider.notifier).state =
        snapshot.selectedKeys.first.midiNote;
  }
}

class _UpdateLinkedSaveButton extends StatelessWidget {
  const _UpdateLinkedSaveButton({
    required this.saveName,
    required this.onPressed,
  });

  final String saveName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Semantics(
      button: true,
      label: 'Update linked save $saveName',
      child: OutlinedButton.icon(
        key: const Key('updateLinkedSaveButton'),
        onPressed: onPressed,
        icon: const Icon(Icons.sync),
        label: Text('Update linked save · $saveName'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: MuzicianTheme.sky,
        ),
      ),
    ),
  );
}
