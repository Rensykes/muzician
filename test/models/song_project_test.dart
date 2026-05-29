import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  group('AudioAsset', () {
    test('JSON round-trip preserves all fields', () {
      const asset = AudioAsset(
        id: 'asset-1',
        durationMs: 4321,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [0, 64, 128, 192, 255],
        sourceLabel: 'Recording',
      );
      final json = asset.toJson();
      final restored = AudioAsset.fromJson(json);
      expect(restored.id, 'asset-1');
      expect(restored.durationMs, 4321);
      expect(restored.sampleRate, 44100);
      expect(restored.channels, 1);
      expect(restored.format, 'wav');
      expect(restored.peaks, [0, 64, 128, 192, 255]);
      expect(restored.sourceLabel, 'Recording');
    });
  });

  group('AudioClipPattern', () {
    test('JSON round-trip preserves all fields', () {
      const p = AudioClipPattern(id: 'p1', name: 'Take 1', assetId: 'asset-1');
      final json = p.toJson();
      final restored = AudioClipPattern.fromJson(json);
      expect(restored.id, 'p1');
      expect(restored.name, 'Take 1');
      expect(restored.assetId, 'asset-1');
    });
  });

  group('SongProject with audio', () {
    test('defaults audioAssets and audioPatterns to empty', () {
      final p = SongProject(
        config: SongProjectConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: const [],
        audioPatterns: const [],
      );
      expect(p.audioAssets, isEmpty);
      expect(p.audioPatterns, isEmpty);
    });

    test('legacy JSON without audio fields loads with empty lists', () {
      final json = {
        'config': {
          'tempo': 120,
          'timeSignature': {'beatsPerMeasure': 4, 'beatUnit': 4},
          'totalMeasures': 4,
        },
        'tracks': [],
        'clips': [],
        'notePatterns': [],
        'drumPatterns': [],
      };
      final p = SongProject.fromJson(json);
      expect(p.audioAssets, isEmpty);
      expect(p.audioPatterns, isEmpty);
    });

    test('round-trips audio assets and patterns', () {
      final p = SongProject(
        config: SongProjectConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        tracks: const [],
        clips: const [],
        notePatterns: const [],
        drumPatterns: const [],
        audioAssets: const [
          AudioAsset(
            id: 'a1',
            durationMs: 1000,
            sampleRate: 44100,
            channels: 1,
            format: 'wav',
            peaks: [0, 128, 255],
            sourceLabel: 'Recording',
          ),
        ],
        audioPatterns: const [
          AudioClipPattern(id: 'p1', name: 'Take', assetId: 'a1'),
        ],
      );
      final restored = SongProject.fromJson(p.toJson());
      expect(restored.audioAssets, hasLength(1));
      expect(restored.audioAssets.first.id, 'a1');
      expect(restored.audioPatterns.first.assetId, 'a1');
    });
  });
}
