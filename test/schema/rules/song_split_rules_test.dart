import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_split_rules.dart';

void main() {
  group('splitNotePattern', () {
    const pattern = NotePattern(
      id: 'p1',
      name: 'Riff',
      lengthTicks: 16,
      notes: [
        NotePatternNote(id: 'a', midiNote: 60, startTick: 0, durationTicks: 4),
        NotePatternNote(id: 'b', midiNote: 62, startTick: 10, durationTicks: 4),
        // Straddles tick 8: 6..14
        NotePatternNote(id: 'c', midiNote: 64, startTick: 6, durationTicks: 8),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 1,
      highlightedNotes: [],
    );

    test('partitions notes around the split tick', () {
      final result = splitNotePattern(
        pattern,
        8,
        leftId: 'L',
        rightId: 'R',
      );
      expect(result, isNotNull);
      final (left, right) = (result!.left, result.right);

      expect(left.id, 'L');
      expect(left.lengthTicks, 8);
      expect(right.id, 'R');
      expect(right.lengthTicks, 8);

      // 'a' stays left untouched; 'c' truncated to 6..8.
      expect(left.notes.map((n) => n.midiNote), [60, 64]);
      final cLeft = left.notes.firstWhere((n) => n.midiNote == 64);
      expect(cLeft.startTick, 6);
      expect(cLeft.durationTicks, 2);

      // 'b' shifts to 2; 'c' remainder starts at 0 with 6 ticks.
      expect(right.notes.map((n) => n.midiNote).toSet(), {62, 64});
      final bRight = right.notes.firstWhere((n) => n.midiNote == 62);
      expect(bRight.startTick, 2);
      final cRight = right.notes.firstWhere((n) => n.midiNote == 64);
      expect(cRight.startTick, 0);
      expect(cRight.durationTicks, 6);
    });

    test('rejects out-of-range split ticks', () {
      expect(splitNotePattern(pattern, 0, leftId: 'L', rightId: 'R'), isNull);
      expect(splitNotePattern(pattern, 16, leftId: 'L', rightId: 'R'), isNull);
      expect(splitNotePattern(pattern, -2, leftId: 'L', rightId: 'R'), isNull);
    });
  });

  group('splitDrumPattern', () {
    const pattern = DrumPattern(
      id: 'd1',
      name: 'Beat',
      lengthTicks: 16,
      lanes: [
        DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8, 12]),
        DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [4]),
      ],
    );

    test('partitions hits and drops empty lanes', () {
      final result = splitDrumPattern(pattern, 8, leftId: 'L', rightId: 'R');
      expect(result, isNotNull);
      final (left, right) = (result!.left, result.right);

      expect(left.lengthTicks, 8);
      expect(right.lengthTicks, 8);
      final kickLeft = left.lanes.firstWhere(
        (l) => l.laneId == DrumLaneId.kick,
      );
      expect(kickLeft.activeTicks, [0]);
      final snareLeft = left.lanes.firstWhere(
        (l) => l.laneId == DrumLaneId.snare,
      );
      expect(snareLeft.activeTicks, [4]);

      final kickRight = right.lanes.firstWhere(
        (l) => l.laneId == DrumLaneId.kick,
      );
      expect(kickRight.activeTicks, [0, 4]); // 8→0, 12→4
      expect(right.lanes.any((l) => l.laneId == DrumLaneId.snare), isFalse);
    });

    test('rejects out-of-range split ticks', () {
      expect(splitDrumPattern(pattern, 16, leftId: 'L', rightId: 'R'), isNull);
    });
  });
}
