import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lyric edits undo and redo as one committed text change', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;

    notifier.setSectionLyric(
      sectionId: sectionId,
      verseIndex: 0,
      text: 'A line to remember',
    );
    expect(container.read(songwriterProvider).sections.single.lyrics, [
      'A line to remember',
    ]);
    expect(notifier.undo(), isTrue);
    expect(container.read(songwriterProvider).sections.single.lyrics, isEmpty);
    expect(notifier.redo(), isTrue);
    expect(container.read(songwriterProvider).sections.single.lyrics, [
      'A line to remember',
    ]);
  });

  test('melody-note and strum-event edits undo and redo', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);

    final melodyId = notifier.addMelodyPattern(name: 'Lead', lengthTicks: 16);
    final melody = container.read(songwriterProvider).melodyPatterns.single;
    notifier.updateMelodyPattern(
      melody.copyWith(
        notes: const [
          NotePatternNote(
            id: 'melody-note',
            midiNote: 67,
            startTick: 4,
            durationTicks: 3,
          ),
        ],
      ),
    );

    expect(
      container
          .read(songwriterProvider)
          .melodyPatterns
          .singleWhere((pattern) => pattern.id == melodyId)
          .notes,
      hasLength(1),
    );
    expect(notifier.undo(), isTrue);
    expect(
      container
          .read(songwriterProvider)
          .melodyPatterns
          .singleWhere((pattern) => pattern.id == melodyId)
          .notes,
      isEmpty,
    );
    expect(notifier.redo(), isTrue);
    expect(
      container
          .read(songwriterProvider)
          .melodyPatterns
          .singleWhere((pattern) => pattern.id == melodyId)
          .notes
          .single
          .midiNote,
      67,
    );

    final strumId = notifier.addGuitarStrumPattern(
      name: 'Downstroke',
      lengthTicks: 16,
    );
    final strum = container.read(songwriterProvider).guitarStrumPatterns.single;
    notifier.updateGuitarStrumPattern(
      strum.copyWith(
        events: const [
          GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
        ],
      ),
    );

    expect(
      container
          .read(songwriterProvider)
          .guitarStrumPatterns
          .singleWhere((pattern) => pattern.id == strumId)
          .events,
      hasLength(1),
    );
    expect(notifier.undo(), isTrue);
    expect(
      container
          .read(songwriterProvider)
          .guitarStrumPatterns
          .singleWhere((pattern) => pattern.id == strumId)
          .events,
      equals(strum.events),
    );
    expect(notifier.redo(), isTrue);
    expect(
      container
          .read(songwriterProvider)
          .guitarStrumPatterns
          .singleWhere((pattern) => pattern.id == strumId)
          .events
          .single
          .direction,
      GuitarStrumDirection.down,
    );
  });

  test('project switch, New, and named load clear Writer history', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final firstProjectId = saveSystem.createProject(
      'First',
      const ProjectConfig(),
    )!;
    final secondProjectId = saveSystem.createProject(
      'Second',
      const ProjectConfig(),
    )!;

    saveSystem.selectProject(firstProjectId);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    expect(notifier.canUndo, isTrue);

    saveSystem.selectProject(secondProjectId);
    expect(notifier.canUndo, isFalse);
    expect(notifier.canRedo, isFalse);

    notifier.addSection(label: 'Chorus', lengthBars: 4);
    await notifier.newProject();
    expect(notifier.canUndo, isFalse);
    expect(container.read(songwriterProvider).sections, isEmpty);

    notifier.addSection(label: 'Bridge', lengthBars: 4);
    notifier.loadProject(
      const SongwriterProjectSnapshot(
        name: 'Named snapshot',
        config: SongwriterConfig(
          tempo: 96,
          beatsPerBar: 3,
          beatUnit: 4,
          keyRoot: null,
          keyScaleName: 'major',
        ),
      ),
    );
    expect(notifier.canUndo, isFalse);
    expect(container.read(songwriterProvider).name, 'Named snapshot');
  });
}
