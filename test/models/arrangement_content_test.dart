import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/arrangement_content.dart';

void main() {
  test(
    'sequenced note duration offset defaults for old JSON and round-trips',
    () {
      final legacy = NotePatternNote.fromJson({
        'id': 'legacy',
        'midiNote': 60,
        'startTick': 0,
        'durationTicks': 4,
        'onsetOffsetMs': 12,
      });
      expect(legacy.durationOffsetMs, 0);

      const clipped = NotePatternNote(
        id: 'clipped',
        midiNote: 64,
        startTick: 15,
        durationTicks: 1,
        onsetOffsetMs: 24,
        durationOffsetMs: -24,
      );
      final restored = NotePatternNote.fromJson(clipped.toJson());
      expect(restored.onsetOffsetMs, 24);
      expect(restored.durationOffsetMs, -24);
    },
  );

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
}
