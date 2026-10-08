/// Production [SongAudioClipSink] backed by one `AudioPlayer` per asset.
///
/// Sets a global iOS audio session that allows multiple internal
/// `AVAudioPlayer` instances to coexist (mixes within the app) and pre-loads
/// every player's source at [prepare] time so the tick loop's parallel
/// startClip calls only have to seek + resume.
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_project.dart';
import '../utils/playback_profiling.dart';
import 'song_audio_repository.dart';
import 'song_playback_store.dart';

class AudioPlayersClipSink implements SongAudioClipSink {
  AudioPlayersClipSink(this.repository) {
    // Run once per sink lifetime: configure the global audio session so
    // concurrent in-app playback does not interrupt itself.  Without
    // `mixWithOthers`, a new player's session activation can preempt any
    // other player whose preparation has not yet completed.
    final contextTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin('writer.clip_sink.global_audio_context')
        : null;
    final contextFuture = AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    if (contextTrace != null) {
      unawaited(
        contextFuture.then<void>(
          (_) => contextTrace.finish(
            arguments: {'context_future_completed': true},
          ),
          onError: (Object error, StackTrace stackTrace) {
            contextTrace.finish(
              arguments: {
                'context_future_completed': false,
                'error_type': error.runtimeType.toString(),
              },
            );
            Error.throwWithStackTrace(error, stackTrace);
          },
        ),
      );
    }
  }

  final SongAudioRepository repository;
  final Map<String, AudioPlayer> _players = {};

  /// Last balance set per asset player — players start centered, so skip the
  /// platform call while the value is unchanged (0.0 for unpanned lanes).
  final Map<String, double> _balanceByAsset = {};

  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {
    final prepareTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin('writer.clip_sink.prepare')
        : null;
    int? assetCount = playbackProfilingEnabled ? 0 : null;
    int? preparedCount = playbackProfilingEnabled ? 0 : null;
    try {
      for (final asset in assets) {
        if (assetCount != null) assetCount++;
        final pathTrace = playbackProfilingEnabled
            ? PlaybackProfileTask.begin(
                'writer.clip_sink.resolve_path',
                arguments: {'asset_id': asset.id, 'format': asset.format},
              )
            : null;
        final File file;
        final bool fileExists;
        try {
          file = await repository.resolvePath(asset.id, asset.format);
          fileExists = file.existsSync();
          pathTrace?.finish(
            arguments: {'outcome': 'path_resolved', 'exists': fileExists},
          );
        } catch (error) {
          pathTrace?.finishError(error, stage: 'resolve_path');
          rethrow;
        }
        if (!fileExists) continue;
        final wasPrepared =
            playbackProfilingEnabled && _players.containsKey(asset.id);
        final player = _players.putIfAbsent(asset.id, () {
          final p = AudioPlayer();
          // Keep the loaded source after `stop()` so subsequent plays only
          // need to seek + resume.
          p.setReleaseMode(ReleaseMode.stop);
          return p;
        });
        // Always (re)bind the source — covers replaced/re-recorded assets and
        // the first-time load on a fresh player.
        final sourceTrace = playbackProfilingEnabled
            ? PlaybackProfileTask.begin(
                'writer.clip_sink.set_source',
                arguments: {
                  'asset_id': asset.id,
                  'player_id': identityHashCode(player),
                  'existing_player': wasPrepared,
                },
              )
            : null;
        try {
          await player.setSource(DeviceFileSource(file.path));
          await player.pause();
          sourceTrace?.finish(
            arguments: {'outcome': 'source_ready_and_paused'},
          );
        } catch (error) {
          sourceTrace?.finishError(error, stage: 'set_source_or_pause');
          rethrow;
        }
        if (preparedCount != null) preparedCount++;
      }
      prepareTrace?.finish(
        arguments: {
          'outcome': 'completed',
          'asset_count': assetCount,
          'prepared_count': preparedCount,
        },
      );
    } catch (error, stackTrace) {
      prepareTrace?.finishError(error, stage: 'prepare');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    double balance = 0.0,
    bool loop = false,
  }) async {
    final startTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'writer.clip_sink.start_clip',
            arguments: {
              'asset_id': asset.id,
              'offset_ms': offsetMs,
              'volume': volume,
              'pan': balance,
              'loop': loop,
            },
          )
        : null;
    try {
      var player = _players[asset.id];
      if (player == null) {
        // Lazy fall-back path: a clip was added after [prepare] (e.g. the user
        // imported during playback).  Load + bind now.
        final file = await repository.resolvePath(asset.id, asset.format);
        if (!file.existsSync()) {
          startTrace?.finish(arguments: {'outcome': 'skipped_missing_file'});
          return;
        }
        player = AudioPlayer();
        player.setReleaseMode(ReleaseMode.stop);
        final sourceTrace = playbackProfilingEnabled
            ? PlaybackProfileTask.begin(
                'writer.clip_sink.lazy_set_source',
                arguments: {
                  'asset_id': asset.id,
                  'player_id': identityHashCode(player),
                },
              )
            : null;
        try {
          await player.setSource(DeviceFileSource(file.path));
          sourceTrace?.finish(arguments: {'outcome': 'source_ready'});
        } catch (error) {
          sourceTrace?.finishError(error, stage: 'lazy_set_source');
          rethrow;
        }
        _players[asset.id] = player;
      }
      final configureTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'writer.clip_sink.configure',
              arguments: {
                'asset_id': asset.id,
                'player_id': identityHashCode(player),
                'loop': loop,
              },
            )
          : null;
      try {
        await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
        await player.setVolume(volume.clamp(0.0, 1.0));
        final clampedBalance = balance.clamp(-1.0, 1.0);
        if ((_balanceByAsset[asset.id] ?? 0.0) != clampedBalance) {
          _balanceByAsset[asset.id] = clampedBalance;
          await player.setBalance(clampedBalance);
        }
        configureTrace?.finish(arguments: {'outcome': 'configured'});
      } catch (error) {
        configureTrace?.finishError(error, stage: 'configure');
        rethrow;
      }
      final seekTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'writer.clip_sink.seek',
              arguments: {'asset_id': asset.id, 'offset_ms': offsetMs},
            )
          : null;
      try {
        await player.seek(Duration(milliseconds: offsetMs));
        seekTrace?.finish(arguments: {'outcome': 'seek_future_completed'});
      } catch (error) {
        seekTrace?.finishError(error, stage: 'seek');
        rethrow;
      }
      final resumeTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'writer.clip_sink.resume',
              arguments: {'asset_id': asset.id, 'offset_ms': offsetMs},
            )
          : null;
      try {
        await player.resume();
        resumeTrace?.finish(arguments: {'outcome': 'resume_future_completed'});
        startTrace?.finish(arguments: {'outcome': 'resume_future_completed'});
      } catch (error) {
        resumeTrace?.finishError(error, stage: 'resume');
        rethrow;
      }
    } catch (error, stackTrace) {
      startTrace?.finishError(error, stage: 'start_clip');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    final stopTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'writer.clip_sink.stop_clip',
            arguments: {'asset_id': asset.id},
          )
        : null;
    final player = _players[asset.id];
    if (player == null) {
      stopTrace?.finish(arguments: {'outcome': 'no_player'});
      return;
    }
    try {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.stop);
      stopTrace?.finish(arguments: {'outcome': 'stop_future_completed'});
    } catch (error, stackTrace) {
      stopTrace?.finishError(error, stage: 'stop_clip');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> stopAll() async {
    // Snapshot before iterating: the awaited `stop()` yields control, and a
    // concurrent `startClip`/`prepare` may insert into `_players` during the
    // suspension — iterating the live view would throw ConcurrentModification.
    final stopTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'writer.clip_sink.stop_all',
            arguments: {'player_count': _players.length},
          )
        : null;
    try {
      for (final player in _players.values.toList()) {
        await player.stop();
      }
      stopTrace?.finish(arguments: {'outcome': 'stop_futures_completed'});
    } catch (error, stackTrace) {
      stopTrace?.finishError(error, stage: 'stop_all');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// Override in `main.dart` to swap the no-op sink in [songAudioClipSinkProvider]
/// for the real one.  Tests keep using the no-op default unless they override
/// the same provider explicitly.
final productionSongAudioClipSinkProvider = Provider<SongAudioClipSink>((ref) {
  return AudioPlayersClipSink(ref.read(songAudioRepositoryProvider));
});
