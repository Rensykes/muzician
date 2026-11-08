import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/utils/feedback_diagnostics.dart';
import 'package:muzician/utils/feedback_doc_writer.dart';
import 'package:muzician/utils/feedback_service.dart';

void main() {
  FeedbackEntry entry({int attempt = 1, bool possiblyWritten = false}) =>
      FeedbackEntry(
        docId: 'doc-1',
        sessionId: 'sess-1',
        message: 'hello',
        category: FeedbackCategory.idea,
        contact: '',
        diagnostics: const FeedbackDiagnostics(
          appVersion: '2.0.0+2',
          platform: 'web',
          osVersion: 'Chrome / macOS',
          screen: 'settings',
          locale: 'en',
        ),
        attempt: attempt,
        possiblyWritten: possiblyWritten,
      );

  test('passes the client document id and adds a server timestamp', () async {
    final writer = _Writer(() async {});
    await FirestoreFeedbackService(writer).send(entry(attempt: 1));
    expect(writer.docId, 'doc-1');
    expect(writer.fields!['createdAt'], isA<FieldValue>());
    expect(writer.fields!['message'], 'hello');
  });

  test(
    'permission_denied on a retry that may have written is alreadyRecorded',
    () async {
      final writer = _Writer(
        () async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );
      await expectLater(
        FirestoreFeedbackService(
          writer,
        ).send(entry(attempt: 2, possiblyWritten: true)),
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

  test(
    'permission_denied on a retry that could not have written is rejected',
    () async {
      final writer = _Writer(
        () async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        ),
      );
      // A rejected first attempt means nothing landed, so the retry's denial
      // must not be reported as a send.
      await expectLater(
        FirestoreFeedbackService(
          writer,
        ).send(entry(attempt: 2, possiblyWritten: false)),
        throwsA(
          isA<FeedbackSendException>().having(
            (e) => e.failure,
            'failure',
            FeedbackSendFailure.rejected,
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
          isA<FeedbackSendException>()
              .having(
                (e) => e.failure,
                'failure',
                FeedbackSendFailure.unreachable,
              )
              .having((e) => e.cause, 'cause', isA<FirebaseException>()),
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
  Future<void> warmUp() async {}

  @override
  Future<void> create(String docId, Map<String, Object?> fields) async {
    this.docId = docId;
    this.fields = fields;
    await behaviour();
  }
}
