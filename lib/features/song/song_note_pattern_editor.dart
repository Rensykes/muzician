/// SongNotePatternEditor – isolated piano-roll editor host for a NotePattern.
///
/// Creates an isolated [ProviderContainer] seeded from the pattern so that edits
/// never leak into the standalone Piano Roll screen.  On save the edited state
/// is converted back to a [NotePattern] and applied via [songProjectProvider].
///
/// The editor mounts the full [PianoRollScreenV2] shell (stack builder,
/// detection, hum recorder, transport, tools, snap, pitch range), but hides the
/// per-pattern scale picker — the scale is inherited from the song.  Save/Load
/// panels are also hidden because loading would smash the host pattern length.
library;

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart';
import '../../models/song_playback.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_pattern_bridge_rules.dart' as bridge;
import '../../store/piano_roll_playback_store.dart';
import '../../store/piano_roll_store.dart';
import '../../store/song_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/glass_snackbar.dart';
import '../../utils/note_utils.dart';
import '../piano_roll/piano_roll_screen_v2.dart';

class _SeededPianoRollNotifier extends PianoRollNotifier {
  _SeededPianoRollNotifier(this.seedState);
  final PianoRollState seedState;

  @override
  PianoRollState build() => seedState;
}

class SongNotePatternEditor extends ConsumerStatefulWidget {
  final String clipId;
  final String patternId;

  const SongNotePatternEditor({
    super.key,
    required this.clipId,
    required this.patternId,
  });

  @override
  ConsumerState<SongNotePatternEditor> createState() =>
      _SongNotePatternEditorState();
}

class _SongNotePatternEditorState extends ConsumerState<SongNotePatternEditor> {
  ProviderContainer? _isolatedContainer;
  String _patternName = '';

  /// When false (default) the editor's transport plays only this pattern in
  /// isolation (SOLO).  When true, playback is delegated to the song transport
  /// so the pattern is heard together with the rest of the arrangement, started
  /// at the opened clip instance's slot.
  bool _songContext = false;

  /// Snapshot of the pattern's per-pattern `highlightedNotes` taken at open
  /// time.  Preserved through save so the pattern keeps its own fallback when
  /// the song scale is cleared later.
  List<String> _patternHighlightFallback = const [];

  @override
  void dispose() {
    // Stop any song-context playback this editor started so it does not keep
    // running after the editor is dismissed.  Guarded: in widget tests the
    // enclosing ProviderScope container can be torn down before this widget
    // unmounts, which makes `ref` unusable.
    if (_songContext) {
      try {
        ref.read(songPlaybackProvider.notifier).stopPlayback();
      } catch (_) {
        // Provider container already disposed — nothing left to stop.
      }
    }
    _isolatedContainer?.dispose();
    super.dispose();
  }

  PianoRollPlaybackNotifier? get _soloPlayback =>
      _isolatedContainer?.read(pianoRollPlaybackProvider.notifier);

  void _setSongContext(bool songContext) {
    if (_songContext == songContext) return;
    // Tear down whichever transport was active before switching modes.
    if (songContext) {
      _soloPlayback?.stopPlayback();
    } else {
      ref.read(songPlaybackProvider.notifier).stopPlayback();
      _soloPlayback?.mirrorExternalTick(null);
    }
    setState(() => _songContext = songContext);
  }

  void _toggleSongPlayback(int clipStartTick) {
    final notifier = ref.read(songPlaybackProvider.notifier);
    final status = ref.read(songPlaybackProvider).status;
    if (status == SongPlaybackStatus.playing) {
      notifier.stopPlayback();
      _soloPlayback?.mirrorExternalTick(null);
    } else {
      notifier.startPlayback(startTick: clipStartTick);
    }
  }

  void _ensureIsolatedContainer(NotePattern pattern, SongProject project) {
    if (_isolatedContainer != null) return;

    _patternName = pattern.name;
    _patternHighlightFallback = List<String>.from(pattern.highlightedNotes);

    final scale = _songScaleFromConfig(project.config);

    final seedState = bridge.pianoRollStateFromNotePattern(
      pattern,
      tempo: project.config.tempo,
      timeSignature: project.config.timeSignature,
      songHighlightedNotes: scale?.notes,
      songKey: scale?.label,
    );

    _isolatedContainer = ProviderContainer(
      overrides: [
        pianoRollProvider.overrideWith(
          () => _SeededPianoRollNotifier(seedState),
        ),
      ],
    );
  }

  void _onSave() {
    final pianoRollState = _isolatedContainer!.read(pianoRollProvider);
    final project = ref.read(songProjectProvider);
    final currentPattern = project.notePatterns.firstWhere(
      (p) => p.id == widget.patternId,
    );
    final hasSongScale =
        project.config.scaleRoot != null && project.config.scaleName != null;
    final nextPattern = bridge.notePatternFromPianoRollState(
      pianoRollState,
      patternId: widget.patternId,
      patternName: _patternName,
      minimumLengthTicks: currentPattern.lengthTicks,
      highlightedNotesOverride: hasSongScale ? _patternHighlightFallback : null,
    );
    final applied = ref
        .read(songProjectProvider.notifier)
        .applyNotePattern(widget.patternId, nextPattern);
    if (!applied) {
      showGlassSnackbar(
        context,
        title: 'Resize rejected',
        message:
            'Pattern resize rejected because it would overlap another clip.',
        contentType: ContentType.warning,
      );
      return;
    }
    Navigator.pop(context);
  }

  void _onMakeUnique() {
    ref.read(songProjectProvider.notifier).makeClipPatternUnique(widget.clipId);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songProjectProvider);

    NotePattern pattern;
    SongClipInstance clip;
    try {
      clip = project.clips.firstWhere((c) => c.id == widget.clipId);
      pattern = project.notePatterns.firstWhere(
        (p) => p.id == widget.patternId,
      );
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    _ensureIsolatedContainer(pattern, project);

    final clipStartTick = clip.startTick;
    final patternLength = pattern.lengthTicks;

    // In song context, mirror the song transport's position into the embedded
    // grid's playhead (mapped to pattern-local ticks). The song transport is
    // what actually produces the audio.
    ref.listen<SongPlaybackState>(songPlaybackProvider, (_, next) {
      if (!_songContext) return;
      final solo = _soloPlayback;
      if (solo == null) return;
      if (next.status == SongPlaybackStatus.playing &&
          next.currentTick != null) {
        final local = next.currentTick! - clipStartTick;
        solo.mirrorExternalTick(
          local >= 0 && local < patternLength ? local : null,
        );
      } else {
        solo.mirrorExternalTick(null);
      }
    });

    final songPlaying =
        ref.watch(songPlaybackProvider).status == SongPlaybackStatus.playing;

    final usageCount = project.clips
        .where((c) => c.patternId == widget.patternId)
        .length;

    final songScale = _songScaleFromConfig(project.config);
    final scaleLabel = songScale?.label ?? 'No song scale';

    return Scaffold(
      backgroundColor: MuzicianTheme.surface,
      appBar: AppBar(
        backgroundColor: MuzicianTheme.surface,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _patternName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            Text(
              scaleLabel,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _onMakeUnique,
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Make unique'),
            style: TextButton.styleFrom(
              foregroundColor: MuzicianTheme.textSecondary,
            ),
          ),
          TextButton.icon(
            onPressed: _onSave,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Save'),
            style: TextButton.styleFrom(foregroundColor: MuzicianTheme.sky),
          ),
          const SizedBox(width: 8),
        ],
        // Playback controls + usage live on a dedicated sub-bar so the action
        // row never overflows on narrow widths.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                _PlaybackModeToggle(
                  songContext: _songContext,
                  onChanged: _setSongContext,
                ),
                if (_songContext) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: songPlaying ? 'Stop' : 'Play in song',
                    icon: Icon(songPlaying ? Icons.stop : Icons.play_arrow),
                    color: MuzicianTheme.sky,
                    onPressed: () => _toggleSongPlayback(clipStartTick),
                  ),
                ],
                const Spacer(),
                Text(
                  'Used in $usageCount clips',
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: UncontrolledProviderScope(
        container: _isolatedContainer!,
        child: const PianoRollScreenV2(
          showScale: false,
          showSavePanels: false,
          showBackground: false,
        ),
      ),
    );
  }
}

/// Compact SOLO / SONG segmented toggle shown in the editor app bar.
///
/// SOLO plays only the edited pattern (via the embedded transport); SONG hands
/// playback to the song transport so the pattern is heard in arrangement
/// context, positioned at the opened clip instance's slot.
class _PlaybackModeToggle extends StatelessWidget {
  final bool songContext;
  final ValueChanged<bool> onChanged;

  const _PlaybackModeToggle({
    required this.songContext,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, bool value) {
      final active = songContext == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? MuzicianTheme.sky : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: active
                  ? MuzicianTheme.surface
                  : MuzicianTheme.textSecondary,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [pill('SOLO', false), pill('SONG', true)],
      ),
    );
  }
}

/// Compact view-model derived from [SongProjectConfig.scaleRoot] /
/// [SongProjectConfig.scaleName].  Returns `null` when the song has no scale.
({String label, List<String> notes})? _songScaleFromConfig(
  SongProjectConfig config,
) {
  final root = config.scaleRoot;
  final name = config.scaleName;
  if (root == null || name == null) return null;
  final notes = getScaleNotes(root, name);
  if (notes.isEmpty) return null;
  final scaleLabel = scaleGroups.values
      .expand((v) => v)
      .firstWhere((s) => s.$1 == name, orElse: () => (name, name))
      .$2;
  return (label: '$root $scaleLabel', notes: notes);
}
