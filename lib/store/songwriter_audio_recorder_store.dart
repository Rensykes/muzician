/// Project-agnostic count-in -> record -> ready state machine for the Songwriter
/// audio lane. Owns no project state: the caller commits the recorded asset.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart' show AudioAsset;
import '../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../schema/rules/songwriter_audio_rules.dart'
    show SongwriterScheduledClip;
import '../schema/rules/songwriter_playback_rules.dart'
    show SongwriterAuditionBed;
import '../utils/note_player.dart';
import '../utils/tick_pacer.dart';
import 'drum_pattern_playback_store.dart';
import 'song_audio_recorder_store.dart'
    show SongAudioRecorderStatus, songAudioRecorderDriverProvider;
import 'song_audio_repository.dart';
import 'songwriter_audio_sink.dart';
import 'songwriter_playback_store.dart';

/// Plain-data descriptor for record-time monitoring. Built by the caller from
/// project state and passed into [SongwriterAudioRecorderNotifier.start]; the
/// store reads no project state itself. [bed]/[clips] are ignored when
/// [backing] is false (only the metronome fires).
class SongwriterRecordMonitor {
  final bool backing;
  final bool metronome;
  final int tempo;
  final int beatTicks; // ticksPerBeat
  final int measureTicks; // ticksPerBeat * beatsPerBar
  final int loopTicks; // section length in ticks (wraps the loop)
  final int loopMs; // section length in ms (positions clips)
  final SongwriterAuditionBed bed;
  final List<SongwriterScheduledClip> clips;
  const SongwriterRecordMonitor({
    required this.backing,
    required this.metronome,
    required this.tempo,
    required this.beatTicks,
    required this.measureTicks,
    required this.loopTicks,
    required this.loopMs,
    required this.bed,
    required this.clips,
  });

  SongwriterRecordMonitor copyWith({bool? backing, bool? metronome}) =>
      SongwriterRecordMonitor(
        backing: backing ?? this.backing,
        metronome: metronome ?? this.metronome,
        tempo: tempo,
        beatTicks: beatTicks,
        measureTicks: measureTicks,
        loopTicks: loopTicks,
        loopMs: loopMs,
        bed: bed,
        clips: clips,
      );
}

class SongwriterAudioRecorderState {
  final SongAudioRecorderStatus status;
  final AudioAsset? pendingAsset;
  final String? errorMessage;
  const SongwriterAudioRecorderState({
    this.status = SongAudioRecorderStatus.idle,
    this.pendingAsset,
    this.errorMessage,
  });
  SongwriterAudioRecorderState copyWith({
    SongAudioRecorderStatus? status,
    AudioAsset? Function()? pendingAsset,
    String? Function()? errorMessage,
  }) => SongwriterAudioRecorderState(
    status: status ?? this.status,
    pendingAsset: pendingAsset != null ? pendingAsset() : this.pendingAsset,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

class SongwriterAudioRecorderNotifier
    extends Notifier<SongwriterAudioRecorderState> {
  bool _cancelled = false;
  int _monitorGen = 0;

  @override
  SongwriterAudioRecorderState build() => const SongwriterAudioRecorderState();

  Future<void> start({
    int countInMs = 0,
    int countInBeats = 4,
    SongwriterRecordMonitor? monitor,
  }) async {
    final st = state.status;
    if (st != SongAudioRecorderStatus.idle &&
        st != SongAudioRecorderStatus.error) {
      return;
    }
    _cancelled = false;
    final driver = ref.read(songAudioRecorderDriverProvider);
    if (!await driver.ensurePermission()) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Microphone permission denied',
      );
      return;
    }
    state = const SongwriterAudioRecorderState(
      status: SongAudioRecorderStatus.countIn,
    );
    if (countInMs > 0 && countInBeats > 0) {
      final beat = Duration(milliseconds: (countInMs / countInBeats).round());
      for (var i = 0; i < countInBeats; i++) {
        if (state.status != SongAudioRecorderStatus.countIn) return;
        NotePlayer.instance.playClick(accent: i == 0);
        await Future<void>.delayed(beat);
      }
    }
    if (state.status != SongAudioRecorderStatus.countIn) return;
    state = state.copyWith(status: SongAudioRecorderStatus.recording);
    await driver.start();
    if (monitor != null && (monitor.backing || monitor.metronome)) {
      unawaited(_runMonitor(++_monitorGen, monitor));
    }
  }

  /// Section-looped backing + metronome under the live recording. Mirrors the
  /// audition transport: a [TickPacer] anchors ticks; bed notes/drums fire by
  /// section-local tick; section audio clips fire by section-local ms and
  /// re-arm each loop pass. Cancelled when [_monitorGen] moves past [gen]
  /// (stop/cancel).
  Future<void> _runMonitor(int gen, SongwriterRecordMonitor m) async {
    final clipSink = ref.read(songwriterAudioClipSinkProvider);
    final noteSink = ref.read(songwriterNoteSinkProvider);
    final drumSink = ref.read(drumPatternPlaybackSinkProvider);
    final metroSink = ref.read(songwriterMetronomeSinkProvider);

    if (m.backing && m.clips.isNotEmpty) {
      await clipSink.prepare(m.clips.map((c) => c.asset));
      if (_monitorGen != gen) return; // stop during prepare
    }

    final loopTicks = m.loopTicks > 0 ? m.loopTicks : m.measureTicks;
    final pacer = TickPacer(pr_rules.tickDuration(m.tempo));
    final pendingStops = <(AudioAsset, int)>[];
    var tick = 0;
    var elapsed = 0;
    var nextClip = 0;

    void fireClips(int nowMs) {
      while (nextClip < m.clips.length && m.clips[nextClip].startMs <= nowMs) {
        final clip = m.clips[nextClip++];
        unawaited(
          clipSink.startClip(
            asset: clip.asset,
            offsetMs: clip
                .offsetIntoAsset(nowMs)
                .clamp(0, clip.asset.durationMs),
            volume: clip.volume,
            loop: clip.loop,
          ),
        );
        pendingStops.add((clip.asset, clip.endMs));
      }
      pendingStops.removeWhere((p) {
        if (p.$2 <= nowMs) {
          unawaited(clipSink.stopClip(asset: p.$1));
          return true;
        }
        return false;
      });
    }

    while (_monitorGen == gen) {
      if (m.metronome && tick % m.beatTicks == 0) {
        unawaited(metroSink(accent: tick % m.measureTicks == 0));
      }
      if (m.backing) {
        final notes = m.bed.notesByTick[tick];
        if (notes != null && notes.isNotEmpty) noteSink(notes);
        final drums = m.bed.drumByTick[tick];
        if (drums != null && drums.isNotEmpty) unawaited(drumSink(drums, 0.8));
        if (m.clips.isNotEmpty) {
          fireClips((tick * m.loopMs / loopTicks).round());
        }
      }
      await pacer.awaitBoundary(++elapsed);
      if (_monitorGen != gen) break;
      final prev = tick;
      tick = (tick + 1) % loopTicks;
      if (tick <= prev) {
        // Loop wrapped: re-arm clips for the next pass.
        nextClip = 0;
        for (final p in pendingStops) {
          unawaited(clipSink.stopClip(asset: p.$1));
        }
        pendingStops.clear();
      }
    }
  }

  void _stopMonitor() {
    _monitorGen++;
    unawaited(ref.read(songwriterAudioClipSinkProvider).stopAll());
  }

  Future<void> stop() async {
    if (state.status != SongAudioRecorderStatus.recording) return;
    state = state.copyWith(status: SongAudioRecorderStatus.finalising);
    _stopMonitor();
    final driver = ref.read(songAudioRecorderDriverProvider);
    try {
      final bytes = await driver.stop();
      final asset = await ref
          .read(songwriterAudioRepositoryProvider)
          .writeRecording(bytes);
      if (_cancelled) {
        try {
          await ref.read(songwriterAudioRepositoryProvider).delete(asset.id);
        } catch (_) {}
        state = const SongwriterAudioRecorderState();
        return;
      }
      state = state.copyWith(
        status: SongAudioRecorderStatus.ready,
        pendingAsset: () => asset,
      );
    } catch (e) {
      state = state.copyWith(
        status: SongAudioRecorderStatus.error,
        errorMessage: () => 'Recording failed: $e',
      );
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _stopMonitor();
    if (state.status == SongAudioRecorderStatus.idle) return;
    if (state.status == SongAudioRecorderStatus.recording) {
      try {
        await ref.read(songAudioRecorderDriverProvider).stop();
      } catch (_) {}
    }
    final asset = state.pendingAsset;
    if (asset != null) {
      try {
        await ref.read(songwriterAudioRepositoryProvider).delete(asset.id);
      } catch (_) {}
    }
    state = const SongwriterAudioRecorderState();
  }

  AudioAsset? consumePendingAsset() {
    final asset = state.pendingAsset;
    state = const SongwriterAudioRecorderState();
    return asset;
  }
}

final songwriterAudioRecorderProvider =
    NotifierProvider<
      SongwriterAudioRecorderNotifier,
      SongwriterAudioRecorderState
    >(SongwriterAudioRecorderNotifier.new);
