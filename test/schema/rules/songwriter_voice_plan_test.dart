import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/guitar_sound.dart' show GuitarTone;
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/songwriter_playback_rules.dart';
import 'package:muzician/utils/guitar_synth.dart';
import 'package:muzician/utils/playback_voice_spec.dart';

void main() {
  const tick = Duration(milliseconds: 100);

  NotePatternNote note(int midi, {int duration = 2, int onsetMs = 0}) =>
      NotePatternNote(
        id: 'n$midi$onsetMs',
        midiNote: midi,
        startTick: 0,
        durationTicks: duration,
        onsetOffsetMs: onsetMs,
      );

  SongwriterVoicePlan plan(
    List<SongwriterPlaybackEvent> events, {
    int startTick = 0,
    int endTick = 100,
    bool metronome = false,
    GuitarTone tone = GuitarTone.clean,
  }) => playbackVoicePlan(
    events,
    tickDuration: tick,
    measureTicks: 4,
    startTick: startTick,
    endTick: endTick,
    metronome: metronome,
    defaultGuitarTone: tone,
  );

  test('metronome contributes both click flavors', () {
    expect(plan(const [], metronome: true).voices, {
      const PlaybackVoiceSpec.click(accent: true),
      const PlaybackVoiceSpec.click(accent: false),
    });
    expect(plan(const []).voices, isEmpty);
  });

  test('stabs use the chord gate and the shared guitar tone', () {
    final events = [
      SongwriterPlaybackEvent(
        tick: 0,
        noteGroups: [
          (volume: 1, pan: 0, isGuitar: false, midiNotes: [64, 60]),
          (volume: 1, pan: 0, isGuitar: true, midiNotes: [40, 47]),
        ],
      ),
      SongwriterPlaybackEvent(
        tick: 4,
        noteGroups: [
          (volume: 0.5, pan: 1, isGuitar: false, midiNotes: [60, 64]),
        ],
      ),
    ];
    final gate = songwriterChordGate(tick, 4);
    expect(gate, const Duration(milliseconds: 400));
    expect(
      plan(events, tone: GuitarTone.distorted).voices.map((v) => v.cacheKey),
      {
        PlaybackVoiceSpec.sequencedChord([60, 64], duration: gate).cacheKey,
        PlaybackVoiceSpec.sequencedChord(
          [40, 47],
          duration: gate,
          guitarTone: GuitarTone.distorted,
        ).cacheKey,
      },
    );
  });

  test('gate is capped at 700 ms', () {
    expect(
      songwriterChordGate(const Duration(seconds: 1), 4),
      const Duration(milliseconds: 700),
    );
  });

  test('sequenced notes resolve explicit and default guitar tones', () {
    final events = [
      SongwriterPlaybackEvent(
        tick: 0,
        sequencedNoteGroups: [
          (
            volume: 1,
            pan: 0,
            isGuitar: true,
            guitarTone: null,
            notes: [note(52), note(52)],
          ),
          (
            volume: 1,
            pan: 0,
            isGuitar: true,
            guitarTone: GuitarTone.clean,
            notes: [note(52)],
          ),
          (
            volume: 1,
            pan: 0,
            isGuitar: false,
            guitarTone: null,
            notes: [note(52)],
          ),
        ],
      ),
    ];
    const duration = Duration(milliseconds: 200);
    expect(
      plan(events, tone: GuitarTone.distorted).voices.map((v) => v.cacheKey),
      {
        GuitarSynth.noteCacheKey(
          52,
          tone: GuitarTone.distorted,
          duration: duration,
        ),
        GuitarSynth.noteCacheKey(
          52,
          tone: GuitarTone.clean,
          duration: duration,
        ),
        PlaybackVoiceSpec.sequencedNote(52, duration: duration).cacheKey,
      },
    );
  });

  test('drum lanes are collected uniquely', () {
    final events = [
      for (var t = 0; t < 3; t++)
        SongwriterPlaybackEvent(
          tick: t,
          drumGroups: [
            (
              volume: 1,
              pan: 0,
              drumLanes: [DrumLaneId.kick, DrumLaneId.closedHiHat],
            ),
          ],
        ),
    ];
    expect(plan(events).voices, {
      const PlaybackVoiceSpec.drum(DrumLaneId.kick),
      const PlaybackVoiceSpec.drum(DrumLaneId.closedHiHat),
    });
  });

  test('only events inside the run window are prepared', () {
    final events = [
      for (final t in [0, 5, 9])
        SongwriterPlaybackEvent(
          tick: t,
          sequencedNoteGroups: [
            (
              volume: 1,
              pan: 0,
              isGuitar: false,
              guitarTone: null,
              notes: [note(60 + t)],
            ),
          ],
        ),
    ];
    expect(plan(events, startTick: 5, endTick: 9).voices.single.midiNotes, [
      65,
    ]);
  });

  test('peak counts overlapping holds including onset offsets', () {
    final events = [
      SongwriterPlaybackEvent(
        tick: 0,
        sequencedNoteGroups: [
          (
            volume: 1,
            pan: 0,
            isGuitar: true,
            guitarTone: GuitarTone.clean,
            notes: [for (var i = 0; i < 3; i++) note(40 + i, onsetMs: i * 12)],
          ),
        ],
      ),
      // Starts as the first note ends, so the peak does not grow to four.
      SongwriterPlaybackEvent(
        tick: 2,
        sequencedNoteGroups: [
          (
            volume: 1,
            pan: 0,
            isGuitar: true,
            guitarTone: GuitarTone.clean,
            notes: [note(50)],
          ),
        ],
      ),
    ];
    expect(plan(events).peakSequencedVoices, 3);
    expect(plan(const []).peakSequencedVoices, 0);
  });

  group('guitar strokes', () {
    SongwriterPlaybackEvent strokeEvent(int tick, List<int> midis) =>
        SongwriterPlaybackEvent(
          tick: tick,
          strokeGroups: [
            (
              volume: 1,
              pan: 0,
              notes: [
                for (var i = 0; i < midis.length; i++)
                  note(midis[i], onsetMs: i * 12),
              ],
            ),
          ],
        );

    test('each unique stroke is one voice at the shared guitar tone', () {
      final events = [
        strokeEvent(0, [40, 47, 52]),
        strokeEvent(4, [40, 47, 52]),
        strokeEvent(8, [52, 47, 40]),
      ];
      final voices = plan(events, tone: GuitarTone.distorted).voices;
      expect(voices, hasLength(2));
      expect(
        voices.every((v) => v.kind == PlaybackVoiceKind.guitarStroke),
        true,
      );
      expect(
        voices.first,
        PlaybackVoiceSpec.guitarStroke(
          strokeStrings(events.first.strokeGroups.single, tick),
          guitarTone: GuitarTone.distorted,
        ),
      );
    });

    test('stroke strings keep stagger and the clipped per-string duration', () {
      const clipped = NotePatternNote(
        id: 'a',
        midiNote: 40,
        startTick: 0,
        durationTicks: 2,
        onsetOffsetMs: 12,
        durationOffsetMs: -80,
      );
      expect(
        strokeStrings((volume: 1, pan: 0, notes: [note(40), clipped]), tick),
        [
          (midi: 40, onsetMs: 0, durationMs: 200),
          (midi: 40, onsetMs: 12, durationMs: 120),
        ],
      );
    });

    test('a stroke holds one voice however many strings it has', () {
      final events = [
        strokeEvent(0, [40, 47, 52, 55, 59, 64]),
        strokeEvent(1, [64, 59, 55, 52, 47, 40]),
      ];
      expect(plan(events).peakSequencedVoices, 2);
    });

    test('a stroke is held until its latest string ends', () {
      final events = [
        strokeEvent(0, [40, 47]),
        // Strings end at 200 ms and 212 ms; this note starts at 200 ms.
        SongwriterPlaybackEvent(
          tick: 2,
          sequencedNoteGroups: [
            (
              volume: 1,
              pan: 0,
              isGuitar: true,
              guitarTone: GuitarTone.clean,
              notes: [note(50, duration: 1)],
            ),
          ],
        ),
      ];
      expect(plan(events).peakSequencedVoices, 2);
    });
  });
}
