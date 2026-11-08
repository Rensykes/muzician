import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/utils/feedback_diagnostics.dart';

void main() {
  final diagnostics = const FeedbackDiagnostics(
    appVersion: '2.0.0+2',
    platform: 'web',
    osVersion: 'Chrome / macOS',
    screen: 'settings',
    locale: 'en',
  );

  FeedbackEntry entry({int attempt = 1, String message = 'hello'}) =>
      FeedbackEntry(
        docId: 'doc-1',
        sessionId: 'sess-1',
        message: message,
        category: FeedbackCategory.idea,
        contact: '',
        diagnostics: diagnostics,
        attempt: attempt,
      );

  test('rejects empty and over-long messages, counts runes not code units', () {
    expect(FeedbackEntry.validateMessage('   '), isNotNull);
    expect(FeedbackEntry.validateMessage('x' * 4000), isNull);
    expect(FeedbackEntry.validateMessage('x' * 4001), isNotNull);
    expect(countRunes('🐛'), 1);
    expect(FeedbackEntry.validateMessage('🐛' * 4000), isNull);
  });

  test('map carries the rules field set and no client-only fields', () {
    final map = entry(message: '  line one\nline two 🐛 日本語  ').toMap();
    expect(map['schemaVersion'], 1);
    expect(map['message'], 'line one\nline two 🐛 日本語');
    expect(map['category'], 'idea');
    expect(map['contact'], '');
    expect(map['clientSessionId'], 'sess-1');
    expect(map['docId'], isNull, reason: 'the document id is the path');
    expect(map['attempt'], isNull, reason: 'client-only');
    expect(map.keys, hasLength(10));
  });

  test('contact accepts empty, rejects more than 200 runes', () {
    expect(FeedbackEntry.validateContact(''), isNull);
    expect(FeedbackEntry.validateContact('a@b.co'), isNull);
    expect(FeedbackEntry.validateContact('a' * 201), isNotNull);
  });
}
