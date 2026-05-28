import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_playback.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  test('initial state is idle', () {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('stopPlayback resets state to idle', () {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    notifier.stopPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('startPlayback with no clips completes quickly', () async {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    await notifier.startPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.completed,
    );
  });
}
