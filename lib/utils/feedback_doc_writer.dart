/// The only place the app talks to the Firebase SDK.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Writes a feedback document to the backend.
abstract interface class FeedbackDocWriter {
  /// Creates the document at `feedback/[docId]` with [fields].
  Future<void> create(String docId, Map<String, Object?> fields);
}

/// Writes feedback to the `feedback` collection in Cloud Firestore.
///
/// Firebase is initialized lazily on the first write so app startup never
/// touches the network.
class FirestoreDocWriter implements FeedbackDocWriter {
  const FirestoreDocWriter();

  @override
  Future<void> create(String docId, Map<String, Object?> fields) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    await FirebaseFirestore.instance
        .collection('feedback')
        .doc(docId)
        .set(fields);
  }
}
