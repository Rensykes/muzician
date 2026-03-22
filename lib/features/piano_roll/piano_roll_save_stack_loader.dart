/// PianoRollSaveStackLoader – folder browser that loads saved instrument
/// snapshots as note stacks into the piano roll (exact or pitch-class mode).
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../store/save_system_store.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../schema/rules/save_system_rules.dart';
import '../../theme/muzician_theme.dart';

// ── MIDI helpers ────────────────────────────────────────────────────────────

const _noteToPC = <String, int>{
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

int? _bestMidiInRange(String pitchClass, int rangeStart, int rangeEnd, int anchor) {
  final pc = _noteToPC[pitchClass];
  if (pc == null) return null;
  int? best;
  var bestDist = 9999;
  for (var midi = rangeStart; midi <= rangeEnd; midi++) {
    if (((midi % 12) + 12) % 12 != pc) continue;
    final dist = (midi - anchor).abs();
    if (dist < bestDist) {
      best = midi;
      bestDist = dist;
    }
  }
  return best;
}

int? _noteNameToMidi(String noteName) {
  // Parse "C#4" => pitch class + octave => MIDI
  final match = RegExp(r'^([A-G]#?)(\d+)$').firstMatch(noteName);
  if (match == null) return null;
  final pc = _noteToPC[match.group(1)!];
  if (pc == null) return null;
  final octave = int.tryParse(match.group(2)!);
  if (octave == null) return null;
  return (octave + 1) * 12 + pc;
}

List<int> _extractMidis(InstrumentSnapshot snap, String mode, int rangeStart, int rangeEnd) {
  if (mode == 'exact') {
    if (snap is FretboardSnapshot) {
      // Fretboard cells don't carry MIDI directly; compute from noteName
      return snap.selectedCells
          .map((c) => _noteNameToMidi(c.noteName))
          .whereType<int>()
          .where((m) => m >= rangeStart && m <= rangeEnd)
          .toList();
    } else if (snap is PianoSnapshot) {
      return snap.selectedKeys
          .map((k) => k.midiNote)
          .where((m) => m >= rangeStart && m <= rangeEnd)
          .toList();
    }
    return [];
  }
  // pitch-class mode: map each unique pitch class to nearest MIDI in range
  final pcs = snap.selectedNotes.toSet();
  if (pcs.isEmpty) return [];
  final anchor = ((rangeStart + rangeEnd) / 2).round();
  return pcs
      .map((pc) => _bestMidiInRange(pc, rangeStart, rangeEnd, anchor))
      .whereType<int>()
      .toList();
}

// ── Widget ──────────────────────────────────────────────────────────────────

class PianoRollSaveStackLoader extends ConsumerStatefulWidget {
  final VoidCallback? onStackAdded;
  const PianoRollSaveStackLoader({super.key, this.onStackAdded});

  @override
  ConsumerState<PianoRollSaveStackLoader> createState() =>
      _PianoRollSaveStackLoaderState();
}

class _PianoRollSaveStackLoaderState
    extends ConsumerState<PianoRollSaveStackLoader> {
  String? _currentFolderId;
  String? _selectedSaveId;
  String _placementMode = 'exact';

  @override
  Widget build(BuildContext context) {
    final ssState = ref.watch(saveSystemProvider);
    final prState = ref.watch(pianoRollProvider);
    final prNotifier = ref.read(pianoRollProvider.notifier);

    // Build breadcrumb
    final breadcrumb = <SaveFolder>[];
    String? walkId = _currentFolderId;
    while (walkId != null) {
      final folder = ssState.folders.where((f) => f.id == walkId).firstOrNull;
      if (folder == null) break;
      breadcrumb.insert(0, folder);
      walkId = folder.parentId;
    }

    // Items at current level
    final subFolders = getChildFolders(ssState.folders, _currentFolderId)
      ..sort((a, b) => a.order.compareTo(b.order));
    final saves = getSavesInFolder(ssState.saves, _currentFolderId ?? '')
      ..sort((a, b) => a.order.compareTo(b.order));

    // Resolve saves at root when no folder selected
    final rootSaves = _currentFolderId == null
        ? <SaveEntry>[]
        : saves;

    final selectedSave = _selectedSaveId != null
        ? ssState.saves.where((s) => s.id == _selectedSaveId).firstOrNull
        : null;

    final previewMidis = selectedSave != null
        ? _extractMidis(
            selectedSave.snapshot,
            _placementMode,
            prState.pitchRangeStart,
            prState.pitchRangeEnd,
          )
        : <int>[];

    void handleAddStack() {
      if (previewMidis.isEmpty) return;
      final maxTicks = rules.totalTicks(
          prState.config.timeSignature, prState.config.totalMeasures);
      final fallbackStart = min(
        maxTicks - 1,
        prState.notes.fold<int>(
            0, (acc, n) => max(acc, n.startTick + n.durationTicks)),
      ).clamp(0, maxTicks - 1);
      final startTick = prState.selectedColumnTick ?? fallbackStart;

      prNotifier.addNoteStack(previewMidis, startTick, 4);
      prNotifier.selectColumn(startTick);

      // Centre pitch range on added notes
      final minM = previewMidis.reduce(min);
      final maxM = previewMidis.reduce(max);
      final midCenter = ((minM + maxM) / 2).round();
      final span = prState.pitchRangeEnd - prState.pitchRangeStart;
      final newStart = max(21, midCenter - span ~/ 2);
      final newEnd = min(108, newStart + span);
      prNotifier.setPitchRange(newStart, newEnd);

      HapticFeedback.mediumImpact();
      widget.onStackAdded?.call();
    }

    return Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        border: Border.all(color: MuzicianTheme.glassBorder, width: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Load from Saves',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),

          // ── Breadcrumb ──
          if (_currentFolderId != null) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() {
                      _currentFolderId = null;
                      _selectedSaveId = null;
                    }),
                    child: const Text('⌂',
                        style: TextStyle(
                            color: MuzicianTheme.sky,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  ...breadcrumb.asMap().entries.expand((e) => [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('›',
                              style: TextStyle(
                                  color: MuzicianTheme.textMuted, fontSize: 12)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _currentFolderId = e.value.id;
                            _selectedSaveId = null;
                          }),
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
                      ]),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Back button
            GestureDetector(
              onTap: () => setState(() {
                _currentFolderId = breadcrumb.length > 1
                    ? breadcrumb[breadcrumb.length - 2].id
                    : null;
                _selectedSaveId = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12), width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('← Back',
                    style: TextStyle(
                        color: MuzicianTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // ── List ──
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (_currentFolderId == null && subFolders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No folders yet. Create saves in the Fretboard or Piano tab first.',
                        style: TextStyle(
                            color: MuzicianTheme.textMuted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Folders
                  ...subFolders.map((folder) => GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentFolderId = folder.id;
                            _selectedSaveId = null;
                          });
                          HapticFeedback.selectionClick();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                folder.progressionMeta != null ? '🎼' : '📁',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  folder.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: MuzicianTheme.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              const Text('›',
                                  style: TextStyle(
                                      color: MuzicianTheme.textMuted,
                                      fontSize: 16)),
                            ],
                          ),
                        ),
                      )),
                  // Saves
                  if (_currentFolderId != null && rootSaves.isEmpty && subFolders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No saves in this folder.',
                          style: TextStyle(
                              color: MuzicianTheme.textMuted, fontSize: 12),
                          textAlign: TextAlign.center),
                    ),
                  ...rootSaves.map((save) {
                    final isSelected = _selectedSaveId == save.id;
                    final icon =
                        save.snapshot.instrument == 'piano' ? '🎹' : '🎸';
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedSaveId = isSelected ? null : save.id;
                        });
                        HapticFeedback.selectionClick();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? MuzicianTheme.sky.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(icon, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                save.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected
                                      ? MuzicianTheme.sky
                                      : MuzicianTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ── Selected save controls ──
          if (selectedSave != null) ...[
            Divider(
                color: MuzicianTheme.glassBorder, height: 16, thickness: 0.5),
            // Note preview
            Row(
              children: [
                const Text('Notes:',
                    style: TextStyle(
                        color: MuzicianTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: selectedSave.snapshot.selectedNotes.isNotEmpty
                          ? selectedSave.snapshot.selectedNotes
                              .map((note) => Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: MuzicianTheme.sky
                                          .withValues(alpha: 0.15),
                                      border: Border.all(
                                          color: MuzicianTheme.sky
                                              .withValues(alpha: 0.35),
                                          width: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(note,
                                        style: const TextStyle(
                                            color: MuzicianTheme.sky,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ))
                              .toList()
                          : [
                              const Text('No pitch classes saved.',
                                  style: TextStyle(
                                      color: MuzicianTheme.textMuted,
                                      fontSize: 12))
                            ],
                    ),
                  ),
                ),
              ],
            ),
            // Chord/scale context
            if (selectedSave.snapshot.pendingChord != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Chord: ${selectedSave.snapshot.pendingChord!.symbol}',
                  style: const TextStyle(
                      color: MuzicianTheme.violet,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            if (selectedSave.snapshot.pendingScale != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Scale: ${selectedSave.snapshot.pendingScale!.root} ${selectedSave.snapshot.pendingScale!.scaleName}',
                  style: const TextStyle(
                      color: MuzicianTheme.violet,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),

            const SizedBox(height: 8),

            // Placement mode toggle
            Row(
              children: [
                const Text('Placement:',
                    style: TextStyle(
                        color: MuzicianTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                _ModePill(
                  label: 'Exact MIDI',
                  active: _placementMode == 'exact',
                  onTap: () => setState(() => _placementMode = 'exact'),
                ),
                const SizedBox(width: 8),
                _ModePill(
                  label: 'Pitch Class',
                  active: _placementMode == 'pitch-class',
                  onTap: () => setState(() => _placementMode = 'pitch-class'),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // MIDI preview / warning
            if (previewMidis.isNotEmpty)
              Text(
                '${previewMidis.length} MIDI note${previewMidis.length != 1 ? 's' : ''} · MIDI [${previewMidis.join(', ')}]',
                style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              )
            else
              Text(
                _placementMode == 'exact'
                    ? 'No exact positions saved. Try Pitch Class mode.'
                    : 'No pitch classes could be mapped to the current range.',
                style: const TextStyle(
                    color: MuzicianTheme.orange, fontSize: 11),
              ),

            const SizedBox(height: 8),

            // Add Stack button
            GestureDetector(
              onTap: previewMidis.isNotEmpty ? handleAddStack : null,
              child: AnimatedOpacity(
                opacity: previewMidis.isNotEmpty ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MuzicianTheme.sky.withValues(alpha: 0.18),
                    border: Border.all(
                        color: MuzicianTheme.sky.withValues(alpha: 0.45),
                        width: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '＋ Add Stack${prState.selectedColumnTick != null ? ' at beat ${prState.selectedColumnTick! + 1}' : ''}',
                    style: const TextStyle(
                        color: MuzicianTheme.sky,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
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

// ── Mode Pill ───────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModePill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: active
                ? MuzicianTheme.sky
                : Colors.white.withValues(alpha: 0.14),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? MuzicianTheme.sky : MuzicianTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
