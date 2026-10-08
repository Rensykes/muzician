import 'package:audioplayers/audioplayers.dart';

import 'playback_profiling.dart';

/// Combines a sequenced player's local voice handle with the canonical
/// profile voice identity used by run manifests and score events.
Map<String, Object?> sequencedPlaybackProfileArguments({
  required Map<String, Object?>? profileTimelineArguments,
  required int? sequencedVoiceId,
  Map<String, Object?> additionalArguments = const {},
}) => {
  ...additionalArguments,
  ...?profileTimelineArguments,
  'sequenced_voice_id': ?sequencedVoiceId,
};

/// Adds a development timeline span around audioplayers source binding.
///
/// [delegate] still performs the original source setup through its public
/// [Source.setOnPlayer] implementation. The span therefore includes native
/// preparation and audioplayers' awaited position update.
class PlaybackProfileSource extends Source {
  PlaybackProfileSource(this.delegate, this.arguments);

  final Source delegate;
  final Map<String, Object?> arguments;

  @override
  String? get mimeType => delegate.mimeType;

  @override
  Future<void> setOnPlayer(AudioPlayer player) async {
    final task = PlaybackProfileTask.begin(
      'note_player.source_binding',
      arguments: arguments,
    );
    try {
      await delegate.setOnPlayer(player);
      task.finish(
        arguments: {...arguments, 'outcome': 'source_binding_completed'},
      );
    } catch (error) {
      task.finish(
        arguments: {
          ...arguments,
          'outcome': 'error',
          'error_type': error.runtimeType.toString(),
          'stage': 'source_binding',
        },
      );
      rethrow;
    }
  }
}
