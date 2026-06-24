import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/drum_presets.dart';

void main() {
  test('library is non-empty and every preset is valid', () {
    expect(drumPresets, isNotEmpty);
    for (final p in drumPresets) {
      expect(p.lengthTicks, greaterThan(0), reason: p.name);
      expect(p.name.trim(), isNotEmpty);
      expect(p.category.trim(), isNotEmpty);
      final hitCount = p.hits.values.fold<int>(0, (n, t) => n + t.length);
      expect(hitCount, greaterThan(0), reason: '${p.name} has no hits');
      for (final entry in p.hits.entries) {
        for (final t in entry.value) {
          expect(
            t,
            inInclusiveRange(0, p.lengthTicks - 1),
            reason: '${p.name} / ${entry.key}',
          );
        }
      }
    }
  });

  test('preset names are unique', () {
    final names = drumPresets.map((p) => p.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('buildLanes yields all eight voices in canonical order', () {
    final lanes = drumPresets.first.buildLanes();
    expect(lanes.map((l) => l.laneId).toList(), DrumLaneId.values);
  });

  test('toPattern carries id, name, and length', () {
    final preset = drumPresets.first;
    final pattern = preset.toPattern('x1');
    expect(pattern.id, 'x1');
    expect(pattern.name, preset.name);
    expect(pattern.lengthTicks, preset.lengthTicks);
    expect(pattern.lanes.length, DrumLaneId.values.length);
  });

  test('Four on the Floor lands the kick on every beat', () {
    final preset = drumPresets.firstWhere((p) => p.name == 'Four on the Floor');
    expect(preset.hits[DrumLaneId.kick], [0, 4, 8, 12]);
  });

  test('categories cover the expected genres', () {
    final cats = drumPresets.map((p) => p.category).toSet();
    expect(
      cats,
      containsAll(<String>['Rock', 'Funk', 'Pop', 'Latin', 'Hip-Hop', 'Fills']),
    );
  });
}
