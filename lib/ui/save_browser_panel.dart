/// SaveBrowserPanel – reusable nested folder save browser.
///
/// Used by FretboardSavePanel and PianoSavePanel to browse, create,
/// load, rename, delete, and navigate saved instrument snapshots.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/save_system.dart';
import '../schema/rules/save_system_rules.dart';
import '../store/fretboard_store.dart';
import '../store/piano_store.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
import '../utils/note_utils.dart';

// ─── Public Widget ─────────────────────────────────────────────────────────────

class SaveBrowserPanel extends ConsumerStatefulWidget {
  /// When set, the list is filtered so only saves with a matching
  /// [InstrumentSnapshot.instrument] value are shown.
  final String? instrumentFilter;

  /// Returns a snapshot of the current instrument state.
  ///
  /// When provided a "Save here" button is visible inside any folder.
  final InstrumentSnapshot Function()? captureSnapshot;

  /// Called when the user taps "Load" on a selected save.
  final void Function(InstrumentSnapshot snap)? onLoad;

  const SaveBrowserPanel({
    super.key,
    this.instrumentFilter,
    this.captureSnapshot,
    this.onLoad,
  });

  @override
  ConsumerState<SaveBrowserPanel> createState() => _SaveBrowserPanelState();
}

class _SaveBrowserPanelState extends ConsumerState<SaveBrowserPanel> {
  String? _currentFolderId;
  String? _selectedSaveId;
  bool _editMode = false;

  // ── Computed helpers ──────────────────────────────────────────────────────

  List<SaveFolder> _breadcrumb(List<SaveFolder> allFolders) {
    final crumbs = <SaveFolder>[];
    String? walkId = _currentFolderId;
    while (walkId != null) {
      final f = allFolders.where((f) => f.id == walkId).firstOrNull;
      if (f == null) break;
      crumbs.insert(0, f);
      walkId = f.parentId;
    }
    return crumbs;
  }

  List<SaveFolder> _childFolders(List<SaveFolder> allFolders) =>
      getChildFolders(allFolders, _currentFolderId)
        ..sort((a, b) => a.order.compareTo(b.order));

  List<SaveEntry> _savesHere(List<SaveEntry> allSaves) {
    if (_currentFolderId == null) return [];
    final all = getSavesInFolder(allSaves, _currentFolderId!);
    final filter = widget.instrumentFilter;
    if (filter == null) return all;
    return all.where((s) => s.snapshot.instrument == filter).toList();
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<String?> _nameDialogWithSuggestions({
    required String title,
    required List<String> suggestions,
    String hint = 'Enter name…',
  }) async {
    var value = suggestions.isNotEmpty ? suggestions.first : '';
    final controller = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF141826),
          title: Text(
            title,
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (suggestions.isNotEmpty) ...
                [
                  const Text(
                    'SUGGESTIONS',
                    style: TextStyle(
                      color: MuzicianTheme.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: suggestions.map((s) {
                        final isSelected = controller.text.trim() == s;
                        return GestureDetector(
                          onTap: () {
                            controller.text = s;
                            setDialogState(() => value = s);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: isSelected
                                  ? MuzicianTheme.teal.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.06),
                              border: Border.all(
                                color: isSelected
                                    ? MuzicianTheme.teal.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.12),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                color: isSelected
                                    ? MuzicianTheme.teal
                                    : const Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              TextField(
                controller: controller,
                autofocus: suggestions.isEmpty,
                style: const TextStyle(color: MuzicianTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: suggestions.isNotEmpty
                      ? 'Or type a custom name…'
                      : hint,
                  hintStyle: const TextStyle(color: MuzicianTheme.textMuted),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: MuzicianTheme.textDim),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: MuzicianTheme.sky),
                  ),
                ),
                onChanged: (v) => setDialogState(() => value = v),
                onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: MuzicianTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(
                'OK',
                style: TextStyle(color: MuzicianTheme.sky),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _nameDialog({
    required String title,
    String? initial,
    String hint = 'Enter name…',
  }) async {
    var value = initial ?? '';
    final controller = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141826),
        title: Text(
          title,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: MuzicianTheme.textMuted),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: MuzicianTheme.textDim),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: MuzicianTheme.sky),
            ),
          ),
          onChanged: (v) => value = v,
          onSubmitted: (_) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: MuzicianTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, value.trim()),
            child: const Text(
              'OK',
              style: TextStyle(color: MuzicianTheme.sky),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog(String message) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF141826),
      content: Text(
        message,
        style: const TextStyle(color: MuzicianTheme.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: MuzicianTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Delete',
            style: TextStyle(color: MuzicianTheme.red),
          ),
        ),
      ],
    ),
  );

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _handleNewFolder() async {
    final name = await _nameDialog(title: 'New Folder', hint: 'Folder name…');
    if (name == null || name.isEmpty) return;
    ref
        .read(saveSystemProvider.notifier)
        .createSaveFolder(name, _currentFolderId);
    HapticFeedback.lightImpact();
  }

  Future<void> _handleSaveHere() async {
    final capture = widget.captureSnapshot;
    if (capture == null || _currentFolderId == null) return;
    final suggestions = _buildSuggestions();
    final name = await _nameDialogWithSuggestions(
      title: 'Save name',
      suggestions: suggestions,
      hint: 'e.g. Verse 1 – Chord…',
    );
    if (name == null || name.isEmpty) return;
    final snap = capture();
    ref
        .read(saveSystemProvider.notifier)
        .saveSnapshot(name, _currentFolderId!, snap);
    HapticFeedback.mediumImpact();
  }

  List<String> _buildSuggestions() {
    final List<String> selectedNotes;
    final List<String> highlightedNotes;

    if (widget.instrumentFilter == 'fretboard') {
      final s = ref.read(fretboardProvider);
      selectedNotes = s.selectedNotes;
      highlightedNotes = s.highlightedNotes;
    } else if (widget.instrumentFilter == 'piano') {
      final s = ref.read(pianoProvider);
      selectedNotes = s.selectedNotes;
      highlightedNotes = s.highlightedNotes;
    } else {
      return [];
    }

    if (selectedNotes.isEmpty) return [];

    final result = <String>{};

    // 1. Detected chord
    final chord = detectFirstChord(selectedNotes);
    if (chord != null) result.add('${chord.root}${chord.quality}');

    // 2. Notes + scale
    if (highlightedNotes.isNotEmpty) {
      for (final root in chromaticNotes) {
        final rootIdx = noteToPC[root]!;
        for (final entry in scaleIntervals.entries) {
          final scaleTones = entry.value
              .map((i) => chromaticNotes[(rootIdx + i) % 12])
              .toSet();
          final toneSet = highlightedNotes.toSet();
          if (scaleTones.length == toneSet.length &&
              scaleTones.every(toneSet.contains)) {
            result.add(
              '${selectedNotes.join(' ')} | $root ${entry.key}',
            );
            break;
          }
        }
        if (result.length >= 2) break;
      }
    }

    // 3. Note names only
    result.add(selectedNotes.join(' '));

    return result.toList();
  }

  Future<void> _handleRenameFolder(SaveFolder folder) async {
    final name = await _nameDialog(
      title: 'Rename folder',
      initial: folder.name,
      hint: 'Folder name…',
    );
    if (name == null || name.isEmpty) return;
    ref.read(saveSystemProvider.notifier).renameFolder(folder.id, name);
  }

  Future<void> _handleRenameSave(SaveEntry save) async {
    final name = await _nameDialog(
      title: 'Rename save',
      initial: save.name,
      hint: 'Save name…',
    );
    if (name == null || name.isEmpty) return;
    ref.read(saveSystemProvider.notifier).renameSave(save.id, name);
  }

  Future<void> _handleDeleteFolder(SaveFolder folder) async {
    final confirmed = await _confirmDialog(
      'Delete "${folder.name}" and all its contents?',
    );
    if (confirmed != true) return;
    if (_currentFolderId == folder.id) {
      setState(() {
        _currentFolderId = folder.parentId;
        _selectedSaveId = null;
      });
    }
    ref.read(saveSystemProvider.notifier).deleteFolder(folder.id);
    HapticFeedback.mediumImpact();
  }

  Future<void> _handleDeleteSave(SaveEntry save) async {
    final confirmed = await _confirmDialog('Delete "${save.name}"?');
    if (confirmed != true) return;
    if (_selectedSaveId == save.id) {
      setState(() => _selectedSaveId = null);
    }
    ref.read(saveSystemProvider.notifier).deleteSave(save.id);
    HapticFeedback.mediumImpact();
  }

  void _handleLoad(SaveEntry save) {
    final onLoad = widget.onLoad;
    if (onLoad == null) return;
    ref.read(saveSystemProvider.notifier).loadSave(save.id, onLoad);
    HapticFeedback.mediumImpact();
  }

  void _navigatePrev() {
    ref.read(saveSystemProvider.notifier).navigatePrev((snap) {
      widget.onLoad?.call(snap);
      final session = ref.read(saveSystemProvider).activeSession;
      if (session != null) setState(() => _selectedSaveId = session.saveId);
    });
    HapticFeedback.selectionClick();
  }

  void _navigateNext() {
    ref.read(saveSystemProvider.notifier).navigateNext((snap) {
      widget.onLoad?.call(snap);
      final session = ref.read(saveSystemProvider).activeSession;
      if (session != null) setState(() => _selectedSaveId = session.saveId);
    });
    HapticFeedback.selectionClick();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ssState = ref.watch(saveSystemProvider);
    final notifier = ref.read(saveSystemProvider.notifier);

    final breadcrumb = _breadcrumb(ssState.folders);
    final subFolders = _childFolders(ssState.folders);
    final saves = _savesHere(ssState.saves);

    final selectedSave = _selectedSaveId != null
        ? ssState.saves.where((s) => s.id == _selectedSaveId).firstOrNull
        : null;

    final activeSession = ssState.activeSession;
    final adjSaves = getAdjacentSaves(ssState.saves, activeSession);
    final hasPrev =
        activeSession != null &&
        activeSession.folderId == _currentFolderId &&
        adjSaves.prev != null;
    final hasNext =
        activeSession != null &&
        activeSession.folderId == _currentFolderId &&
        adjSaves.next != null;

    final insideFolder = _currentFolderId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ──
        _Header(
          insideFolder: insideFolder,
          editMode: _editMode,
          canSave: widget.captureSnapshot != null && insideFolder,
          onToggleEdit: () => setState(() {
            _editMode = !_editMode;
            if (_editMode) _selectedSaveId = null;
          }),
          onNewFolder: _handleNewFolder,
          onSaveHere: _handleSaveHere,
        ),

        // ── Breadcrumb ──
        if (breadcrumb.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Breadcrumb(
            breadcrumb: breadcrumb,
            onRoot: () => setState(() {
              _currentFolderId = null;
              _selectedSaveId = null;
            }),
            onNavigate: (id) => setState(() {
              _currentFolderId = id;
              _selectedSaveId = null;
            }),
            onBack: () => setState(() {
              _currentFolderId = breadcrumb.length > 1
                  ? breadcrumb[breadcrumb.length - 2].id
                  : null;
              _selectedSaveId = null;
            }),
          ),
        ],

        const SizedBox(height: 8),

        // ── Folder + Save list ──
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (subFolders.isEmpty && saves.isEmpty && !insideFolder)
                  _EmptyHint(
                    message: widget.captureSnapshot != null
                        ? 'Create a folder, then navigate into it to save.'
                        : 'No folders yet.',
                  ),
                if (insideFolder && subFolders.isEmpty && saves.isEmpty)
                  _EmptyHint(
                    message: widget.captureSnapshot != null
                        ? 'No saves here. Tap "Save here" to add one.'
                        : 'No saves in this folder.',
                  ),
                // folders
                ...subFolders.map(
                  (folder) => _FolderRow(
                    folder: folder,
                    editMode: _editMode,
                    isFirst: subFolders.first == folder,
                    isLast: subFolders.last == folder,
                    onTap: () => setState(() {
                      _currentFolderId = folder.id;
                      _selectedSaveId = null;
                    }),
                    onRename: () => _handleRenameFolder(folder),
                    onDelete: () => _handleDeleteFolder(folder),
                    onMoveUp: () => notifier.moveFolderUp(folder.id),
                    onMoveDown: () => notifier.moveFolderDown(folder.id),
                  ),
                ),
                // saves
                ...saves.map(
                  (save) => _SaveRow(
                    save: save,
                    isSelected: _selectedSaveId == save.id,
                    isActiveSession: activeSession?.saveId == save.id,
                    editMode: _editMode,
                    isFirst: saves.first == save,
                    isLast: saves.last == save,
                    onTap: () => setState(() {
                      _selectedSaveId =
                          _selectedSaveId == save.id ? null : save.id;
                    }),
                    onRename: () => _handleRenameSave(save),
                    onDelete: () => _handleDeleteSave(save),
                    onMoveUp: () => notifier.moveSaveUp(save.id),
                    onMoveDown: () => notifier.moveSaveDown(save.id),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Selected save preview ──
        if (selectedSave != null && !_editMode) ...[
          Divider(
            color: MuzicianTheme.glassBorder,
            height: 16,
            thickness: 0.5,
          ),
          _SavePreview(
            save: selectedSave,
            canLoad: widget.onLoad != null,
            hasPrev: hasPrev,
            hasNext: hasNext,
            isActiveSession: activeSession?.saveId == selectedSave.id,
            onLoad: () => _handleLoad(selectedSave),
            onPrev: _navigatePrev,
            onNext: _navigateNext,
          ),
        ],
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool insideFolder;
  final bool editMode;
  final bool canSave;
  final VoidCallback onToggleEdit;
  final VoidCallback onNewFolder;
  final VoidCallback onSaveHere;

  const _Header({
    required this.insideFolder,
    required this.editMode,
    required this.canSave,
    required this.onToggleEdit,
    required this.onNewFolder,
    required this.onSaveHere,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'SAVES',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (canSave) ...[
          _ActionChip(
            label: 'Save here',
            color: MuzicianTheme.emerald,
            onTap: onSaveHere,
          ),
          const SizedBox(width: 6),
        ],
        _ActionChip(
          label: '+ Folder',
          color: MuzicianTheme.sky,
          onTap: onNewFolder,
        ),
        const SizedBox(width: 6),
        _ActionChip(
          label: editMode ? 'Done' : 'Edit',
          color: editMode ? MuzicianTheme.orange : MuzicianTheme.textSecondary,
          onTap: onToggleEdit,
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final List<SaveFolder> breadcrumb;
  final VoidCallback onRoot;
  final void Function(String id) onNavigate;
  final VoidCallback onBack;

  const _Breadcrumb({
    required this.breadcrumb,
    required this.onRoot,
    required this.onNavigate,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              GestureDetector(
                onTap: onRoot,
                child: const Text(
                  '⌂',
                  style: TextStyle(
                    color: MuzicianTheme.sky,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...breadcrumb.asMap().entries.expand(
                (e) => [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '›',
                      style: TextStyle(
                        color: MuzicianTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => onNavigate(e.value.id),
                    child: Text(
                      e.value.name,
                      style: TextStyle(
                        color: e.key == breadcrumb.length - 1
                            ? MuzicianTheme.textPrimary
                            : MuzicianTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: e.key == breadcrumb.length - 1
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '← Back',
              style: TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: MuzicianTheme.textMuted,
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

class _FolderRow extends StatelessWidget {
  final SaveFolder folder;
  final bool editMode;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _FolderRow({
    required this.folder,
    required this.editMode,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Row(
        children: [
          if (editMode) ...[
            Column(
              children: [
                _UpDownButton(
                  icon: Icons.arrow_upward,
                  enabled: !isFirst,
                  onTap: onMoveUp,
                ),
                _UpDownButton(
                  icon: Icons.arrow_downward,
                  enabled: !isLast,
                  onTap: onMoveDown,
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
          GestureDetector(
            onTap: editMode ? onRename : onTap,
            child: Text(
              folder.progressionMeta != null ? '🎼' : '📁',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: editMode ? onRename : onTap,
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: editMode
                      ? MuzicianTheme.orange
                      : MuzicianTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: editMode ? TextDecoration.underline : null,
                  decorationColor: MuzicianTheme.orange,
                ),
              ),
            ),
          ),
          if (editMode)
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: MuzicianTheme.red,
                ),
              ),
            )
          else
            const Text(
              '›',
              style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 16),
            ),
        ],
      ),
    );
  }
}

class _SaveRow extends StatelessWidget {
  final SaveEntry save;
  final bool isSelected;
  final bool isActiveSession;
  final bool editMode;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _SaveRow({
    required this.save,
    required this.isSelected,
    required this.isActiveSession,
    required this.editMode,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  String get _icon =>
      save.snapshot.instrument == 'piano' ? '🎹' : '🎸';

  Color get _accentColor => isActiveSession
      ? MuzicianTheme.emerald
      : isSelected
          ? MuzicianTheme.sky
          : MuzicianTheme.textSecondary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: editMode ? onRename : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected && !editMode
              ? MuzicianTheme.sky.withValues(alpha: 0.1)
              : isActiveSession && !editMode
                  ? MuzicianTheme.emerald.withValues(alpha: 0.08)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected && !editMode
                ? MuzicianTheme.sky.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            if (editMode) ...[
              Column(
                children: [
                  _UpDownButton(
                    icon: Icons.arrow_upward,
                    enabled: !isFirst,
                    onTap: onMoveUp,
                  ),
                  _UpDownButton(
                    icon: Icons.arrow_downward,
                    enabled: !isLast,
                    onTap: onMoveDown,
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            Text(_icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    save.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _accentColor,
                      fontSize: 13,
                      fontWeight: isSelected || isActiveSession
                          ? FontWeight.w700
                          : FontWeight.w500,
                      decoration: editMode ? TextDecoration.underline : null,
                      decorationColor: MuzicianTheme.orange,
                    ),
                  ),
                  if (save.snapshot.pendingChord != null)
                    Text(
                      save.snapshot.pendingChord!.symbol,
                      style: const TextStyle(
                        color: MuzicianTheme.violet,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (isActiveSession && !editMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: MuzicianTheme.emerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'active',
                  style: TextStyle(
                    color: MuzicianTheme.emerald,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            if (editMode)
              GestureDetector(
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: MuzicianTheme.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UpDownButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _UpDownButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Icon(
      icon,
      size: 14,
      color: enabled ? MuzicianTheme.sky : MuzicianTheme.textDim,
    ),
  );
}

class _SavePreview extends StatelessWidget {
  final SaveEntry save;
  final bool canLoad;
  final bool hasPrev;
  final bool hasNext;
  final bool isActiveSession;
  final VoidCallback onLoad;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _SavePreview({
    required this.save,
    required this.canLoad,
    required this.hasPrev,
    required this.hasNext,
    required this.isActiveSession,
    required this.onLoad,
    required this.onPrev,
    required this.onNext,
  });

  String get _instrumentLabel =>
      save.snapshot.instrument == 'piano' ? 'Piano' : 'Fretboard';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Save name + instrument
        Row(
          children: [
            Text(
              save.snapshot.instrument == 'piano' ? '🎹' : '🎸',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    save.name,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _instrumentLabel,
                    style: const TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Notes chips
        if (save.snapshot.selectedNotes.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: save.snapshot.selectedNotes.map((note) {
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.sky.withValues(alpha: 0.12),
                    border: Border.all(
                      color: MuzicianTheme.sky.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    note,
                    style: const TextStyle(
                      color: MuzicianTheme.sky,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
        ],
        // Chord / scale context
        if (save.snapshot.pendingChord != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              'Chord: ${save.snapshot.pendingChord!.symbol}',
              style: const TextStyle(
                color: MuzicianTheme.violet,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (save.snapshot.pendingScale != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              'Scale: ${save.snapshot.pendingScale!.root} ${save.snapshot.pendingScale!.scaleName}',
              style: const TextStyle(
                color: MuzicianTheme.emerald,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Load + navigation row
        Row(
          children: [
            if (hasPrev)
              _NavButton(
                label: '← Prev',
                onTap: onPrev,
              ),
            if (hasPrev) const SizedBox(width: 6),
            if (canLoad)
              Expanded(
                child: GestureDetector(
                  onTap: onLoad,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isActiveSession
                          ? MuzicianTheme.emerald.withValues(alpha: 0.15)
                          : MuzicianTheme.sky.withValues(alpha: 0.15),
                      border: Border.all(
                        color: isActiveSession
                            ? MuzicianTheme.emerald.withValues(alpha: 0.4)
                            : MuzicianTheme.sky.withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        isActiveSession ? 'Reload' : 'Load',
                        style: TextStyle(
                          color: isActiveSession
                              ? MuzicianTheme.emerald
                              : MuzicianTheme.sky,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (hasNext) const SizedBox(width: 6),
            if (hasNext)
              _NavButton(
                label: 'Next →',
                onTap: onNext,
              ),
          ],
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NavButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MuzicianTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
