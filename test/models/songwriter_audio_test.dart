import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  group('SongLaneKind.audio', () {
    test('round-trips through name', () {
      final lane = SongLane(id: 'l1', kind: SongLaneKind.audio, order: 0);
      final back = SongLane.fromJson(lane.toJson());
      expect(back.kind, SongLaneKind.audio);
    });
  });

  group('SongBlock.audioClipId', () {
    test('round-trips and clears', () {
      const block = SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 2,
        audioClipId: 'clip1',
      );
      expect(SongBlock.fromJson(block.toJson()).audioClipId, 'clip1');
      expect(block.copyWith(clearAudioClipId: true).audioClipId, isNull);
    });
  });

  group('ChordSegment', () {
    test('round-trips a harmony pick', () {
      const seg = ChordSegment(
        id: 's1',
        startTick: 0,
        spanTicks: 480,
        chordSymbol: 'C',
        chordQuality: 'maj',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
        romanNumeral: 'I',
      );
      final back = ChordSegment.fromJson(seg.toJson());
      expect(back.chordSymbol, 'C');
      expect(back.chordNotes, ['C', 'E', 'G']);
      expect(back.romanNumeral, 'I');
      expect(back.saveId, isNull);
    });

    test('round-trips a save reference', () {
      const seg = ChordSegment(
        id: 's2',
        startTick: 480,
        spanTicks: 480,
        saveId: 'save9',
      );
      expect(ChordSegment.fromJson(seg.toJson()).saveId, 'save9');
    });
  });

  group('AudioClip', () {
    test('round-trips with defaults', () {
      const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000);
      final back = AudioClip.fromJson(clip.toJson());
      expect(back.assetId, 'a1');
      expect(back.trimStartMs, 0);
      expect(back.trimEndMs, 4000);
      expect(back.fitMode, AudioFitMode.loop);
      expect(back.stretchedAssetId, isNull);
      expect(back.segments, isEmpty);
    });

    test('round-trips stretch + segments', () {
      const clip = AudioClip(
        id: 'c2',
        assetId: 'a2',
        trimStartMs: 100,
        trimEndMs: 3000,
        fitMode: AudioFitMode.stretch,
        stretchedAssetId: 'a2s',
        segments: [
          ChordSegment(id: 's1', startTick: 0, spanTicks: 240, saveId: 'x'),
        ],
      );
      final back = AudioClip.fromJson(clip.toJson());
      expect(back.fitMode, AudioFitMode.stretch);
      expect(back.stretchedAssetId, 'a2s');
      expect(back.segments.single.saveId, 'x');
    });
  });

  group('SongwriterProjectSnapshot audio lists', () {
    test('round-trip and legacy default to empty', () {
      const snap = SongwriterProjectSnapshot(
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        audioAssets: [
          AudioAsset(
            id: 'a1',
            durationMs: 4000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [1, 2, 3],
            sourceLabel: 'Recording',
          ),
        ],
        audioClips: [AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000)],
      );
      final back = SongwriterProjectSnapshot.fromJson(snap.toJson());
      expect(back.audioAssets.single.id, 'a1');
      expect(back.audioClips.single.assetId, 'a1');

      final legacy = SongwriterProjectSnapshot.fromJson({
        'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
      });
      expect(legacy.audioAssets, isEmpty);
      expect(legacy.audioClips, isEmpty);
    });
  });
}
