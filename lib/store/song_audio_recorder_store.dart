/// Shared recorder status and driver used by the Writer audio flow.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SongAudioRecorderStatus {
  idle,
  countIn,
  recording,
  finalising,
  ready,
  error,
}

/// Abstraction over the real `record` package so tests can inject a fake.
abstract class SongAudioRecorderDriver {
  Future<bool> ensurePermission();

  /// Starts capture. [manageIosAudioSession] forwards to the `record` package's
  /// `IosRecordConfig.manageAudioSession`: pass `false` when another plugin
  /// (here, `audioplayers` for record-time monitoring) already owns the shared
  /// AVAudioSession, so the two don't fight over it and silence the capture.
  Future<void> start({bool manageIosAudioSession = true});
  Future<Uint8List> stop();
  Future<void> dispose();
}

final songAudioRecorderDriverProvider = Provider<SongAudioRecorderDriver>((
  ref,
) {
  throw UnimplementedError(
    'Override songAudioRecorderDriverProvider in real launches and tests',
  );
});
