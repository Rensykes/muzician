/// Dedicated looping audition transport for a single Songwriter audio clip.
/// Mirrors [DrumPatternPlaybackNotifier]: an injected sink per voice, a
/// [TickPacer] anchoring ticks to the wall clock, and a version counter that
/// cancels the loop. Alone mode loops the recording only; with-section mode
/// also loops the section bed under it. See
/// docs/superpowers/specs/2026-06-27-songwriter-audio-clip-audition-design.md
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_project.dart';
import '../schema/rules/piano_roll_playback_rules.dart' as rules;
import '../schema/rules/songwriter_playback_rules.dart'
    show SongwriterAuditionBed;
import '../utils/tick_pacer.dart';
import 'drum_pattern_playback_store.dart';
import 'songwriter_audio_sink.dart';
import 'songwriter_playback_store.dart';

enum SongwriterAudioAuditionMode { alone, withSection }

enum SongwriterAudioAuditionStatus { idle, playing }

class SongwriterAudioAuditionState {
  final SongwriterAudioAuditionStatus status;
  final SongwriterAudioAuditionMode mode;
  final int? currentTick;
  const SongwriterAudioAuditionState({
    this.status = SongwriterAudioAuditionStatus.idle,
    this.mode = SongwriterAudioAuditionMode.alone,
    this.currentTick,
  });

  SongwriterAudioAuditionState copyWith({
    SongwriterAudioAuditionStatus? status,
    SongwriterAudioAuditionMode? mode,
    int? Function()? currentTick,
  }) => SongwriterAudioAuditionState(
    status: status ?? this.status,
    mode: mode ?? this.mode,
    currentTick: currentTick != null ? currentTick() : this.currentTick,
  );
}

class SongwriterAudioAuditionNotifier
    extends Notifier<SongwriterAudioAuditionState> {
  int _version = 0;

  @override
  SongwriterAudioAuditionState build() => const SongwriterAudioAuditionState();

  /// Starts the audition. No-op if already playing, or if [mode] is
  /// [SongwriterAudioAuditionMode.withSection] but [bed] is null/empty.
  ///
  /// The recording loops the trimmed region `[trimStartMs, trimEndMs)`.
  /// [trimEndMs] follows the [AudioClip] convention: `0` (or a value at/after
  /// the asset end) means "no end-trim" and the whole tail loops gaplessly via
  /// the sink. A real end-trim is honoured by re-arming the clip at the region
  /// boundary (see [_loopRegion]).
  Future<void> start({
    required AudioAsset asset,
    required int trimStartMs,
    int trimEndMs = 0,
    required int tempo,
    required SongwriterAudioAuditionMode mode,
    SongwriterAuditionBed? bed,
  }) async {
    if (state.status == SongwriterAudioAuditionStatus.playing) return;
    final withSection = mode == SongwriterAudioAuditionMode.withSection;
    if (withSection && (bed == null || bed.loopTicks <= 0)) return;

    final version = ++_version;
    state = SongwriterAudioAuditionState(
      status: SongwriterAudioAuditionStatus.playing,
      mode: mode,
      currentTick: 0,
    );

    final audioSink = ref.read(songwriterAudioClipSinkProvider);
    await audioSink.prepare([asset]);
    // A Stop issued during the (awaited) prepare must abort before we start the
    // clip — otherwise the loop runs stuck against the clobbered version.
    if (_version != version) return;

    final startOffset = trimStartMs.clamp(0, asset.durationMs);
    final hasEndTrim = trimEndMs > 0 && trimEndMs < asset.durationMs;
    final regionMs = hasEndTrim ? trimEndMs - startOffset : 0;
    if (hasEndTrim && regionMs > 0) {
      // Loop just the trimmed region by re-seeking at its boundary.
      unawaited(_loopRegion(version, asset, startOffset, regionMs));
    } else {
      // No usable end-trim: loop the whole tail from the offset, gaplessly.
      unawaited(audioSink.startClip(
        asset: asset,
        offsetMs: startOffset,
        loop: true,
      ));
    }

    if (!withSection) return; // Alone: the recording loops until stop().

    final noteSink = ref.read(songwriterNoteSinkProvider);
    final drumSink = ref.read(drumPatternPlaybackSinkProvider);
    final loop = bed!.loopTicks;
    final tickDuration = rules.tickDuration(tempo);
    final pacer = TickPacer(tickDuration);

    var tick = 0;
    var elapsedTicks = 0;
    while (_version == version) {
      state = state.copyWith(currentTick: () => tick);
      final notes = bed.notesByTick[tick];
      if (notes != null && notes.isNotEmpty) noteSink(notes);
      final drums = bed.drumByTick[tick];
      if (drums != null && drums.isNotEmpty) unawaited(drumSink(drums, 0.8));
      await pacer.awaitBoundary(++elapsedTicks);
      if (_version != version) return;
      tick = (tick + 1) % loop;
    }
  }

  /// Loops the recording over `[offsetMs, offsetMs + regionMs)` by re-seeking to
  /// the head every [regionMs]. Used when the clip has a real end-trim (the sink
  /// can only loop the whole asset, not an interior region). Cancels with
  /// [_version]. A re-arm re-issues [SongAudioClipSink.startClip], which seeks +
  /// resumes, so it never plays past the trimmed end (modulo scheduling jitter).
  Future<void> _loopRegion(
    int version,
    AudioAsset asset,
    int offsetMs,
    int regionMs,
  ) async {
    final audioSink = ref.read(songwriterAudioClipSinkProvider);
    while (_version == version) {
      unawaited(audioSink.startClip(
        asset: asset,
        offsetMs: offsetMs,
        loop: false,
      ));
      await Future<void>.delayed(Duration(milliseconds: regionMs));
    }
  }

  void stop() {
    _version++;
    unawaited(ref.read(songwriterAudioClipSinkProvider).stopAll());
    state = const SongwriterAudioAuditionState();
  }

  /// Set the audition mode while idle so the chip selection persists before the
  /// user presses Play. No-op while playing (change mode by restarting instead).
  void setMode(SongwriterAudioAuditionMode mode) {
    if (state.status == SongwriterAudioAuditionStatus.playing) return;
    state = state.copyWith(mode: mode);
  }
}

final songwriterAudioAuditionProvider =
    NotifierProvider<SongwriterAudioAuditionNotifier,
        SongwriterAudioAuditionState>(SongwriterAudioAuditionNotifier.new);
