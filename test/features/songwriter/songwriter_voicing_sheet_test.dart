import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

void main() {
  testWidgets('sheet shows N voicing cards and tapping one fires onAcceptVoicing',
      (tester) async {
    VoicingSuggestion? picked;
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');
    expect(voicings.length, greaterThan(0));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb1', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: null,
              chordMatches: const [],
              scaleMatches: const [],
              onAcceptVoicing: (v) => picked = v,
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voicingCard_c')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voicingCard_c')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.shape, CagedShape.c);
  });

  testWidgets('Voicings tab shows empty state when chord is missing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(id: 'hb', startBar: 0, spanBars: 1),
              voicings: const [],
              thirdAbove: null,
              chordMatches: const [],
              scaleMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Set a chord to see voicings'), findsOneWidget);
  });

  testWidgets('Voicings tab shows unsupported-quality message when suggestions '
      'empty and chord is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 1,
                chordSymbol: 'Bdim', chordQuality: 'dim', chordRootPc: 11,
                chordNotes: ['B', 'D', 'F'], romanNumeral: 'vii°',
              ),
              voicings: const [],
              thirdAbove: null,
              chordMatches: const [],
              scaleMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (_) {},
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No voicings available'),
      findsOneWidget,
    );
  });
}
