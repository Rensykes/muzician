import '../models/arrangement_content.dart';

/// Sink for audio clips on audio lanes. The default implementation is a no-op
/// so unit tests do not need to touch real audio playback; production code
/// overrides this with [AudioPlayersClipSink].
abstract class AudioClipSink {
  /// Pre-warm internal players so the tick loop's [startClip] calls can fire
  /// in parallel without racing on platform-channel source preparation. The
  /// production implementation pre-loads one `AudioPlayer` per asset; the
  /// no-op default returns immediately.
  Future<void> prepare(Iterable<AudioAsset> assets);
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    double balance = 0.0,
    bool loop = false,
  });
  Future<void> stopClip({required AudioAsset asset});
  Future<void> stopAll();
}

class NoopAudioClipSink implements AudioClipSink {
  const NoopAudioClipSink();
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    double balance = 0.0,
    bool loop = false,
  }) async {}
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async {}
}
