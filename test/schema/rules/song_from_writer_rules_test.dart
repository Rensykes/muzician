import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/song_from_writer_rules.dart';
import 'package:muzician/schema/rules/song_playback_rules.dart'
    as song_playback;
import 'package:muzician/schema/rules/song_render_rules.dart'
    show renderSongPcm;
import 'package:muzician/schema/rules/songwriter_playback_rules.dart'
    as writer_playback;

void main() {
  SongwriterProjectSnapshot writerProject() => const SongwriterProjectSnapshot(
    name: 'My tune',
    config: SongwriterConfig(
      tempo: 96,
      beatsPerBar: 4,
      beatUnit: 4,
      keyRoot: 0,
      keyScaleName: 'major',
    ),
    sections: [
      SongSection(
        id: 's1',
        label: 'Verse',
        lengthBars: 2,
        order: 0,
        repeat: 2,
        lanes: [
          SongLane(
            id: 'l1',
            kind: SongLaneKind.harmony,
            order: 0,
            blocks: [
              SongBlock(
                id: 'b1',
                startBar: 0,
                spanBars: 2,
                chordSymbol: 'C',
                chordNotes: ['C', 'E', 'G'],
              ),
            ],
          ),
          SongLane(
            id: 'l2',
            kind: SongLaneKind.drum,
            order: 1,
            blocks: [
              SongBlock(id: 'b2', startBar: 0, spanBars: 2, patternId: 'dp1'),
            ],
          ),
        ],
      ),
      SongSection(id: 's2', label: 'Chorus', lengthBars: 2, order: 1),
    ],
    drumPatterns: [
      DrumPattern(
        id: 'dp1',
        name: 'Beat',
        lengthTicks: 16,
        lanes: [
          DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
        ],
      ),
    ],
  );

  test('songFromSongwriter maps config, markers, tracks and clips', () {
    final song = songFromSongwriter(writerProject(), const []);

    // Config carried over; bars = 2*2 + 2 = 6 measures.
    expect(song.config.tempo, 96);
    expect(song.config.timeSignature.beatsPerMeasure, 4);
    expect(song.config.totalMeasures, 6);
    expect(song.config.scaleRoot, 'C');
    expect(song.config.scaleName, 'major');

    // One marker per expanded section instance.
    expect(song.markers.map((m) => m.label).toList(), [
      'Verse',
      'Verse',
      'Chorus',
    ]);
    expect(song.markers.map((m) => m.tick).toList(), [0, 32, 64]);

    // Harmony note track + drum track.
    final noteTracks = song.tracks
        .where((t) => t.type == SongTrackType.note)
        .toList();
    final drumTracks = song.tracks
        .where((t) => t.type == SongTrackType.drum)
        .toList();
    expect(noteTracks, hasLength(1));
    expect(drumTracks, hasLength(1));

    // Harmony block repeats across both section instances, sharing a pattern.
    final harmonyClips = song.clips
        .where((c) => c.trackId == noteTracks.single.id)
        .toList();
    expect(harmonyClips, hasLength(2));
    expect(harmonyClips.map((c) => c.startTick).toSet(), {0, 32});
    expect(harmonyClips.map((c) => c.patternId).toSet(), hasLength(1));

    // Chord stabs: one per bar in the 2-bar block.
    final pattern = song.notePatterns.firstWhere(
      (p) => p.id == harmonyClips.first.patternId,
    );
    expect(pattern.lengthTicks, 32);
    expect(pattern.notes.where((n) => n.startTick == 0), hasLength(3));
    expect(pattern.notes.where((n) => n.startTick == 16), hasLength(3));

    // Drum pattern carried over and tiled.
    final drumClips = song.clips
        .where((c) => c.trackId == drumTracks.single.id)
        .toList();
    expect(drumClips, hasLength(2));
    expect(song.drumPatterns, hasLength(1));
  });

  test('multiple harmony lanes export as per-index tracks with volumes', () {
    const chord = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 1,
      chordSymbol: 'C',
      chordNotes: ['C', 'E', 'G'],
    );
    const writer = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'l1',
              kind: SongLaneKind.harmony,
              order: 0,
              volume: 0.4,
              blocks: [chord],
            ),
            SongLane(
              id: 'l2',
              kind: SongLaneKind.harmony,
              order: 1,
              label: 'Double',
              muted: true,
              blocks: [
                SongBlock(
                  id: 'b2',
                  startBar: 0,
                  spanBars: 1,
                  chordSymbol: 'C',
                  chordNotes: ['C', 'E', 'G'],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final song = songFromSongwriter(writer, const []);
    final noteTracks = song.tracks
        .where((t) => t.type == SongTrackType.note)
        .toList();
    expect(noteTracks, hasLength(2));
    expect(noteTracks[0].volume, 0.4);
    expect(noteTracks[1].name, 'Double');
    expect(noteTracks[1].volume, 0.0); // muted → silent track
    // Each lane's block got its own clip on its own track.
    for (final t in noteTracks) {
      expect(song.clips.where((c) => c.trackId == t.id), hasLength(1));
    }
  });

  test('save track inherits the primary harmony lane volume', () {
    final writer = SongwriterProjectSnapshot(
      config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 's1',
          lengthBars: 1,
          order: 0,
          lanes: [
            const SongLane(
              id: 'lh',
              kind: SongLaneKind.harmony,
              order: 0,
              volume: 0.4,
              blocks: [
                SongBlock(
                  id: 'b1',
                  startBar: 0,
                  spanBars: 1,
                  chordSymbol: 'C',
                  chordNotes: ['C', 'E', 'G'],
                ),
              ],
            ),
            SongLane(
              id: 'ls',
              kind: SongLaneKind.save,
              order: 1,
              volume: 1.0, // ignored — save follows the harmony lane
              blocks: [
                SongBlock(
                  id: 'bs',
                  startBar: 0,
                  spanBars: 1,
                  embedded: PianoSnapshot(
                    currentRange: PianoRangeName.key61,
                    selectedKeys: const [
                      PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C'),
                    ],
                    selectedNotes: const ['C'],
                    viewMode: PianoViewMode.exact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final song = songFromSongwriter(writer, const []);
    final saveTrack = song.tracks.firstWhere((t) => t.name == 'Save lane');
    expect(saveTrack.volume, 0.4);
  });

  test('empty writer project yields a default-sized song', () {
    const writer = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );
    final song = songFromSongwriter(writer, const []);
    expect(song.tracks, isEmpty);
    expect(song.config.totalMeasures, greaterThanOrEqualTo(1));
  });

  test(
    'melody and strum import preserve playback notes and omit Writer audio',
    () {
      const writer = SongwriterProjectSnapshot(
        name: 'Patterns',
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
        sections: [
          SongSection(
            id: 's1',
            label: 'Verse',
            lengthBars: 2,
            order: 0,
            lanes: [
              SongLane(
                id: 'harmony',
                kind: SongLaneKind.harmony,
                order: 0,
                blocks: [
                  SongBlock(
                    id: 'chord',
                    startBar: 0,
                    spanBars: 1,
                    chordNotes: ['C', 'E', 'G'],
                  ),
                ],
              ),
              SongLane(
                id: 'melody-lane',
                kind: SongLaneKind.melody,
                order: 1,
                blocks: [
                  SongBlock(
                    id: 'melody-block',
                    startBar: 1,
                    spanBars: 1,
                    patternId: 'melody-pattern',
                  ),
                ],
              ),
              SongLane(
                id: 'strum-lane',
                kind: SongLaneKind.guitarStrum,
                order: 2,
                anchorLaneId: 'harmony',
                blocks: [
                  SongBlock(
                    id: 'strum-block',
                    startBar: 0,
                    spanBars: 1,
                    patternId: 'strum-pattern',
                  ),
                ],
              ),
              SongLane(
                id: 'audio-lane',
                kind: SongLaneKind.audio,
                order: 3,
                label: 'Writer audio',
                blocks: [
                  SongBlock(
                    id: 'audio-block',
                    startBar: 0,
                    spanBars: 1,
                    audioClipId: 'audio-clip',
                  ),
                ],
              ),
            ],
          ),
        ],
        melodyPatterns: [
          NotePattern(
            id: 'melody-pattern',
            name: 'Lead',
            lengthTicks: 8,
            notes: [
              NotePatternNote(
                id: 'lead-note',
                midiNote: 72,
                startTick: 2,
                durationTicks: 4,
                onsetOffsetMs: 7,
              ),
            ],
            pitchRangeStart: 48,
            pitchRangeEnd: 84,
            snapTicks: 1,
            highlightedNotes: [],
          ),
        ],
        guitarStrumPatterns: [
          GuitarStrumPattern(
            id: 'strum-pattern',
            name: 'Down',
            lengthTicks: 16,
            events: [
              GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
            ],
          ),
        ],
      );

      final song = songFromSongwriter(writer, const []);
      expect(song.tracks.any((track) => track.name == 'Writer audio'), isFalse);
      expect(
        song.tracks.where((track) => track.name == 'Melody'),
        hasLength(1),
      );
      expect(
        song.tracks.where((track) => track.name == 'Guitar strum'),
        hasLength(1),
      );

      final writerNotes = [
        for (final event in writer_playback.flattenPlaybackEvents(
          writer,
          const [],
        ))
          for (final group in event.sequencedNoteGroups)
            for (final note in group.notes)
              (
                event.tick,
                note.midiNote,
                note.durationTicks,
                note.onsetOffsetMs,
                note.durationOffsetMs,
              ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final mappedTrackIds = song.tracks
          .where(
            (track) => track.name == 'Melody' || track.name == 'Guitar strum',
          )
          .map((track) => track.id)
          .toSet();
      final notePatternById = {
        for (final pattern in song.notePatterns) pattern.id: pattern,
      };
      final importedNoteIds = {
        for (final clip in song.clips.where(
          (clip) => mappedTrackIds.contains(clip.trackId),
        ))
          for (final note in notePatternById[clip.patternId]!.notes) note.id,
      };
      final importedNotes = [
        for (final event in song_playback.buildPlaybackEvents(song))
          for (final group in event.sequencedNoteGroups)
            for (final note in group.notes.where(
              (note) => importedNoteIds.contains(note.id),
            ))
              (
                event.tick,
                note.midiNote,
                note.durationTicks,
                note.onsetOffsetMs,
                note.durationOffsetMs,
              ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      expect(importedNotes, writerNotes);
      expect(importedNotes.where((note) => note.$4 == 12), hasLength(1));
      expect(
        importedNotes.singleWhere((note) => note.$1 == 18 && note.$2 == 72),
        (18, 72, 4, 7, 0),
      );
    },
  );

  test('repeated strum placements import harmony per placement', () {
    const writer = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 'changing-harmony',
          lengthBars: 3,
          order: 0,
          lanes: [
            SongLane(
              id: 'harmony',
              kind: SongLaneKind.harmony,
              order: 0,
              blocks: [
                SongBlock(
                  id: 'c-major',
                  startBar: 0,
                  spanBars: 1,
                  chordNotes: ['C', 'E', 'G'],
                ),
                SongBlock(
                  id: 'd-major',
                  startBar: 1,
                  spanBars: 1,
                  chordNotes: ['D', 'F#', 'A'],
                ),
                SongBlock(
                  id: 'g-major',
                  startBar: 2,
                  spanBars: 1,
                  chordNotes: ['G', 'B', 'D'],
                ),
              ],
            ),
            SongLane(
              id: 'strum-lane',
              kind: SongLaneKind.guitarStrum,
              order: 1,
              repeat: 3,
              anchorLaneId: 'harmony',
              blocks: [
                SongBlock(
                  id: 'repeated-strum',
                  startBar: 0,
                  spanBars: 1,
                  patternId: 'strum-pattern',
                ),
              ],
            ),
          ],
        ),
      ],
      guitarStrumPatterns: [
        GuitarStrumPattern(
          id: 'strum-pattern',
          name: 'Down/up',
          lengthTicks: 16,
          events: [
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
            GuitarStrumEvent(tick: 8, direction: GuitarStrumDirection.up),
          ],
        ),
      ],
    );

    final writerNotes =
        [
          for (final event in writer_playback.flattenPlaybackEvents(
            writer,
            const [],
          ))
            for (final group in event.sequencedNoteGroups)
              for (final note in group.notes)
                (
                  event.tick,
                  note.midiNote,
                  note.durationTicks,
                  note.onsetOffsetMs,
                  note.durationOffsetMs,
                ),
        ]..sort((a, b) {
          final tickOrder = a.$1.compareTo(b.$1);
          return tickOrder != 0 ? tickOrder : a.$2.compareTo(b.$2);
        });
    final writerPitchesAtTick = <int, Set<int>>{};
    for (final (tick, midiNote, _, _, _) in writerNotes) {
      (writerPitchesAtTick[tick] ??= <int>{}).add(midiNote);
    }
    expect(writerPitchesAtTick, {
      0: {60, 64, 67},
      8: {60, 64, 67},
      16: {62, 66, 69},
      24: {62, 66, 69},
      32: {67, 71, 74},
      40: {67, 71, 74},
    });

    final song = songFromSongwriter(writer, const []);
    final strumTrackId = song.tracks
        .singleWhere((track) => track.name == 'Guitar strum')
        .id;
    final strumClips =
        song.clips.where((clip) => clip.trackId == strumTrackId).toList()
          ..sort((a, b) => a.startTick.compareTo(b.startTick));
    expect(strumClips.map((clip) => clip.startTick), [0, 16, 32]);
    expect(strumClips.map((clip) => clip.patternId).toSet(), hasLength(3));

    final patternById = {
      for (final pattern in song.notePatterns) pattern.id: pattern,
    };
    final importedNoteIds = {
      for (final clip in strumClips)
        for (final note in patternById[clip.patternId]!.notes) note.id,
    };
    final importedNotes =
        [
          for (final event in song_playback.buildPlaybackEvents(song))
            for (final group in event.sequencedNoteGroups)
              for (final note in group.notes.where(
                (note) => importedNoteIds.contains(note.id),
              ))
                (
                  event.tick,
                  note.midiNote,
                  note.durationTicks,
                  note.onsetOffsetMs,
                  note.durationOffsetMs,
                ),
        ]..sort((a, b) {
          final tickOrder = a.$1.compareTo(b.$1);
          return tickOrder != 0 ? tickOrder : a.$2.compareTo(b.$2);
        });
    expect(importedNotes, writerNotes);
  });

  test('clipped melody and strum releases stay inside the imported block', () {
    const writer = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [
        SongSection(
          id: 'boundary-section',
          lengthBars: 1,
          order: 0,
          lanes: [
            SongLane(
              id: 'harmony',
              kind: SongLaneKind.harmony,
              order: 0,
              blocks: [
                SongBlock(
                  id: 'chord',
                  startBar: 0,
                  spanBars: 1,
                  chordNotes: ['C', 'E', 'G'],
                ),
              ],
            ),
            SongLane(
              id: 'melody-lane',
              kind: SongLaneKind.melody,
              order: 1,
              blocks: [
                SongBlock(
                  id: 'melody-block',
                  startBar: 0,
                  spanBars: 1,
                  patternId: 'melody-pattern',
                ),
              ],
            ),
            SongLane(
              id: 'strum-lane',
              kind: SongLaneKind.guitarStrum,
              order: 2,
              blocks: [
                SongBlock(
                  id: 'strum-block',
                  startBar: 0,
                  spanBars: 1,
                  patternId: 'strum-pattern',
                ),
              ],
            ),
          ],
        ),
      ],
      melodyPatterns: [
        NotePattern(
          id: 'melody-pattern',
          name: 'Lead',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'boundary-melody',
              midiNote: 72,
              startTick: 15,
              durationTicks: 3,
              onsetOffsetMs: 36,
            ),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: [],
        ),
      ],
      guitarStrumPatterns: [
        GuitarStrumPattern(
          id: 'strum-pattern',
          name: 'Down',
          lengthTicks: 16,
          events: [
            GuitarStrumEvent(tick: 15, direction: GuitarStrumDirection.down),
          ],
        ),
      ],
    );

    final imported = songFromSongwriter(writer, const []);
    final importedTrackIds = imported.tracks
        .where(
          (track) => track.name == 'Melody' || track.name == 'Guitar strum',
        )
        .map((track) => track.id)
        .toSet();
    final patternById = {
      for (final pattern in imported.notePatterns) pattern.id: pattern,
    };
    final importedNoteIds = {
      for (final clip in imported.clips.where(
        (clip) => importedTrackIds.contains(clip.trackId),
      ))
        for (final note in patternById[clip.patternId]!.notes) note.id,
    };
    final importedNotes = [
      for (final event in song_playback.buildPlaybackEvents(imported))
        for (final group in event.sequencedNoteGroups)
          for (final note in group.notes.where(
            (note) => importedNoteIds.contains(note.id),
          ))
            (event.tick, note),
    ];
    expect(importedNotes, hasLength(4));
    for (final (tick, note) in importedNotes) {
      final availableWindowMs = (16 - tick) * 125;
      final effectiveDurationMs =
          note.durationTicks * 125 + note.durationOffsetMs;
      expect(
        note.onsetOffsetMs + effectiveDurationMs,
        lessThanOrEqualTo(availableWindowMs),
      );
      expect(effectiveDurationMs, greaterThan(0));
    }

    final pcm = renderSongPcm(imported, sampleRate: 8000);
    expect(pcm.take(15999).any((sample) => sample != 0), isTrue);
    expect(pcm.skip(16000).every((sample) => sample == 0), isTrue);
  });

  test(
    'strum export uses primary for null anchor and silences stale anchor',
    () {
      const pattern = GuitarStrumPattern(
        id: 'strum-pattern',
        name: 'Down',
        lengthTicks: 16,
        events: [
          GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
        ],
      );
      const harmony = SongLane(
        id: 'primary',
        kind: SongLaneKind.harmony,
        order: 0,
        blocks: [
          SongBlock(
            id: 'chord',
            startBar: 0,
            spanBars: 1,
            chordNotes: ['C', 'E', 'G'],
          ),
        ],
      );

      for (final (anchorLaneId, shouldStrum) in [
        (null, true),
        ('deleted-harmony', false),
      ]) {
        final writer = SongwriterProjectSnapshot(
          config: const SongwriterConfig(
            tempo: 120,
            beatsPerBar: 4,
            beatUnit: 4,
          ),
          sections: [
            SongSection(
              id: 'section',
              lengthBars: 1,
              order: 0,
              lanes: [
                harmony,
                SongLane(
                  id: 'strum',
                  kind: SongLaneKind.guitarStrum,
                  order: 1,
                  anchorLaneId: anchorLaneId,
                  blocks: const [
                    SongBlock(
                      id: 'strum-block',
                      startBar: 0,
                      spanBars: 1,
                      patternId: 'strum-pattern',
                    ),
                  ],
                ),
              ],
            ),
          ],
          guitarStrumPatterns: const [pattern],
        );

        final song = songFromSongwriter(writer, const []);
        final strumTrack = song.tracks.singleWhere(
          (track) => track.name == 'Guitar strum',
        );
        final strumPatternIds = song.clips
            .where((clip) => clip.trackId == strumTrack.id)
            .map((clip) => clip.patternId)
            .toSet();
        final strumNotes = song.notePatterns
            .where((notePattern) => strumPatternIds.contains(notePattern.id))
            .expand((notePattern) => notePattern.notes);
        expect(strumNotes, shouldStrum ? hasLength(3) : isEmpty);
      }
    },
  );
}
