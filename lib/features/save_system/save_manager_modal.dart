/// SaveManagerModal – full-screen bottom-sheet for browsing, creating,
/// loading, and organising saves in a nested folder tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../schema/rules/save_system_rules.dart';
import '../../store/save_system_store.dart';
import '../../theme/muzician_theme.dart';

enum SaveManagerMode { defaultMode, folderPicker, progressionLoader }

class SaveManagerModal extends ConsumerStatefulWidget {
  final String instrument; // 'fretboard' | 'piano'
  final SaveManagerMode mode;
  final void Function(String? folderId)? onSelectFolder;
  final void Function(String folderId)? onLoadProgressionFolder;
  final InstrumentSnapshot Function()? captureSnapshot;
  final void Function(InstrumentSnapshot)? applySnapshot;
  final void Function({required String type, required String message})?
  onLoadFeedback;

  const SaveManagerModal({
    super.key,
    this.instrument = 'fretboard',
    this.mode = SaveManagerMode.defaultMode,
    this.onSelectFolder,
    this.onLoadProgressionFolder,
    this.captureSnapshot,
    this.applySnapshot,
    this.onLoadFeedback,
  });

  @override
  ConsumerState<SaveManagerModal> createState() => _SaveManagerModalState();
}

class _SaveManagerModalState extends ConsumerState<SaveManagerModal> {
  String? _currentFolderId;
  bool _showSaveForm = false;
  bool _showNewFolderForm = false;
  final _saveNameCtrl = TextEditingController();
  final _folderNameCtrl = TextEditingController();

  @override
  void dispose() {
    _saveNameCtrl.dispose();
    _folderNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sState = ref.watch(saveSystemProvider);
    final notifier = ref.read(saveSystemProvider.notifier);
    final subFolders = getChildFolders(sState.folders, _currentFolderId);
    final savesHere = _currentFolderId != null
        ? getSavesInFolder(
            sState.saves,
            _currentFolderId!,
          ).where((e) => e.snapshot.instrument == widget.instrument).toList()
        : <SaveEntry>[];
    final breadcrumb = _currentFolderId != null
        ? buildFolderBreadcrumb(sState.folders, _currentFolderId!)
        : <({String id, String name})>[];

    final visibleSaves = widget.mode == SaveManagerMode.progressionLoader
        ? <SaveEntry>[]
        : savesHere;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: MuzicianTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.mode == SaveManagerMode.progressionLoader
                          ? 'Load Progression'
                          : 'Save Manager',
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                      child: const Center(
                        child: Text(
                          '✕',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Breadcrumb
            if (_currentFolderId != null && breadcrumb.isNotEmpty)
              _buildBreadcrumb(breadcrumb),
            // Toolbar
            _buildToolbar(notifier),
            // Inline forms
            if (_showNewFolderForm) _buildNewFolderForm(notifier),
            if (_showSaveForm && _currentFolderId != null)
              _buildSaveForm(notifier),
            // Hint
            if (_currentFolderId == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Text(
                  widget.mode == SaveManagerMode.progressionLoader
                      ? 'Tap a 🎼 folder to load that progression.'
                      : 'Create folders to organise saves by song › part › chord.',
                  style: TextStyle(color: MuzicianTheme.textDim, fontSize: 12),
                ),
              ),
            // List
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: _currentFolderId != null
                    ? subFolders.length +
                          visibleSaves.length +
                          (subFolders.isEmpty && visibleSaves.isEmpty ? 1 : 0)
                    : subFolders.isEmpty
                    ? 1
                    : subFolders.length,
                itemBuilder: (context, index) {
                  if (_currentFolderId == null) {
                    if (subFolders.isEmpty) return _emptyItem();
                    return _folderRow(subFolders[index], notifier, sState);
                  }
                  if (subFolders.isEmpty && visibleSaves.isEmpty) {
                    return _emptyItem();
                  }
                  if (index < subFolders.length) {
                    return _folderRow(subFolders[index], notifier, sState);
                  }
                  final saveIdx = index - subFolders.length;
                  if (saveIdx < visibleSaves.length) {
                    return _saveRow(visibleSaves[saveIdx], notifier, sState);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(List<({String id, String name})> crumbs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _currentFolderId = null),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: const Center(
                child: Text(
                  '⌂',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
              ),
            ),
          ),
          ...crumbs.expand(
            (c) => [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '›',
                  style: TextStyle(color: Color(0xFF334155), fontSize: 14),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _currentFolderId = c.id),
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: c.id == _currentFolderId
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(SaveSystemNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (_currentFolderId != null)
            _toolbarBtn('← Back', () {
              final sState = ref.read(saveSystemProvider);
              final breadcrumb = buildFolderBreadcrumb(
                sState.folders,
                _currentFolderId!,
              );
              setState(() {
                _currentFolderId = breadcrumb.length > 1
                    ? breadcrumb[breadcrumb.length - 2].id
                    : null;
              });
              HapticFeedback.selectionClick();
            }),
          const Spacer(),
          _toolbarBtn('＋ Folder', () {
            setState(() {
              _showNewFolderForm = !_showNewFolderForm;
              _showSaveForm = false;
            });
          }),
          if (_currentFolderId != null &&
              widget.mode == SaveManagerMode.defaultMode) ...[
            const SizedBox(width: 8),
            _toolbarBtn('＋ Save', () {
              setState(() {
                _showSaveForm = !_showSaveForm;
                _showNewFolderForm = false;
              });
            }, primary: true),
          ],
          if (widget.mode == SaveManagerMode.folderPicker) ...[
            const SizedBox(width: 8),
            _toolbarBtn('✓ Save Here', () {
              HapticFeedback.heavyImpact();
              widget.onSelectFolder?.call(_currentFolderId);
            }, accent: true),
          ],
        ],
      ),
    );
  }

  Widget _toolbarBtn(
    String label,
    VoidCallback onTap, {
    bool primary = false,
    bool accent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: accent
              ? MuzicianTheme.teal.withValues(alpha: 0.14)
              : primary
              ? MuzicianTheme.sky.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: accent
                ? MuzicianTheme.teal.withValues(alpha: 0.35)
                : primary
                ? MuzicianTheme.sky.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent
                ? MuzicianTheme.teal
                : primary
                ? MuzicianTheme.sky
                : const Color(0xFF94A3B8),
            fontSize: 13,
            fontWeight: primary || accent ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildNewFolderForm(SaveSystemNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _folderNameCtrl,
                autofocus: true,
                maxLength: 60,
                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Folder name…',
                  hintStyle: TextStyle(color: MuzicianTheme.textMuted),
                  counterText: '',
                  isDense: true,
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _createFolder(notifier),
              ),
            ),
            _toolbarBtn('Create', () => _createFolder(notifier)),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveForm(SaveSystemNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _saveNameCtrl,
                autofocus: true,
                maxLength: 80,
                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Save name (e.g. C chord, Intro arp)…',
                  hintStyle: TextStyle(color: MuzicianTheme.textMuted),
                  counterText: '',
                  isDense: true,
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _saveCurrent(notifier),
              ),
            ),
            _toolbarBtn('Save', () => _saveCurrent(notifier)),
          ],
        ),
      ),
    );
  }

  void _createFolder(SaveSystemNotifier notifier) {
    final name = _folderNameCtrl.text.trim();
    final id = notifier.createSaveFolder(name, _currentFolderId);
    if (id != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _folderNameCtrl.clear();
        _showNewFolderForm = false;
      });
    }
  }

  void _saveCurrent(SaveSystemNotifier notifier) {
    if (_currentFolderId == null || widget.captureSnapshot == null) return;
    final name = _saveNameCtrl.text.trim();
    final snapshot = widget.captureSnapshot!();
    final id = notifier.saveSnapshot(name, _currentFolderId!, snapshot);
    if (id != null) {
      HapticFeedback.heavyImpact();
      setState(() {
        _saveNameCtrl.clear();
        _showSaveForm = false;
      });
    }
  }

  Widget _emptyItem() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          _currentFolderId != null
              ? 'No saves here yet. Tap ＋ Save to add one.'
              : 'No folders yet. Create one to get started.',
          style: TextStyle(color: MuzicianTheme.textDim, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _folderRow(
    SaveFolder folder,
    SaveSystemNotifier notifier,
    SaveSystemState sState,
  ) {
    final isProgression = folder.progressionMeta != null;
    return GestureDetector(
      onTap: () {
        if (widget.mode == SaveManagerMode.progressionLoader && isProgression) {
          HapticFeedback.heavyImpact();
          widget.onLoadProgressionFolder?.call(folder.id);
        } else {
          setState(() => _currentFolderId = folder.id);
          HapticFeedback.selectionClick();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isProgression
              ? MuzicianTheme.teal.withValues(alpha: 0.08)
              : MuzicianTheme.glassBg,
          border: Border.all(
            color: isProgression
                ? MuzicianTheme.teal.withValues(alpha: 0.25)
                : MuzicianTheme.glassBorder,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Text(
              isProgression ? '🎼' : '📁',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                style: TextStyle(
                  color: isProgression
                      ? MuzicianTheme.teal
                      : const Color(0xFFCBD5E1),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _miniBtn('✎', const Color(0xFF94A3B8), () {
              // TODO: rename
            }),
            const SizedBox(width: 4),
            _miniBtn('✕', MuzicianTheme.red, () {
              notifier.deleteFolder(folder.id);
              HapticFeedback.heavyImpact();
            }),
            if (!(widget.mode == SaveManagerMode.progressionLoader &&
                isProgression))
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Text(
                  '›',
                  style: TextStyle(color: Color(0xFF334155), fontSize: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _saveRow(
    SaveEntry save,
    SaveSystemNotifier notifier,
    SaveSystemState sState,
  ) {
    final isActive = sState.activeSession?.saveId == save.id;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isActive
            ? MuzicianTheme.sky.withValues(alpha: 0.08)
            : MuzicianTheme.glassBg,
        border: Border.all(
          color: isActive
              ? MuzicianTheme.sky.withValues(alpha: 0.2)
              : MuzicianTheme.glassBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Text(
            save.progressionMeta != null ? '🎵' : '🌸',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  save.name,
                  style: TextStyle(
                    color: isActive
                        ? MuzicianTheme.sky
                        : const Color(0xFFCBD5E1),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      save.progressionMeta != null
                          ? save.progressionMeta!.chordNotes.join(', ')
                          : _formatDate(save.updatedAt),
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: save.snapshot.instrument == 'piano'
                            ? MuzicianTheme.violet.withValues(alpha: 0.12)
                            : MuzicianTheme.orange.withValues(alpha: 0.12),
                        border: Border.all(
                          color: save.snapshot.instrument == 'piano'
                              ? MuzicianTheme.violet.withValues(alpha: 0.4)
                              : MuzicianTheme.orange.withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        save.snapshot.instrument == 'piano' ? '🎹' : '🎸',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.mode != SaveManagerMode.folderPicker) ...[
            _miniBtn('Load', MuzicianTheme.sky, () {
              if (widget.applySnapshot != null) {
                notifier.loadSave(save.id, widget.applySnapshot!);
                Navigator.of(context).pop();
                HapticFeedback.heavyImpact();
                widget.onLoadFeedback?.call(
                  type: 'success',
                  message: 'Save loaded.',
                );
              }
            }),
            const SizedBox(width: 4),
          ],
          _miniBtn('✕', MuzicianTheme.red, () {
            notifier.deleteSave(save.id);
            HapticFeedback.heavyImpact();
          }),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _formatDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}
