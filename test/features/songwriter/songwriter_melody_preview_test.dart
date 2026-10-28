import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_melody_preview.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/theme/studio_theme.dart';

const pattern = NotePattern(
  id: 'pattern',
  name: 'Lead',
  lengthTicks: 24,
  pitchRangeStart: 48,
  pitchRangeEnd: 84,
  snapTicks: 1,
  highlightedNotes: [],
  notes: [
    NotePatternNote(id: 'a', midiNote: 60, startTick: 0, durationTicks: 4),
    NotePatternNote(id: 'b', midiNote: 64, startTick: 12, durationTicks: 8),
    NotePatternNote(id: 'c', midiNote: 67, startTick: 22, durationTicks: 4),
  ],
);

void main() {
  testWidgets('theme and note changes repaint the existing preview', (
    tester,
  ) async {
    Future<void> show(NotePattern notes, StudioPalette palette) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [palette]),
          home: Center(
            child: SizedBox(
              width: 240,
              height: 48,
              child: SongwriterMelodyPreview(
                pattern: notes,
                segmentStartTick: 0,
                segmentEndTick: 16,
              ),
            ),
          ),
        ),
      );
    }

    await show(pattern, StudioPalette.studio);
    final finder = find.descendant(
      of: find.byType(SongwriterMelodyPreview),
      matching: find.byType(CustomPaint),
    );
    final original = tester.widget<CustomPaint>(finder).painter!;
    await show(pattern, StudioPalette.studioMuzician);
    await tester.pumpAndSettle();
    final themed = tester.widget<CustomPaint>(finder).painter!;
    expect(themed.shouldRepaint(original), isTrue);
    expect(
      finder,
      paints
        ..rrect(color: StudioPalette.studioMuzician.teal.withValues(alpha: .8)),
    );
    await show(
      pattern.copyWith(notes: [pattern.notes.first.copyWith(midiNote: 70)]),
      StudioPalette.studioMuzician,
    );
    expect(
      tester.widget<CustomPaint>(finder).painter!.shouldRepaint(themed),
      isTrue,
    );
  });

  testWidgets('a mid-note continuation retains its pattern-wide pitch row', (
    tester,
  ) async {
    Future<void> show(int start, int end) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [StudioPalette.studio]),
          home: Center(
            child: SizedBox(
              width: 240,
              height: 48,
              child: SongwriterMelodyPreview(
                pattern: pattern,
                segmentStartTick: start,
                segmentEndTick: end,
              ),
            ),
          ),
        ),
      );
    }

    await show(0, 16);
    final first = find.descendant(
      of: find.byType(SongwriterMelodyPreview),
      matching: find.byType(CustomPaint),
    );
    expect(
      first,
      paints
        ..rrect(
          rrect: RRect.fromRectAndRadius(
            const Rect.fromLTRB(0, 40.40625, 60, 44.34375),
            const Radius.circular(1),
          ),
        )
        ..rrect(
          rrect: RRect.fromRectAndRadius(
            const Rect.fromLTRB(180, 19.40625, 240, 23.34375),
            const Radius.circular(1),
          ),
        ),
    );
    await show(16, 48);
    expect(
      first,
      paints..rrect(
        rrect: RRect.fromRectAndRadius(
          const Rect.fromLTRB(0, 19.40625, 30, 23.34375),
          const Radius.circular(1),
        ),
      ),
    );
  });

  test('clips looping notes to loop and visible window boundaries', () {
    final notes = melodyPreviewNotes(
      pattern: pattern,
      segmentStartTick: 16,
      segmentEndTick: 48,
    );
    expect(notes.map((n) => (n.startTick, n.endTick, n.midiNote)), [
      (16, 20, 64),
      (22, 24, 67),
      (24, 28, 60),
      (36, 44, 64),
      (46, 48, 67),
    ]);
  });

  test('clips a placement and ignores invalid starts and empty patterns', () {
    final invalid = pattern.copyWith(
      notes: [
        const NotePatternNote(
          id: 'x',
          midiNote: 40,
          startTick: -1,
          durationTicks: 10,
        ),
        const NotePatternNote(
          id: 'y',
          midiNote: 40,
          startTick: 24,
          durationTicks: 10,
        ),
        const NotePatternNote(
          id: 'z',
          midiNote: 61,
          startTick: 15,
          durationTicks: 0,
        ),
        const NotePatternNote(
          id: 'w',
          midiNote: 62,
          startTick: 14,
          durationTicks: 9,
        ),
      ],
    );
    final notes = melodyPreviewNotes(
      pattern: invalid,
      segmentStartTick: 0,
      segmentEndTick: 16,
    );
    expect(notes.map((n) => (n.startTick, n.endTick, n.midiNote)), [
      (15, 16, 61),
      (14, 16, 62),
    ]);
    for (final p in [
      pattern.copyWith(lengthTicks: 0),
      pattern.copyWith(lengthTicks: -1),
      pattern.copyWith(notes: []),
    ]) {
      expect(
        melodyPreviewNotes(pattern: p, segmentStartTick: 0, segmentEndTick: 16),
        isEmpty,
      );
    }
    expect(
      melodyPreviewNotes(
        pattern: pattern,
        segmentStartTick: 16,
        segmentEndTick: 16,
      ),
      isEmpty,
    );
  });
}
