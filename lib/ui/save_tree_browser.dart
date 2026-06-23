/// SaveTreeBrowser — visual folder + save library with snapshot previews.
///
/// Reusable across save and load flows. Same provider-backed data as
/// [SaveBrowserPanel] but renders each save with a glance-thumbnail of its
/// content (see lib/ui/save_previews/) and hides folders that contain no
/// matching saves when an [instrumentFilter] is active.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/save_system.dart';
import '../schema/rules/save_system_rules.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
import 'core/muzician_dialog.dart';
import 'save_previews/save_preview_thumbnail.dart';

class SaveTreeBrowser extends ConsumerStatefulWidget {
  /// Only saves whose `snapshot.instrument` equals this value are shown.
  /// Folders without any matching descendant save are hidden as well.
  final String? instrumentFilter;

  /// When set, a "Save here" button appears inside folders.
  final InstrumentSnapshot Function()? captureSnapshot;

  /// Called when the user picks a save. Receives the loaded snapshot.
  final void Function(InstrumentSnapshot snap)? onLoad;

  /// Optional label displayed in the empty-state below the breadcrumb.
  final String? emptyLabel;

  const SaveTreeBrowser({
    super.key,
    this.instrumentFilter,
    this.captureSnapshot,
    this.onLoad,
    this.emptyLabel,
  });

  @override
  ConsumerState<SaveTreeBrowser> createState() => _SaveTreeBrowserState();
}

class _SaveTreeBrowserState extends ConsumerState<SaveTreeBrowser> {
  String? _currentFolderId;

  // ── Filtering helpers ──────────────────────────────────────────────────────

  bool _folderHasMatch(
    SaveFolder folder,
    List<SaveFolder> allFolders,
    List<SaveEntry> allSaves,
  ) {
    final filter = widget.instrumentFilter;
    if (filter == null) return true;
    final ids = <String>{
      folder.id,
      ...getDescendantFolderIds(allFolders, folder.id),
    };
    return allSaves.any(
      (s) => ids.contains(s.folderId) && s.snapshot.instrument == filter,
    );
  }

  List<SaveFolder> _visibleChildFolders(
    List<SaveFolder> allFolders,
    List<SaveEntry> allSaves,
  ) {
    final children = getChildFolders(allFolders, _currentFolderId)
      ..sort((a, b) => a.order.compareTo(b.order));
    if (widget.instrumentFilter == null) return children;
    return children
        .where((f) => _folderHasMatch(f, allFolders, allSaves))
        .toList();
  }

  List<SaveEntry> _visibleSaves(List<SaveEntry> allSaves) {
    if (_currentFolderId == null) return const [];
    final inFolder = getSavesInFolder(allSaves, _currentFolderId!);
    final filter = widget.instrumentFilter;
    if (filter == null) return inFolder;
    return inFolder.where((s) => s.snapshot.instrument == filter).toList();
  }

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

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> _handleNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => MuzicianDialog(
        title: 'New folder',
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: MuzicianTheme.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.pop(ctx),
          ),
          MuzicianDialogButton(
            'Create',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    ref
        .read(saveSystemProvider.notifier)
        .createSaveFolder(name, _currentFolderId);
    HapticFeedback.lightImpact();
  }

  Future<void> _handleSaveHere() async {
    final capture = widget.captureSnapshot;
    if (capture == null || _currentFolderId == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => MuzicianDialog(
        title: 'Name your save',
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Save name',
            hintStyle: TextStyle(color: MuzicianTheme.textMuted),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.pop(ctx),
          ),
          MuzicianDialogButton(
            'Save',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    ref
        .read(saveSystemProvider.notifier)
        .saveSnapshot(name, _currentFolderId!, capture());
    HapticFeedback.mediumImpact();
  }

  void _handleLoad(SaveEntry save) {
    final onLoad = widget.onLoad;
    if (onLoad == null) return;
    ref.read(saveSystemProvider.notifier).loadSave(save.id, onLoad);
    HapticFeedback.mediumImpact();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ssState = ref.watch(saveSystemProvider);
    final breadcrumb = _breadcrumb(ssState.folders);
    final folders = _visibleChildFolders(ssState.folders, ssState.saves);
    final saves = _visibleSaves(ssState.saves);
    final insideFolder = _currentFolderId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderBar(
          insideFolder: insideFolder,
          canSave: widget.captureSnapshot != null && insideFolder,
          onNewFolder: _handleNewFolder,
          onSaveHere: _handleSaveHere,
        ),
        if (breadcrumb.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Breadcrumb(
            breadcrumb: breadcrumb,
            onRoot: () => setState(() => _currentFolderId = null),
            onNavigate: (id) => setState(() => _currentFolderId = id),
            onBack: () => setState(
              () => _currentFolderId = breadcrumb.length > 1
                  ? breadcrumb[breadcrumb.length - 2].id
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: (folders.isEmpty && saves.isEmpty)
              ? _EmptyState(
                  insideFolder: insideFolder,
                  filter: widget.instrumentFilter,
                  emptyLabel: widget.emptyLabel,
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final folder in folders)
                      _FolderRow(
                        folder: folder,
                        onTap: () =>
                            setState(() => _currentFolderId = folder.id),
                      ),
                    if (folders.isNotEmpty && saves.isNotEmpty)
                      const SizedBox(height: 8),
                    for (final save in saves)
                      _SaveRow(save: save, onLoad: () => _handleLoad(save)),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─── Header bar ──────────────────────────────────────────────────────────────

class _HeaderBar extends StatelessWidget {
  final bool insideFolder;
  final bool canSave;
  final VoidCallback onNewFolder;
  final VoidCallback onSaveHere;

  const _HeaderBar({
    required this.insideFolder,
    required this.canSave,
    required this.onNewFolder,
    required this.onSaveHere,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
      child: Row(
        children: [
          const Text(
            'Library',
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onNewFolder,
            icon: const Icon(
              Icons.create_new_folder_outlined,
              color: MuzicianTheme.sky,
              size: 18,
            ),
            label: const Text(
              'Folder',
              style: TextStyle(color: MuzicianTheme.sky, fontSize: 13),
            ),
          ),
          if (canSave)
            TextButton.icon(
              onPressed: onSaveHere,
              icon: const Icon(
                Icons.save_outlined,
                color: MuzicianTheme.emerald,
                size: 18,
              ),
              label: const Text(
                'Save here',
                style: TextStyle(color: MuzicianTheme.emerald, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Breadcrumb ──────────────────────────────────────────────────────────────

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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: MuzicianTheme.textSecondary,
              size: 16,
            ),
            onPressed: onBack,
          ),
          InkWell(
            onTap: onRoot,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Library',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          for (var i = 0; i < breadcrumb.length; i++) ...[
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: MuzicianTheme.textMuted,
            ),
            InkWell(
              onTap: () => onNavigate(breadcrumb[i].id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  breadcrumb[i].name,
                  style: TextStyle(
                    color: i == breadcrumb.length - 1
                        ? MuzicianTheme.textPrimary
                        : MuzicianTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: i == breadcrumb.length - 1
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Rows ────────────────────────────────────────────────────────────────────

class _FolderRow extends StatelessWidget {
  final SaveFolder folder;
  final VoidCallback onTap;

  const _FolderRow({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_outlined,
                    color: MuzicianTheme.sky,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      folder.name,
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: MuzicianTheme.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveRow extends StatelessWidget {
  final SaveEntry save;
  final VoidCallback onLoad;

  const _SaveRow({required this.save, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    final instrumentLabel = _instrumentLabel(save.snapshot.instrument);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onLoad,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                SavePreviewThumbnail(snapshot: save.snapshot),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        save.name,
                        style: const TextStyle(
                          color: MuzicianTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        instrumentLabel,
                        style: const TextStyle(
                          color: MuzicianTheme.textMuted,
                          fontSize: 11,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.download_outlined,
                  color: MuzicianTheme.sky,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _instrumentLabel(String instrument) {
    switch (instrument) {
      case 'piano':
        return 'PIANO';
      case 'fretboard':
        return 'FRETBOARD';
      case 'piano_roll':
        return 'PIANO ROLL';
      case 'song':
        return 'SONG';
      default:
        return instrument.toUpperCase();
    }
  }
}

class _EmptyState extends StatelessWidget {
  final bool insideFolder;
  final String? filter;
  final String? emptyLabel;

  const _EmptyState({
    required this.insideFolder,
    required this.filter,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final message = emptyLabel ?? _defaultMessage();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              color: MuzicianTheme.textMuted.withValues(alpha: 0.5),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MuzicianTheme.textMuted.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _defaultMessage() {
    if (!insideFolder) {
      return filter == null
          ? 'No folders yet. Create one to start saving.'
          : 'No saves of this type yet.\nCreate one from its instrument tab.';
    }
    return filter == null
        ? 'Empty folder.'
        : 'No matching saves in this folder.';
  }
}
