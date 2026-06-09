import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';

void main() {
  group('ProjectConfig', () {
    test('defaults: tempo=120, beatsPerBar=4, beatUnit=4, key fields null', () {
      const cfg = ProjectConfig();
      expect(cfg.tempo, 120);
      expect(cfg.beatsPerBar, 4);
      expect(cfg.beatUnit, 4);
      expect(cfg.keyRootPc, isNull);
      expect(cfg.keyScaleName, isNull);
    });

    test('toJson / fromJson roundtrip preserves all fields', () {
      const original = ProjectConfig(
        keyRootPc: 9,
        keyScaleName: 'minor',
        tempo: 96,
        beatsPerBar: 3,
        beatUnit: 8,
      );
      final restored = ProjectConfig.fromJson(original.toJson());
      expect(restored.keyRootPc, 9);
      expect(restored.keyScaleName, 'minor');
      expect(restored.tempo, 96);
      expect(restored.beatsPerBar, 3);
      expect(restored.beatUnit, 8);
    });

    test('copyWith updates only specified fields; clearKey nulls both key fields', () {
      const original = ProjectConfig(
        keyRootPc: 0,
        keyScaleName: 'major',
        tempo: 120,
      );
      final patched = original.copyWith(tempo: 140);
      expect(patched.tempo, 140);
      expect(patched.keyRootPc, 0);

      final cleared = original.copyWith(clearKey: true);
      expect(cleared.keyRootPc, isNull);
      expect(cleared.keyScaleName, isNull);
      expect(cleared.tempo, 120);
    });
  });
}
