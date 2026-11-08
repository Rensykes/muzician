import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/utils/feedback_diagnostics.dart';
import 'package:muzician/utils/feedback_doc_writer.dart';
import 'package:muzician/utils/feedback_service.dart';

void main() {
  FeedbackEntry entry({int attempt = 1}) => FeedbackEntry(
    docId: 'doc-1',
    sessionId: 'sess-1',
    message: 'hello',
    category: FeedbackCategory.idea,
    contact: '',
    diagnostics: const FeedbackDiagnostics(
      appVersion: '2.0.0+2',
      platform: 'web',
      osVersion: 'Chrome / macOS',
      screen: 'Settings',
      locale: 'en',
    ),
    attempt: attempt,
  );

  test('passes the client document id and adds a server timestamp', () async {
    final writer = _Writer(() async {});
    await FirestoreFeedbackService(writer).send(entry(attempt: 1));
    expect(writer.docId, 'doc-1');
    expect(writer.fields!['createdAt'], isA<FieldValue>());
    expect(writer.fields!['message'], 'hello');
  });

  test(
    'permission_denied on a retry means the document already landed',
    () async {
      final writer = _Writer(
        () async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );
      await expectLater(
        FirestoreFeedbackService(writer).send(entry(attempt: 2)),
        throwsA(
          isA<FeedbackSendException>().having(
            (e) => e.failure,
            'failure',
            FeedbackSendFailure.alreadyRecorded,
          ),
        ),
      );
    },
  );

  test('permission_denied on the first attempt is never success', () async {
    final writer = _Writer(
      () async => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ),
    );
    await expectLater(
      FirestoreFeedbackService(writer).send(entry(attempt: 1)),
      throwsA(
        isA<FeedbackSendException>().having(
          (e) => e.failure,
          'failure',
          FeedbackSendFailure.rejected,
        ),
      ),
    );
  });

  test('unavailable and deadline-exceeded map to unreachable', () async {
    for (final code in ['unavailable', 'deadline-exceeded']) {
      final writer = _Writer(
        () async =>
            throw FirebaseException(plugin: 'cloud_firestore', code: code),
      );
      await expectLater(
        FirestoreFeedbackService(writer).send(entry(attempt: 1)),
        throwsA(
          isA<FeedbackSendException>().having(
            (e) => e.failure,
            'failure',
            FeedbackSendFailure.unreachable,
          ),
        ),
      );
    }
  });
}

class _Writer implements FeedbackDocWriter {
  _Writer(this.behaviour);
  final Future<void> Function() behaviour;
  String? docId;
  Map<String, Object?>? fields;
  @override
  Future<void> create(String docId, Map<String, Object?> fields) async {
    this.docId = docId;
    this.fields = fields;
    await behaviour();
  }
}
