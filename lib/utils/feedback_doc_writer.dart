/// The only place the app talks to the Firebase SDK.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Writes a feedback document to the backend.
abstract interface class FeedbackDocWriter {
  /// Creates the document at `feedback/[docId]` with [fields].
  Future<void> create(String docId, Map<String, Object?> fields);

  /// Initializes Firebase if needed, without writing anything.
  Future<void> warmUp();
}

/// Writes feedback to the `feedback` collection in Cloud Firestore.
///
/// Firebase is initialized lazily on the first write (or warm-up) so app
/// startup never touches the network.
class FirestoreDocWriter implements FeedbackDocWriter {
  const FirestoreDocWriter();

  @override
  Future<void> warmUp() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  @override
  Future<void> create(String docId, Map<String, Object?> fields) async {
    await warmUp();
    await FirebaseFirestore.instance
        .collection('feedback')
        .doc(docId)
        .set(fields);
  }
}
