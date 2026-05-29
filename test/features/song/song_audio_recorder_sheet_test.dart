import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_recorder_sheet.dart';
import 'package:muzician/models/song_project.dart';
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
  testWidgets('shows Record button when idle', (tester) async {
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
  });

  testWidgets('shows Stop button when recording', (tester) async {
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
  });

  testWidgets(
      'preview renders waveform body and Discard / Retry / Confirm actions',
      (tester) async {
    const asset = AudioAsset(
      id: 'a1',
      durationMs: 4321,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [0, 64, 128, 192, 255],
      sourceLabel: 'Recording',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songAudioRecorderProvider.overrideWith(
            () => _ScriptedRecorderNotifier(
              const SongAudioRecorderState(
                status: SongAudioRecorderStatus.preview,
                targetTrackId: 't1',
                startTick: 0,
                pendingAsset: asset,
                elapsedMs: 4321,
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
    expect(find.text('Review the take'), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-discard')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-rec-confirm')), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('WAV'), findsOneWidget);
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
