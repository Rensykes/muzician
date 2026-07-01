/// iOS audio-session coordination for monitored recording.
///
/// The app configures a single global `audioplayers` session whose iOS category
/// is `playback` (see [AudioPlayersClipSink]) — a category that forbids mic
/// capture. When the Songwriter records WITH monitoring, the backing / metronome
/// / clips play through `audioplayers` while the `record` package captures from
/// the mic. Because iOS has one shared `AVAudioSession`, an `audioplayers`
/// playback activation would re-assert the `playback` category and revoke the
/// recorder's `playAndRecord` input route — so the take records silent.
///
/// [enterRecording] switches the global session to `playAndRecord` (so playback
/// and capture coexist) for the recording window; [restore] returns it to
/// `playback` afterwards. Both are no-ops off iOS / in tests via
/// [NoopRecordAudioSession]; the production impl is wired in `main.dart`.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class RecordAudioSession {
  /// Make the global session allow simultaneous capture + playback.
  Future<void> enterRecording();

  /// Restore the playback-only session.
  Future<void> restore();
}

/// Default sink: does nothing. Used off iOS and in tests.
class NoopRecordAudioSession implements RecordAudioSession {
  const NoopRecordAudioSession();
  @override
  Future<void> enterRecording() async {}
  @override
  Future<void> restore() async {}
}

/// Production impl: flips the global `audioplayers` audio context. The context
/// is process-wide for `audioplayers`, so one switch covers the bed, the
/// metronome clicks (both via `NotePlayer`) and the clip sink.
class AudioPlayersRecordAudioSession implements RecordAudioSession {
  const AudioPlayersRecordAudioSession();

  // Android coexists via the music/gain focus already used by the clip sink;
  // the category switch is an iOS concern, so Android stays constant here.
  static const _android = AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.media,
    audioFocus: AndroidAudioFocus.gain,
  );

  @override
  Future<void> enterRecording() => AudioPlayer.global.setAudioContext(
    AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.defaultToSpeaker,
          AVAudioSessionOptions.allowBluetooth,
        },
      ),
      android: _android,
    ),
  );

  @override
  Future<void> restore() => AudioPlayer.global.setAudioContext(
    AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
      android: _android,
    ),
  );
}

/// No-op by default; overridden with [AudioPlayersRecordAudioSession] in
/// `main.dart`. Tests override it with a fake to assert the wiring.
final recordAudioSessionProvider = Provider<RecordAudioSession>(
  (ref) => const NoopRecordAudioSession(),
);
