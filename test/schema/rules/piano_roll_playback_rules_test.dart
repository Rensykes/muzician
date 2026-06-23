import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/schema/rules/piano_roll_playback_rules.dart' as rules;

void main() {
  group('resolvePlaybackStartTick', () {
    test('returns selectedColumnTick when set', () {
      final state = PianoRollState(
        config: const PianoRollConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: 16,
      );
      expect(rules.resolvePlaybackStartTick(state), 16);
    });

    test('falls back to 0 when selectedColumnTick is null', () {
      final state = PianoRollState(
        config: const PianoRollConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: null,
      );
      expect(rules.resolvePlaybackStartTick(state), 0);
    });
  });

  group('resolvePlaybackEndTick', () {
    test('returns totalTicks from config time signature and totalMeasures', () {
      // ticksPerMeasure for 4/4 = beatsPerMeasure * (beatUnit == 8 ? 2 : 4) = 4 * 4 = 16
      // 16 * 4 measures = 64
      final state = PianoRollState(
        config: const PianoRollConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
          totalMeasures: 4,
        ),
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
      );
      expect(rules.resolvePlaybackEndTick(state), 64);
    });

    test('handles 3/4 time with 8 measures', () {
      // ticksPerMeasure for 3/4 = 3 * 4 = 12; 12 * 8 = 96
      final state = PianoRollState(
        config: const PianoRollConfig(
          tempo: 120,
          timeSignature: TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
          totalMeasures: 8,
        ),
        notes: [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
      );
      expect(rules.resolvePlaybackEndTick(state), 96);
    });
  });

  group('millisecondsPerTick', () {
    test('computes 125ms per tick at 120 BPM', () {
      // 60000 / 120 / 4 = 125.0
      expect(rules.millisecondsPerTick(120), 125.0);
    });

    test('computes 250ms per tick at 60 BPM', () {
      // 60000 / 60 / 4 = 250.0
      expect(rules.millisecondsPerTick(60), 250.0);
    });

    test('computes ~83.33ms per tick at 180 BPM', () {
      // 60000 / 180 / 4 ≈ 83.333...
      expect(rules.millisecondsPerTick(180), closeTo(83.333, 0.001));
    });
  });

  group('tickDuration', () {
    test('computes 125ms per tick at 120 BPM', () {
      expect(rules.tickDuration(120), const Duration(milliseconds: 125));
    });

    test('computes 250ms per tick at 60 BPM', () {
      expect(rules.tickDuration(60), const Duration(milliseconds: 250));
    });

    test('a span is the tick duration times a tick count', () {
      // 4 ticks at 120 BPM → 4 × 125ms = 500ms.
      expect(rules.tickDuration(120) * 4, const Duration(milliseconds: 500));
    });

    test('keeps microsecond precision at tempos that do not divide evenly', () {
      // 1 tick at 180 BPM → 60000/180/4 ≈ 83.333ms. Microsecond-precise
      // (83333µs), not rounded to a whole millisecond, so the transport does
      // not accrue a constant tempo offset.
      expect(rules.tickDuration(180), const Duration(microseconds: 83333));
    });
  });

  group('groupPlaybackEvents', () {
    test(
      'groups same-tick notes into one playback event with sorted MIDI notes',
      () {
        final notes = [
          PianoRollNote(
            id: '1',
            midiNote: 60,
            pitchClass: 'C',
            noteWithOctave: 'C4',
            startTick: 8,
            durationTicks: 4,
          ),
          PianoRollNote(
            id: '2',
            midiNote: 64,
            pitchClass: 'E',
            noteWithOctave: 'E4',
            startTick: 8,
            durationTicks: 4,
          ),
          PianoRollNote(
            id: '3',
            midiNote: 67,
            pitchClass: 'G',
            noteWithOctave: 'G4',
            startTick: 8,
            durationTicks: 4,
          ),
        ];
        final events = rules.groupPlaybackEvents(notes, 0);
        expect(events, hasLength(1));
        expect(events.first.tick, 8);
        expect(events.first.midiNotes, [60, 64, 67]);
      },
    );

    test(
      'excludes notes whose startTick is before the playback start tick',
      () {
        final notes = [
          PianoRollNote(
            id: '1',
            midiNote: 60,
            pitchClass: 'C',
            noteWithOctave: 'C4',
            startTick: 0,
            durationTicks: 4,
          ),
          PianoRollNote(
            id: '2',
            midiNote: 64,
            pitchClass: 'E',
            noteWithOctave: 'E4',
            startTick: 4,
            durationTicks: 4,
          ),
          PianoRollNote(
            id: '3',
            midiNote: 67,
            pitchClass: 'G',
            noteWithOctave: 'G4',
            startTick: 8,
            durationTicks: 4,
          ),
        ];
        final events = rules.groupPlaybackEvents(notes, 4);
        expect(events, hasLength(2));
        expect(events[0].tick, 4);
        expect(events[0].midiNotes, [64]);
        expect(events[1].tick, 8);
        expect(events[1].midiNotes, [67]);
      },
    );

    test(
      'returns events in ascending tick order regardless of input order',
      () {
        final notes = [
          PianoRollNote(
            id: '3',
            midiNote: 67,
            pitchClass: 'G',
            noteWithOctave: 'G4',
            startTick: 8,
            durationTicks: 4,
          ),
          PianoRollNote(
            id: '1',
            midiNote: 60,
            pitchClass: 'C',
            noteWithOctave: 'C4',
            startTick: 0,
            durationTicks: 4,
          ),
          PianoRollNote(
            id: '2',
            midiNote: 64,
            pitchClass: 'E',
            noteWithOctave: 'E4',
            startTick: 4,
            durationTicks: 4,
          ),
        ];
        final events = rules.groupPlaybackEvents(notes, 0);
        expect(events, hasLength(3));
        expect(events[0].tick, 0);
        expect(events[0].midiNotes, [60]);
        expect(events[1].tick, 4);
        expect(events[1].midiNotes, [64]);
        expect(events[2].tick, 8);
        expect(events[2].midiNotes, [67]);
      },
    );

    test('deduplicates MIDI notes at the same tick', () {
      final notes = [
        PianoRollNote(
          id: '1',
          midiNote: 60,
          pitchClass: 'C',
          noteWithOctave: 'C4',
          startTick: 4,
          durationTicks: 4,
        ),
        PianoRollNote(
          id: '2',
          midiNote: 60,
          pitchClass: 'C',
          noteWithOctave: 'C4',
          startTick: 4,
          durationTicks: 2,
        ),
      ];
      final events = rules.groupPlaybackEvents(notes, 0);
      expect(events, hasLength(1));
      expect(events.first.midiNotes, [60]);
    });

    test('returns empty list when no notes are at or after startTick', () {
      final notes = [
        PianoRollNote(
          id: '1',
          midiNote: 60,
          pitchClass: 'C',
          noteWithOctave: 'C4',
          startTick: 0,
          durationTicks: 4,
        ),
      ];
      final events = rules.groupPlaybackEvents(notes, 8);
      expect(events, isEmpty);
    });

    test('handles empty notes list', () {
      final events = rules.groupPlaybackEvents([], 0);
      expect(events, isEmpty);
    });
  });
}
