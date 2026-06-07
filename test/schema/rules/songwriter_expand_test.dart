import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('expandSections lays out repeats on a global bar axis', () {
    const sections = [
      SongSection(id: 'a', lengthBars: 4, order: 0, repeat: 2),
      SongSection(id: 'b', lengthBars: 8, order: 1, repeat: 1),
    ];
    final ex = expandSections(sections);
    expect(ex.map((e) => e.sectionId).toList(), ['a', 'a', 'b']);
    expect(ex.map((e) => e.globalStartBar).toList(), [0, 4, 8]);
    expect(ex.map((e) => e.repeatIndex).toList(), [0, 1, 0]);
  });

  test('sectionAtGlobalBar returns the containing instance + local bar', () {
    const sections = [
      SongSection(id: 'a', lengthBars: 4, order: 0, repeat: 2),
    ];
    final ex = expandSections(sections);
    final hit = sectionAtGlobalBar(ex, 5);
    expect(hit, isNotNull);
    expect(hit!.section.sectionId, 'a');
    expect(hit.localBar, 1);
    expect(sectionAtGlobalBar(ex, 99), isNull);
  });
}
