import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_recorder_sheet.dart';
import 'package:muzician/store/song_audio_recorder_store.dart';

/// Pushes the recorder state machine into specific statuses without touching
/// disk so the widget test stays deterministic.
class _ScriptedRecorderNotifier extends SongAudioRecorderNotifier {
  final SongAudioRecorderState initial;
  _ScriptedRecorderNotifier(this.initial);

  @override
  SongAudioRecorderState build() => initial;
}

void main() {
  testWidgets('shows Record + Close buttons when idle', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songAudioRecorderProvider.overrideWith(
            () => _ScriptedRecorderNotifier(const SongAudioRecorderState()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SongAudioRecorderSheet(trackId: 't1', startTick: 0),
          ),
        ),
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-cancel')), findsOneWidget);
  });

  testWidgets('shows Stop + Cancel buttons when recording', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songAudioRecorderProvider.overrideWith(
            () => _ScriptedRecorderNotifier(
              const SongAudioRecorderState(
                status: SongAudioRecorderStatus.recording,
                targetTrackId: 't1',
                startTick: 0,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SongAudioRecorderSheet(trackId: 't1', startTick: 0),
          ),
        ),
      ),
    );
    expect(find.text('Recording…'), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-stop')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-cancel')), findsOneWidget);
  });

  testWidgets('shows spinner when finalising', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songAudioRecorderProvider.overrideWith(
            () => _ScriptedRecorderNotifier(
              const SongAudioRecorderState(
                status: SongAudioRecorderStatus.finalising,
                targetTrackId: 't1',
                startTick: 0,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SongAudioRecorderSheet(trackId: 't1', startTick: 0),
          ),
        ),
      ),
    );
    expect(find.text('Finalising…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error message in error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songAudioRecorderProvider.overrideWith(
            () => _ScriptedRecorderNotifier(
              const SongAudioRecorderState(
                status: SongAudioRecorderStatus.error,
                errorMessage: 'Microphone permission denied',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SongAudioRecorderSheet(trackId: 't1', startTick: 0),
          ),
        ),
      ),
    );
    expect(find.text('Microphone permission denied'), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-start')), findsOneWidget);
  });
}
