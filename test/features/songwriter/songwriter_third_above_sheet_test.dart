import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_third_above_rules.dart';
import 'package:muzician/schema/rules/songwriter_voicing_rules.dart';
import 'package:muzician/features/songwriter/songwriter_block_preview.dart';

void main() {
  ThirdAboveSuggestion freshThird() => suggestThirdAbove(
        chordRootPc: 0,
        chordQuality: '',
        chordTonePcs: const [0, 4, 7],
        keyRootPc: 0,
        keyScaleName: 'major',
      )!;

  testWidgets('sheet has Voicings + Harmony tabs', (tester) async {
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: freshThird(),
              chordMatches: const [],
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

    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsOneWidget);
  });

  testWidgets('switching to Harmony tab shows the third-above card '
      'and tapping it fires onAcceptThirdAbove', (tester) async {
    ThirdAboveSuggestion? picked;
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: freshThird(),
              chordMatches: const [],
              onAcceptVoicing: (_) {},
              onAcceptThirdAbove: (s) => picked = s,
              onAcceptLibrary: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Harmony'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('thirdAboveCard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('thirdAboveCard')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.targetPcs, [4, 7, 11]);
  });

  testWidgets('Harmony tab shows "Set a key" message when thirdAbove is null',
      (tester) async {
    final voicings = suggestVoicings(chordRootPc: 0, quality: '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showHarmonyBlockSheet(
              context,
              block: const SongBlock(
                id: 'hb', startBar: 0, spanBars: 2,
                chordSymbol: 'C', chordQuality: '', chordRootPc: 0,
                chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
              ),
              voicings: voicings,
              thirdAbove: null,
              chordMatches: const [],
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

    await tester.tap(find.text('Harmony'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Set a key'), findsOneWidget);
  });
}
