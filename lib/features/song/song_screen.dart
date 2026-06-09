library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart' show TimeSignature;
import '../../models/song_playback.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_rules.dart' as song_rules;
import '../../store/song_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../ui/project_chip.dart';
import '../../ui/transport_strip.dart' as transport;
import '../../models/save_system.dart';
import '../../store/save_system_store.dart';
import '../../ui/project_gate_modal.dart';
import '../../utils/note_utils.dart' as note_utils;
import '../_mockup_shell.dart' show showWidgetSheet, showPickerSheet;
import 'song_arranger_timeline.dart';
import 'song_clip_action_bar.dart';
import 'song_import_picker_sheet.dart';
import 'song_save_panel.dart';

class SongScreen extends ConsumerStatefulWidget {
  const SongScreen({super.key});

  @override
  ConsumerState<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends ConsumerState<SongScreen> {
  @override
  void initState() {
    super.initState();
    registerSongImportPicker();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedProjectProvider);
    if (selected == null || selected.kind == SaveFolderKind.dump) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ProjectGateModal.show(context, allowDump: false, allowCancel: false);
      });
    }

    final project = ref.watch(songProjectProvider);
    final playback = ref.watch(songPlaybackProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
          stops: [0, 0.3, 0.7, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Song',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: MuzicianTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          '${project.tracks.length} tracks',
                          style: const TextStyle(
                            fontSize: 14,
                            color: MuzicianTheme.textMuted,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Consumer(builder: (context, ref, _) {
                    final locked = ref.watch(isProjectLockedProvider);
                    return IgnorePointer(
                      ignoring: locked,
                      child: Opacity(
                        opacity: locked ? 0.5 : 1.0,
                        child: _SongScaleChip(config: project.config),
                      ),
                    );
                  }),
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: ProjectChip(),
                  ),
                  IconButton(
                    tooltip: 'New Song',
                    icon: const Icon(
                      Icons.note_add_outlined,
                      color: MuzicianTheme.sky,
                    ),
                    onPressed: () => _confirmNewSong(context),
                  ),
                  IconButton(
                    tooltip: 'Add Track',
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: MuzicianTheme.sky,
                    ),
                    onPressed: () => _showAddTrackSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Save / Load',
                    icon: const Icon(
                      Icons.save_outlined,
                      color: MuzicianTheme.sky,
                    ),
                    onPressed: () => _showSavePanel(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Shared transport strip
            _SongTransportStrip(project: project, playback: playback),
            const SizedBox(height: 4),
            // Arranger timeline
            Expanded(
              child: project.tracks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No tracks yet',
                            style: TextStyle(
                              color: MuzicianTheme.textMuted.withValues(
                                alpha: 0.6,
                              ),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _showAddTrackSheet(context),
                            icon: const Icon(
                              Icons.add,
                              color: MuzicianTheme.sky,
                            ),
                            label: const Text(
                              'Add Track',
                              style: TextStyle(color: MuzicianTheme.sky),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SongArrangerTimeline(
                      measureTicks: song_rules.songTicksPerMeasure(
                        project.config.timeSignature,
                      ),
                      currentPlaybackTick: playback.currentTick,
                    ),
            ),
            const SongClipActionBar(),
          ],
        ),
      ),
    );
  }

  void _showAddTrackSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Track',
                  style: TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.music_note,
                    color: MuzicianTheme.sky,
                  ),
                  title: const Text(
                    'Note Track',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Melody, chords, bass',
                    style: TextStyle(color: MuzicianTheme.textMuted),
                  ),
                  onTap: () {
                    ref
                        .read(songProjectProvider.notifier)
                        .addTrack(SongTrackType.note);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.album, color: MuzicianTheme.orange),
                  title: const Text(
                    'Drum Track',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Step sequencer',
                    style: TextStyle(color: MuzicianTheme.textMuted),
                  ),
                  onTap: () {
                    ref
                        .read(songProjectProvider.notifier)
                        .addTrack(SongTrackType.drum);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic, color: MuzicianTheme.teal),
                  title: const Text(
                    'Audio Track',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Record or import audio clips',
                    style: TextStyle(color: MuzicianTheme.textMuted),
                  ),
                  onTap: () {
                    ref
                        .read(songProjectProvider.notifier)
                        .addTrack(SongTrackType.audio);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSavePanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MuzicianTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SongSavePanel(),
      ),
    );
  }

  Future<void> _confirmNewSong(BuildContext context) async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text(
          'Start a new song?',
          style: TextStyle(color: MuzicianTheme.textPrimary),
        ),
        content: const Text(
          'This overwrites your current session. Save it first from the Save / '
          'Load panel if you want to keep it.',
          style: TextStyle(color: MuzicianTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('New Song'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(songPlaybackProvider.notifier).stopPlayback();
    await ref.read(songProjectProvider.notifier).loadProject(song_rules.getDefaultSongProject());
  }
}

class _SongTransportStrip extends ConsumerWidget {
  final SongProject project;
  final SongPlaybackState playback;

  const _SongTransportStrip({required this.project, required this.playback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = playback.status == SongPlaybackStatus.playing;
    final playbackNotifier = ref.read(songPlaybackProvider.notifier);
    final songNotifier = ref.read(songProjectProvider.notifier);
    final bpm = project.config.tempo;
    final timeSig = project.config.timeSignature;
    final barBeat = transport.tickToBarBeatDisplay(
      playback.currentTick,
      timeSig,
    );
    final timeSigLabel = '${timeSig.beatsPerMeasure}/${timeSig.beatUnit}';

    void onRewind() {
      HapticFeedback.selectionClick();
      playbackNotifier.seek(0);
    }

    void onStop() {
      HapticFeedback.lightImpact();
      playbackNotifier.stopPlayback();
    }

    void onPlayPause() {
      HapticFeedback.lightImpact();
      if (playing) {
        playbackNotifier.stopPlayback();
      } else {
        // Resume from a parked cursor (set by rewind or a ruler tap) when the
        // transport is idle; otherwise start from the top.
        final cursor = playback.status == SongPlaybackStatus.idle
            ? playback.currentTick
            : null;
        playbackNotifier.startPlayback(startTick: cursor);
      }
    }

    Future<void> onBpmTap() async {
      HapticFeedback.selectionClick();
      await showWidgetSheet(
        context: context,
        title: 'Tempo',
        child: Consumer(
          builder: (_, sheetRef, _) {
            final tempo = sheetRef.watch(
              songProjectProvider.select((s) => s.config.tempo),
            );
            return transport.BpmSheet(
              currentBpm: tempo,
              onChanged: (v) =>
                  sheetRef.read(songProjectProvider.notifier).setTempo(v),
            );
          },
        ),
      );
    }

    Future<void> onSigTap() async {
      HapticFeedback.selectionClick();
      final picked = await showPickerSheet<String>(
        context: context,
        title: 'Time Signature',
        options: transport.kTimeSignatureOptions,
        current: timeSigLabel,
      );
      if (picked == null) return;
      final parts = picked.split('/');
      songNotifier.setTimeSignature(
        TimeSignature(
          beatsPerMeasure: int.parse(parts[0]),
          beatUnit: int.parse(parts[1]),
        ),
      );
    }

    return transport.TransportStrip(
      bpm: bpm,
      barBeat: barBeat,
      timeSig: timeSig,
      playing: playing,
      onRewind: onRewind,
      onStop: onStop,
      onPlayPause: onPlayPause,
      onBpmTap: onBpmTap,
      onSigTap: onSigTap,
      onBpmDelta: (delta) => songNotifier.setTempo(bpm + delta),
    );
  }
}

// ── Song Scale Chip & Picker ─────────────────────────────────────────────────

class _SongScaleChip extends ConsumerWidget {
  final SongProjectConfig config;
  const _SongScaleChip({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = config.scaleRoot;
    final name = config.scaleName;
    final isSet = root != null && name != null;
    final label = isSet ? '$root ${_scaleLabel(name)}' : 'Set scale';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          showWidgetSheet(
            context: context,
            title: 'Song Scale',
            child: _SongScalePickerSheet(config: config),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSet
                ? MuzicianTheme.teal.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSet
                  ? MuzicianTheme.teal.withValues(alpha: 0.45)
                  : MuzicianTheme.glassBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.piano_rounded,
                size: 14,
                color: isSet ? MuzicianTheme.teal : MuzicianTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSet ? MuzicianTheme.teal : MuzicianTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _scaleLabel(String name) => note_utils.scaleGroups.values
    .expand((v) => v)
    .firstWhere((s) => s.$1 == name, orElse: () => (name, name))
    .$2;

class _SongScalePickerSheet extends ConsumerStatefulWidget {
  final SongProjectConfig config;
  const _SongScalePickerSheet({required this.config});

  @override
  ConsumerState<_SongScalePickerSheet> createState() =>
      _SongScalePickerSheetState();
}

class _SongScalePickerSheetState extends ConsumerState<_SongScalePickerSheet> {
  String? _selectedRoot;
  String? _selectedScale;
  note_utils.ScaleCategory _activeCategory = note_utils.ScaleCategory.common;

  @override
  void initState() {
    super.initState();
    _selectedRoot = widget.config.scaleRoot;
    _selectedScale = widget.config.scaleName;
    if (_selectedScale != null) {
      for (final entry in note_utils.scaleGroups.entries) {
        if (entry.value.any((s) => s.$1 == _selectedScale)) {
          _activeCategory = entry.key;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scalesForCategory =
        note_utils.scaleGroups[_activeCategory] ?? const [];
    final isActive = _selectedRoot != null && _selectedScale != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Inherited by every note pattern',
              style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 11),
            ),
            const Spacer(),
            if (isActive)
              TextButton(onPressed: _clearScale, child: const Text('Clear')),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: note_utils.chromaticNotes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final note = note_utils.chromaticNotes[i];
              final active = note == _selectedRoot;
              return GestureDetector(
                onTap: () => _onRootTap(note),
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minWidth: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: active
                        ? MuzicianTheme.sky.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.sky
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    note,
                    style: TextStyle(
                      color: active
                          ? MuzicianTheme.sky
                          : const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: note_utils.ScaleCategory.values.map((cat) {
            final isTab = cat == _activeCategory;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeCategory = cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isTab ? MuzicianTheme.sky : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      note_utils.scaleCategoryLabels[cat]!,
                      style: TextStyle(
                        color: isTab
                            ? MuzicianTheme.sky
                            : const Color(0xFF475569),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: scalesForCategory.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final (name, label) = scalesForCategory[i];
              final active = name == _selectedScale;
              return GestureDetector(
                onTap: () => _onScaleTap(name),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: active
                        ? MuzicianTheme.sky.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.sky
                          : Colors.white.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: active
                          ? MuzicianTheme.sky
                          : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onRootTap(String root) {
    HapticFeedback.lightImpact();
    final newRoot = root == _selectedRoot ? null : root;
    if (newRoot == null) {
      _clearScale();
      return;
    }
    if (_selectedScale != null) {
      _applyScale(newRoot, _selectedScale!);
    } else {
      setState(() => _selectedRoot = newRoot);
    }
  }

  void _onScaleTap(String scale) {
    HapticFeedback.lightImpact();
    final newScale = scale == _selectedScale ? null : scale;
    if (newScale == null) {
      _clearScale();
      return;
    }
    if (_selectedRoot != null) {
      _applyScale(_selectedRoot!, newScale);
    } else {
      setState(() => _selectedScale = newScale);
    }
  }

  void _clearScale() {
    setState(() {
      _selectedRoot = null;
      _selectedScale = null;
    });
    ref.read(songProjectProvider.notifier).setScale();
  }

  Future<void> _applyScale(String root, String scaleName) async {
    final scaleNotes = note_utils.getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final scaleSet = scaleNotes.toSet();
    final project = ref.read(songProjectProvider);
    final conflicts = <String>{
      for (final pattern in project.notePatterns)
        for (final n in pattern.notes) _midiToPitchClass(n.midiNote),
    }.where((pc) => !scaleSet.contains(pc)).toList();

    if (conflicts.isEmpty) {
      _commitScale(root, scaleName);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(conflictingNotes: conflicts),
    );
    if (confirmed != true) return;
    ref
        .read(songProjectProvider.notifier)
        .removeNotesByPitchClassAcrossPatterns(conflicts);
    _commitScale(root, scaleName);
  }

  void _commitScale(String root, String scaleName) {
    setState(() {
      _selectedRoot = root;
      _selectedScale = scaleName;
    });
    ref
        .read(songProjectProvider.notifier)
        .setScale(root: root, scaleName: scaleName);
  }
}

const _kPitchClasses = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

String _midiToPitchClass(int midi) => _kPitchClasses[midi % 12];
