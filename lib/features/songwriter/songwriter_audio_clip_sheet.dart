import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_playback_rules.dart';
import '../../schema/rules/songwriter_segment_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_audio_audition_store.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../store/songwriter_stretch_controller.dart';
import '../../theme/muzician_theme.dart';
import '../song/song_audio_clip_body.dart';
import '../_mockup_shell.dart' show showWidgetSheet;
import 'harmony_chord_sheet.dart';
import 'songwriter_audio_lane_row.dart' show fitGlyph;

Future<void> showSongwriterAudioClipSheet({
  required BuildContext context,
  required String sectionId,
  required String laneId,
  required String clipId,
}) => showWidgetSheet(
  context: context,
  title: 'Audio Clip',
  child: SongwriterAudioClipBody(
    sectionId: sectionId,
    laneId: laneId,
    clipId: clipId,
  ),
);

class SongwriterAudioClipBody extends ConsumerStatefulWidget {
  const SongwriterAudioClipBody({
    super.key,
    required this.sectionId,
    required this.laneId,
    required this.clipId,
  });
  final String sectionId;
  final String laneId;
  final String clipId;

  @override
  ConsumerState<SongwriterAudioClipBody> createState() =>
      _SongwriterAudioClipBodyState();
}

class _SongwriterAudioClipBodyState
    extends ConsumerState<SongwriterAudioClipBody> {
  @override
  void dispose() {
    // Stop the audition loop so it does not keep playing after the sheet pops.
    // Guarded: in widget tests the enclosing ProviderScope container can be
    // torn down before this widget unmounts, which makes `ref` unusable.
    try {
      ref.read(songwriterAudioAuditionProvider.notifier).stop();
    } catch (_) {
      // Provider container already disposed — nothing left to stop.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionId = widget.sectionId;
    final laneId = widget.laneId;
    final clipId = widget.clipId;

    final project = ref.watch(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return const SizedBox.shrink();
    final asset = project.audioAssets
        .where((a) => a.id == clip.assetId)
        .firstOrNull;
    final section = project.sections
        .where((s) => s.id == sectionId)
        .firstOrNull;
    final block = section?.lanes
        .where((l) => l.id == laneId)
        .expand((l) => l.blocks)
        .where((b) => b.audioClipId == clipId)
        .firstOrNull;
    if (asset == null || section == null || block == null) {
      return const SizedBox.shrink();
    }
    final store = ref.read(songwriterProvider.notifier);
    final maxSpan = section.lengthBars <= 1 ? 1 : section.lengthBars - 1;

    void rerenderIfStretch() {
      final cur = ref
          .read(songwriterProvider)
          .audioClips
          .where((c) => c.id == clipId)
          .firstOrNull;
      if (cur != null && cur.fitMode == AudioFitMode.stretch) {
        ref.read(songwriterStretchControllerProvider).rerender(clipId);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 80,
            child: _TrimWaveform(
              asset: asset,
              clip: clip,
              onTrim: (startMs, endMs) {
                store.setClipTrim(
                  clipId: clipId,
                  trimStartMs: startMs,
                  trimEndMs: endMs,
                );
                rerenderIfStretch();
              },
            ),
          ),
          const SizedBox(height: 8),
          _SegmentRow(
            clipId: clipId,
            segments: clip.segments,
            spanBars: block.spanBars,
            config: project.config,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final mode in AudioFitMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ChoiceChip(
                    key: Key('clipFit_${mode.name}'),
                    avatar: Icon(fitGlyph(mode), size: 16),
                    label: Text(mode.name),
                    selected: clip.fitMode == mode,
                    onSelected: (_) {
                      store.setClipFitMode(clipId: clipId, fitMode: mode);
                      if (mode == AudioFitMode.stretch) {
                        ref
                            .read(songwriterStretchControllerProvider)
                            .rerender(clipId);
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('clipSpanMinus'),
                icon: const Icon(Icons.remove),
                onPressed: () {
                  final newSpan = (block.spanBars - 1).clamp(1, maxSpan);
                  store.setBlockPlacement(
                    sectionId: sectionId,
                    laneId: laneId,
                    blockId: block.id,
                    startBar: block.startBar,
                    spanBars: newSpan,
                  );
                  store.clampClipSegments(
                    clipId: clipId,
                    spanTotalTicks: clipSpanTicks(newSpan, project.config),
                  );
                  rerenderIfStretch();
                },
              ),
              Text(
                '${block.spanBars} bar(s)',
                style: const TextStyle(color: MuzicianTheme.textPrimary),
              ),
              IconButton(
                key: const ValueKey('clipSpanPlus'),
                icon: const Icon(Icons.add),
                onPressed: () {
                  final newSpan = (block.spanBars + 1).clamp(1, maxSpan);
                  store.setBlockPlacement(
                    sectionId: sectionId,
                    laneId: laneId,
                    blockId: block.id,
                    startBar: block.startBar,
                    spanBars: newSpan,
                  );
                  store.clampClipSegments(
                    clipId: clipId,
                    spanTotalTicks: clipSpanTicks(newSpan, project.config),
                  );
                  rerenderIfStretch();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AuditionRow(
            asset: asset,
            trimStartMs: clip.trimStartMs,
            trimEndMs: clip.trimEndMs,
            tempo: project.config.tempo,
            bed: () => sectionAuditionBed(
              section,
              project.config,
              ref.read(saveSystemProvider).saves,
              drumPatterns: project.drumPatterns,
            ),
          ),
          if (ref.watch(songwriterStretchProcessingProvider).contains(clipId))
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Stretching…',
                    style: TextStyle(color: MuzicianTheme.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrimWaveform extends StatefulWidget {
  const _TrimWaveform({
    required this.asset,
    required this.clip,
    required this.onTrim,
  });
  final AudioAsset asset;
  final AudioClip clip;
  final void Function(int startMs, int endMs) onTrim;
  @override
  State<_TrimWaveform> createState() => _TrimWaveformState();
}

class _TrimWaveformState extends State<_TrimWaveform> {
  late double _start = widget.asset.durationMs == 0
      ? 0.0
      : widget.clip.trimStartMs / widget.asset.durationMs;
  late double _end = widget.asset.durationMs == 0
      ? 1.0
      : (widget.clip.trimEndMs == 0
                ? widget.asset.durationMs
                : widget.clip.trimEndMs) /
            widget.asset.durationMs;

  void _commit() => widget.onTrim(
    (_start * widget.asset.durationMs).round(),
    (_end * widget.asset.durationMs).round(),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: AudioClipBody(
                name: widget.asset.sourceLabel,
                durationMs: widget.asset.durationMs,
                format: widget.asset.format,
                peaks: widget.asset.peaks,
                isBroken: false,
              ),
            ),
            _handle(w, _start, const Key('clipTrimStart'), (nx) {
              setState(() => _start = nx.clamp(0.0, _end - 0.02));
            }),
            _handle(w, _end, const Key('clipTrimEnd'), (nx) {
              setState(() => _end = nx.clamp(_start + 0.02, 1.0));
            }),
          ],
        );
      },
    );
  }

  Widget _handle(
    double w,
    double frac,
    Key key,
    void Function(double nx) onMove,
  ) {
    return Positioned(
      left: (frac * w - 8).clamp(0.0, w - 16),
      top: 0,
      bottom: 0,
      child: GestureDetector(
        key: key,
        onHorizontalDragUpdate: (d) => onMove(((frac * w) + d.delta.dx) / w),
        onHorizontalDragEnd: (_) => _commit(),
        child: Container(
          width: 16,
          alignment: Alignment.center,
          child: Container(width: 3, color: MuzicianTheme.sky),
        ),
      ),
    );
  }
}

/// A beat grid laid over the clip. Each beat cell shows the covering chord
/// segment (symbol + Roman numeral) or is empty-and-tappable. Tapping an empty
/// cell opens the harmony picker and adds a segment; tapping a filled cell
/// removes it. Silent annotations only — no synth.
class _SegmentRow extends ConsumerWidget {
  const _SegmentRow({
    required this.clipId,
    required this.segments,
    required this.spanBars,
    required this.config,
  });
  final String clipId;
  final List<ChordSegment> segments;
  final int spanBars;
  final SongwriterConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final beats = spanBars * config.beatsPerBar;
    final tpb = config.ticksPerBeat;
    final store = ref.read(songwriterProvider.notifier);
    return Row(
      children: [
        for (var beat = 0; beat < beats; beat++)
          Expanded(
            child: GestureDetector(
              key: Key('segBeat_$beat'),
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final tick = beat * tpb;
                final existing = segmentAtTick(segments, tick);
                if (existing != null) {
                  store.removeChordSegment(
                    clipId: clipId,
                    segmentId: existing.id,
                  );
                  return;
                }
                await _addAt(context, store, tick);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: 34,
                decoration: BoxDecoration(
                  color: segmentAtTick(segments, beat * tpb) != null
                      ? MuzicianTheme.sky.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.03),
                  border: Border.all(color: MuzicianTheme.glassBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: _label(segmentAtTick(segments, beat * tpb)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _label(ChordSegment? seg) {
    if (seg == null) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          seg.chordSymbol ?? '◆',
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (seg.romanNumeral != null)
          Text(
            seg.romanNumeral!,
            style: const TextStyle(color: MuzicianTheme.textMuted, fontSize: 9),
          ),
      ],
    );
  }

  /// Lets the user mark a beat with a harmony chord OR a save reference.
  Future<void> _addAt(
    BuildContext context,
    SongwriterNotifier store,
    int tick,
  ) async {
    final tpb = config.ticksPerBeat;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('segAddChord'),
              leading: const Icon(
                Icons.piano,
                color: MuzicianTheme.textPrimary,
              ),
              title: const Text(
                'Chord',
                style: TextStyle(color: MuzicianTheme.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'chord'),
            ),
            ListTile(
              key: const ValueKey('segAddSave'),
              leading: const Icon(
                Icons.library_music_outlined,
                color: MuzicianTheme.textPrimary,
              ),
              title: const Text(
                'From a save',
                style: TextStyle(color: MuzicianTheme.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'chord') {
      if (!context.mounted) return;
      final picked = await showHarmonyChordSheet(
        context,
        startBar: 0,
        spanBars: 1,
        keyRoot: config.keyRoot,
        keyScaleName: config.keyScaleName,
      );
      if (picked == null || picked.isSilent) return;
      store.addChordSegment(
        clipId: clipId,
        startTick: tick,
        spanTicks: tpb,
        chordSymbol: picked.chordSymbol,
        chordQuality: picked.chordQuality,
        chordRootPc: picked.chordRootPc,
        chordNotes: picked.chordNotes,
        romanNumeral: picked.romanNumeral,
      );
    } else if (choice == 'save') {
      if (!context.mounted) return;
      final saveId = await _pickSave(context, store);
      if (saveId == null) return;
      store.addChordSegment(
        clipId: clipId,
        startTick: tick,
        spanTicks: tpb,
        saveId: saveId,
      );
    }
  }

  Future<String?> _pickSave(BuildContext context, SongwriterNotifier store) {
    final saves = store.searchableSavesForLibraryMatch();
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      builder: (ctx) => SafeArea(
        child: saves.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saves in this project',
                  style: TextStyle(color: MuzicianTheme.textSecondary),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in saves)
                    ListTile(
                      key: Key('segSavePick_${s.id}'),
                      title: Text(
                        s.name,
                        style: const TextStyle(
                          color: MuzicianTheme.textPrimary,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, s.id),
                    ),
                ],
              ),
      ),
    );
  }
}

class _AuditionRow extends ConsumerWidget {
  const _AuditionRow({
    required this.asset,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.tempo,
    required this.bed,
  });
  final AudioAsset asset;
  final int trimStartMs;
  final int trimEndMs;
  final int tempo;
  final SongwriterAuditionBed Function() bed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only (status, mode): currentTick changes every tick during
    // with-section playback, and rebuilding the row per tick would re-run the
    // bed() flatten needlessly.
    final (status, mode) = ref.watch(
      songwriterAudioAuditionProvider.select((s) => (s.status, s.mode)),
    );
    final n = ref.read(songwriterAudioAuditionProvider.notifier);
    final playing = status == SongwriterAudioAuditionStatus.playing;
    final computed = bed();
    final hasBed =
        computed.notesByTick.isNotEmpty || computed.drumByTick.isNotEmpty;

    Future<void> startWith(SongwriterAudioAuditionMode auditionMode) async {
      // One owner of the audio sink: stop the project transport first.
      ref.read(songwriterPlaybackProvider.notifier).stopPlayback();
      n.stop();
      await n.start(
        asset: asset,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
        tempo: tempo,
        mode: auditionMode,
        bed: auditionMode == SongwriterAudioAuditionMode.withSection
            ? computed
            : null,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('clipAuditionPlay'),
          icon: Icon(playing ? Icons.stop : Icons.play_arrow),
          onPressed: () => playing ? n.stop() : startWith(mode),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          key: const ValueKey('clipAuditionAlone'),
          label: const Text('Alone'),
          selected: mode == SongwriterAudioAuditionMode.alone,
          onSelected: (_) => playing
              ? startWith(SongwriterAudioAuditionMode.alone)
              : n.setMode(SongwriterAudioAuditionMode.alone),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          key: const ValueKey('clipAuditionWithSection'),
          label: const Text('With section'),
          selected: mode == SongwriterAudioAuditionMode.withSection,
          onSelected: hasBed
              ? (_) => playing
                  ? startWith(SongwriterAudioAuditionMode.withSection)
                  : n.setMode(SongwriterAudioAuditionMode.withSection)
              : null,
        ),
      ],
    );
  }
}
