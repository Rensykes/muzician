import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_audio_rules.dart';

const _asset = AudioAsset(
  id: 'a1',
  durationMs: 1500,
  sampleRate: 44100,
  channels: 1,
  format: 'wav',
  peaks: [1],
  sourceLabel: 'Recording',
);

SongwriterProjectSnapshot _project(AudioFitMode mode) {
  const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 1500);
  return SongwriterProjectSnapshot(
    config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    audioAssets: const [_asset],
    audioClips: [clip.copyWith(fitMode: mode)],
    sections: const [
      SongSection(
        id: 's1',
        lengthBars: 4,
        order: 0,
        lanes: [
          SongLane(
            id: 'l1',
            kind: SongLaneKind.audio,
            order: 0,
            blocks: [
              SongBlock(id: 'b1', startBar: 0, spanBars: 2, audioClipId: 'c1'),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('tick->ms at 120 BPM, 4/4: 1 bar = 2000ms', () {
    const cfg = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    final measureTicks = cfg.ticksPerBeat * cfg.beatsPerBar;
    expect(songwriterAudioTickToMs(measureTicks, cfg), 2000);
  });

  test('loop clip fills the whole 2-bar span (4000ms)', () {
    final clips = songwriterSchedulableAudioClips(_project(AudioFitMode.loop));
    final c = clips.single;
    expect(c.startMs, 0);
    expect(c.endMs, 4000);
    expect(c.loop, isTrue);
    expect(c.offsetIntoAsset(0), 0);
  });

  test('one-shot clip stops at natural end (1500ms), not span end', () {
    final clips = songwriterSchedulableAudioClips(
      _project(AudioFitMode.oneShot),
    );
    expect(clips.single.endMs, 1500);
    expect(clips.single.loop, isFalse);
  });

  test('oneShot with trimEndMs==0 plays to the natural asset end', () {
    final base = _project(AudioFitMode.oneShot);
    final clip0 = base.audioClips.single.copyWith(trimEndMs: 0);
    final clips = songwriterSchedulableAudioClips(
      base.copyWith(audioClips: [clip0]),
    );
    // Sentinel 0 → natural end (asset durationMs 1500), not silenced at 0.
    expect(clips.single.endMs, 1500);
  });

  test('section repeat x2 yields two placements', () {
    final base = _project(AudioFitMode.loop);
    final repeated = base.copyWith(
      sections: [base.sections.single.copyWith(repeat: 2)],
    );
    final clips = songwriterSchedulableAudioClips(repeated);
    expect(clips.length, 2);
    expect(clips[1].startMs, 8000); // section length 4 bars = 8000ms
  });
}
