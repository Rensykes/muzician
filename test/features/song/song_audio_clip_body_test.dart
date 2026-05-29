import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_clip_body.dart';

void main() {
  testWidgets('renders clip name and duration label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: AudioClipBody(
              name: 'Take 1',
              durationMs: 12345,
              format: 'wav',
              peaks: [0, 64, 128, 192, 255],
              isBroken: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Take 1'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('WAV'), findsOneWidget);
  });

  testWidgets('shows broken indicator when isBroken', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: AudioClipBody(
              name: 'Missing',
              durationMs: 1000,
              format: 'wav',
              peaks: [],
              isBroken: true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('audio-clip-broken')), findsOneWidget);
  });
}
