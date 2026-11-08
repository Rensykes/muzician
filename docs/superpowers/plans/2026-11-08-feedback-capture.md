# In-App Feedback Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tester can send a bug report or idea from Settings on web and Android, with app context attached, into a Firestore collection the developer reads in the console.

**Architecture:** A local draft store (Riverpod + `shared_preferences`) owns the message and its client-generated document ID; `FeedbackService` maps Firestore errors to four outcomes; `FirestoreDocWriter` is the only file that creates Firestore clients and collections (the service may reference SDK types such as `FieldValue` and `FirebaseException`, never a client). The sheet is a Studio-palette bottom sheet opened from a new Settings group.

**Tech Stack:** Flutter 3.x, Riverpod `NotifierProvider`, `shared_preferences`, `uuid`, `package_info_plus`, `cloud_firestore`, `firebase_core`, Firebase CLI + FlutterFire CLI.

**Spec:** `docs/superpowers/specs/2026-11-08-feedback-capture-design.md`

## Global Constraints

- Document ID is a uuid v4 generated on the device and reused across retries.
- Collection `feedback`, schema version `1`, Firestore location `eur3` (created once, permanent).
- Client caps the message at **4000 runes**; rules cap the stored string at **16000** so that any client-valid message passes regardless of how rules count multi-byte text.
- No install identifier, analytics or crash reporting. The only outbound write is a feedback submission the tester confirms.
- Public contact address everywhere: `bytebakehouseinc@gmail.com`.
- The Settings entry appears only when `isFeedbackAvailable` (web, or Android).
- Firebase is initialized lazily on the first send, never at startup.
- Dart 2-space indent, `UpperCamelCase` types, `snake_case.dart` files, Studio palette via `StudioPalette.of(context)`, commits in `feat:` / `docs:` style.
- Every task ends with `dart format <paths>`, `flutter analyze`, and the task's own `flutter test` target passing.

## Review Focus

1. **Send with no network.** Pressing Send in airplane mode keeps the text, shows a retry path within seconds, and never reports success. Task 5.
2. **App killed mid-send, then retried.** One document, not two; text never vanishes. Tasks 4 and 5.
3. **Rules missing or rejecting the payload.** A `permission_denied` on the *first* attempt must not read as "already sent". Task 4.
4. **Long or non-Latin input.** A 6000-character paste, emoji, CJK and newlines are capped in the field, counted in runes, and survive the round trip. Task 2.
5. **Keyboard open on a small screen.** A 320×568 sheet with the keyboard up scrolls and keeps Send reachable. Task 6.

---

### Task 1: Diagnostics

**Files:**
- Create: `lib/utils/feedback_diagnostics.dart`
- Create: `lib/utils/feedback_user_agent.dart`, `lib/utils/feedback_user_agent_stub.dart`, `lib/utils/feedback_user_agent_web.dart`
- Modify: `pubspec.yaml` (add `package_info_plus`)
- Test: `test/utils/feedback_diagnostics_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class FeedbackDiagnostics { const FeedbackDiagnostics({required String appVersion, required String platform, required String osVersion, required String screen, required String locale}); Map<String, Object?> toMap(); String get summary; }`
  - `Future<FeedbackDiagnostics> captureDiagnostics({required String screen})`
  - `String describeUserAgent(String? userAgent)` — `unknown` when it cannot classify.
  - `bool get isFeedbackAvailable` — `kIsWeb || defaultTargetPlatform == TargetPlatform.android`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add package_info_plus`
Expected: `pubspec.yaml` gains it and `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test**

```dart
// test/utils/feedback_diagnostics_test.dart
test('describes common user agents coarsely', () {
  expect(
    describeUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
    ),
    'Chrome / macOS',
  );
  expect(
    describeUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 '
        'Safari/604.1'),
    'Safari / iOS',
  );
  expect(describeUserAgent(null), 'unknown');
  expect(describeUserAgent('curl/8.0'), 'unknown');
});

test('summary joins the four visible fields with a middle dot', () {
  const d = FeedbackDiagnostics(
    appVersion: '2.0.0+2',
    platform: 'android',
    osVersion: 'Android 14',
    screen: 'Settings',
    locale: 'en',
  );
  expect(d.summary, 'Muzician 2.0.0+2 · Android 14 · Settings · en');
  expect(
    d.toMap().keys,
    containsAll(<String>[
      'appVersion', 'platform', 'osVersion', 'screen', 'locale',
    ]),
  );
});

test('availability is on for web and android only', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  expect(isFeedbackAvailable, isFalse);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  expect(isFeedbackAvailable, isTrue);
});
```

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/utils/feedback_diagnostics_test.dart`
Expected: FAIL — `describeUserAgent` is not defined.

- [ ] **Step 4: Implement**

`feedback_user_agent.dart` imports the stub with `if (dart.library.js_interop)` the web file (the repo already splits platform code this way, see `lib/utils/note_player_web.dart`); `currentUserAgent()` returns `String?`.

`describeUserAgent` classifies browser first — Edge, Chrome, Firefox, Safari (when `Version/` and `Safari/` appear without `Chrome/`) — then OS — iOS, Android, macOS, Windows, Linux. Both must resolve, else `unknown`; output is `<Browser> / <OS>`.

`captureDiagnostics`: `platform` is `web` when `kIsWeb` else `defaultTargetPlatform.name`; `osVersion` is `describeUserAgent(currentUserAgent())` on web, else `Platform.operatingSystemVersion` trimmed to its first two tokens (`Android 14`); `appVersion` is `'${info.version}+${info.buildNumber}'` from `PackageInfo.fromPlatform()`, `unknown` on any error; `locale` is `PlatformDispatcher.instance.locale.languageCode`.

`isFeedbackAvailable` uses `defaultTargetPlatform`, never `dart:io`, so web builds compile.

- [ ] **Step 5: Run the test**

Run: `flutter test test/utils/feedback_diagnostics_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/utils/feedback_diagnostics.dart lib/utils/feedback_user_agent*.dart test/utils/feedback_diagnostics_test.dart
git commit -m "feat: collect feedback diagnostics"
```

---

### Task 2: Entry model and validation

**Files:**
- Create: `lib/models/feedback_entry.dart`
- Test: `test/models/feedback_entry_test.dart`

**Interfaces:**
- Consumes: `FeedbackDiagnostics`.
- Produces:
  - `enum FeedbackCategory { bug, idea, confusing, other }` with `String get wireName`.
  - `class FeedbackEntry { const FeedbackEntry({required String docId, required String sessionId, required String message, required FeedbackCategory category, required String contact, required FeedbackDiagnostics diagnostics, required int attempt}); Map<String, Object?> toMap(); FeedbackEntry copyWith({...}); static String? validateMessage(String raw); static String? validateContact(String raw); static const int maxMessageLength = 4000; static const int maxContactLength = 200; }`
  - `int countRunes(String value)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/models/feedback_entry_test.dart
final diagnostics = const FeedbackDiagnostics(
  appVersion: '2.0.0+2',
  platform: 'web',
  osVersion: 'Chrome / macOS',
  screen: 'Settings',
  locale: 'en',
);

FeedbackEntry entry({int attempt = 1, String message = 'hello'}) => FeedbackEntry(
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/models/feedback_entry_test.dart`
Expected: FAIL — `FeedbackEntry` is not defined.

- [ ] **Step 3: Implement `lib/models/feedback_entry.dart`**

`toMap()` returns exactly: `schemaVersion: 1`, `message` (trimmed), `category` (wire name), `contact` (trimmed), `clientSessionId`, plus the five keys from `diagnostics.toMap()`. Validators return `null` when valid, `'Write a message first.'` / `'That email is too long.'` when not, and count runes.

- [ ] **Step 4: Run the test**

Run: `flutter test test/models/feedback_entry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/feedback_entry.dart test/models/feedback_entry_test.dart
git commit -m "feat: add feedback entry model"
```

---

### Task 3: Firebase project, rules, and the writer

**Files:**
- Create: `firestore.rules`
- Create: `lib/firebase_options.dart`, `android/app/google-services.json` (generated)
- Create: `lib/utils/feedback_doc_writer.dart`
- Modify: `firebase.json`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, Android Gradle files

**Interfaces:**
- Consumes: nothing.
- Produces: `abstract interface class FeedbackDocWriter { Future<void> create(String docId, Map<String, Object?> fields); }` and `class FirestoreDocWriter implements FeedbackDocWriter { const FirestoreDocWriter(); }`.

- [ ] **Step 1: Enable Firestore**

Run: `firebase firestore:databases:create default --location=eur3 --project muzician-b0953`
Expected: a database in `eur3`, confirmed by
`firebase firestore:databases:list --project muzician-b0953`.
If it answers 403 (API not enabled) and the CLI cannot enable it, stop and hand the owner the console link — do not work around it.

- [ ] **Step 2: Generate the FlutterFire config**

Run: `dart pub global activate flutterfire_cli`, then
`flutterfire configure --project=muzician-b0953 --platforms=web,android --out=lib/firebase_options.dart --yes`
Expected: `lib/firebase_options.dart`, `android/app/google-services.json`, Gradle plugin wiring.

- [ ] **Step 3: Add dependencies and the Android permission**

Run: `flutter pub add firebase_core cloud_firestore`
Add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml`.

- [ ] **Step 4: Write `firestore.rules`**

The deployed file is `firestore.rules`; it is the source of truth.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /feedback/{docId} {
      allow create: if docId.matches('^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        && request.resource.data.keys().hasOnly([
          'schemaVersion','message','category','contact','appVersion',
          'platform','osVersion','screen','locale','createdAt',
          'clientSessionId'])
        && request.resource.data.keys().hasAll([
          'schemaVersion','message','category','contact','appVersion',
          'platform','osVersion','screen','locale','createdAt',
          'clientSessionId'])
        && request.resource.data.schemaVersion == 1
        && request.resource.data.message is string
        && request.resource.data.message.size() > 0
        && request.resource.data.message.size() <= 16000
        && request.resource.data.category in ['bug','idea','confusing','other']
        && request.resource.data.contact is string
        && request.resource.data.contact.size() <= 800
        && request.resource.data.platform in ['web','android']
        && request.resource.data.appVersion is string
        && request.resource.data.appVersion.size() <= 120
        && request.resource.data.osVersion is string
        && request.resource.data.osVersion.size() <= 120
        && request.resource.data.screen is string
        && request.resource.data.screen.size() <= 120
        && request.resource.data.locale is string
        && request.resource.data.locale.size() <= 120
        && request.resource.data.clientSessionId is string
        && request.resource.data.clientSessionId.size() <= 40
        && request.resource.data.createdAt == request.time;
      allow read, update, delete: if false;
    }
  }
}
```

- [ ] **Step 5: Deploy the rules**

Add `"firestore": { "rules": "firestore.rules" }` to `firebase.json`, then
`firebase deploy --only firestore:rules --project muzician-b0953`.
Expected: `Deploy complete!`

- [ ] **Step 6: Implement `lib/utils/feedback_doc_writer.dart`**

`FirestoreDocWriter.create` initializes Firebase on first use (`if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`) and writes `FirebaseFirestore.instance.collection('feedback').doc(docId).set(fields)`.

- [ ] **Step 7: Verify the wiring compiles**

Run: `flutter analyze`
Expected: no issues. The first real write is exercised at the end of Task 6.

- [ ] **Step 8: Commit**

```bash
git add firebase.json firestore.rules lib/utils/feedback_doc_writer.dart lib/firebase_options.dart pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml android/app/google-services.json android/build.gradle.kts android/settings.gradle.kts android/app/build.gradle.kts
git commit -m "feat: wire firebase and feedback collection rules"
```

---

### Task 4: Service and error mapping

**Files:**
- Create: `lib/utils/feedback_service.dart`
- Create: `test/support/fake_feedback_service.dart` (shared by Tasks 5 and 6)
- Test: `test/utils/feedback_service_test.dart`

**Interfaces:**
- Consumes: `FeedbackEntry`, `FeedbackDocWriter`.
- Produces:
  - `enum FeedbackSendFailure { alreadyRecorded, rejected, unreachable, unknown }`
  - `class FeedbackSendException implements Exception { const FeedbackSendException(this.failure); final FeedbackSendFailure failure; }`
  - `abstract interface class FeedbackService { Future<void> send(FeedbackEntry entry); }`
  - `class FirestoreFeedbackService implements FeedbackService { const FirestoreFeedbackService(this.writer); final FeedbackDocWriter writer; }`
  - `class FakeFeedbackService implements FeedbackService` with `final List<FeedbackEntry> attempts`, `List<FeedbackEntry> get sent`, `int failing`, `bool hang`, `FeedbackSendFailure failure`, and a named constructor `FakeFeedbackService({this.failing = 0, this.hang = false, this.failure = FeedbackSendFailure.unreachable})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/utils/feedback_service_test.dart
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

test('passes the client document id and adds a server timestamp', () async {
  final writer = _Writer(() async {});
  await FirestoreFeedbackService(writer).send(entry(attempt: 1));
  expect(writer.docId, 'doc-1');
  expect(writer.fields!['createdAt'], isA<FieldValue>());
  expect(writer.fields!['message'], 'hello');
});

test('permission_denied on a retry means the document already landed', () async {
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
});

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
      () async => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
      ),
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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/utils/feedback_service_test.dart`
Expected: FAIL — `FirestoreFeedbackService` is not defined.

- [ ] **Step 3: Implement the service and the shared fake**

`send` calls `writer.create(entry.docId, {...entry.toMap(), 'createdAt': FieldValue.serverTimestamp()})` and maps `FirebaseException` exactly as the tests require; anything else is `unknown`.

`FakeFeedbackService`: records every entry in `attempts`; the first `failing` calls throw `FeedbackSendException(FeedbackSendFailure.unreachable)`; with `hang`, the call never completes. `sent` returns the entries that succeeded.

- [ ] **Step 4: Run the test**

Run: `flutter test test/utils/feedback_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/feedback_service.dart test/support/fake_feedback_service.dart test/utils/feedback_service_test.dart
git commit -m "feat: add firestore feedback service"
```

---

### Task 5: Draft store

**Files:**
- Create: `lib/store/feedback_store.dart`
- Modify: `lib/store/app_bootstrap.dart`
- Test: `test/store/feedback_store_test.dart`

**Interfaces:**
- Consumes: entry, diagnostics, service, fake.
- Produces:
  - `enum FeedbackStatus { idle, sending, pending, sent, failed }`
  - `class FeedbackState { const FeedbackState({...}); final String sessionId; final String message; final FeedbackCategory category; final String contact; final String? docId; final int attempt; final FeedbackDiagnostics? diagnostics; final FeedbackStatus status; final String? error; final DateTime? lastSentAt; final String lastSentMessage; bool get hasDraft; }`
  - `class FeedbackNotifier extends Notifier<FeedbackState> { Future<void> hydrate(); Future<void> setMessage(String value); Future<void> setCategory(FeedbackCategory value); Future<void> setContact(String value); Future<void> attachDiagnostics(FeedbackDiagnostics value); Future<void> send(); }`
  - `final feedbackProvider = NotifierProvider<FeedbackNotifier, FeedbackState>(FeedbackNotifier.new);`
  - `final feedbackServiceProvider = Provider<FeedbackService>((ref) => const FirestoreFeedbackService(FirestoreDocWriter()));`
  - `final feedbackClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);`
  - `final feedbackSendTimeoutProvider = Provider<Duration>((ref) => const Duration(seconds: 8));`
  - `const feedbackDraftStorageKey = '@muzician/feedback_draft/v1';`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/feedback_store_test.dart
ProviderContainer containerWith(
  FakeFeedbackService service, {
  DateTime Function()? clock,
  Duration timeout = const Duration(seconds: 8),
}) => ProviderContainer(
  overrides: [
    feedbackServiceProvider.overrideWithValue(service),
    if (clock != null) feedbackClockProvider.overrideWithValue(clock),
    feedbackSendTimeoutProvider.overrideWithValue(timeout),
  ],
);

Future<FeedbackNotifier> loaded(ProviderContainer c) async {
  final n = c.read(feedbackProvider.notifier);
  await n.hydrate();
  return n;
}

test('sends, clears the draft, and records the send time', () async {
  SharedPreferences.setMockInitialValues({});
  final service = FakeFeedbackService();
  final c = containerWith(service);
  addTearDown(c.dispose);
  final n = await loaded(c);
  await n.setMessage('crashes on open');
  await n.setCategory(FeedbackCategory.bug);
  await n.send();
  expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
  expect(c.read(feedbackProvider).message, '');
  expect(service.sent.single.docId, isNotEmpty);
});

test('a failed send keeps the text, the docId, and bumps attempt', () async {
  SharedPreferences.setMockInitialValues({});
  final service = FakeFeedbackService(failing: 1);
  final c = containerWith(service);
  addTearDown(c.dispose);
  final n = await loaded(c);
  await n.setMessage('hello');
  await n.send();
  expect(c.read(feedbackProvider).status, FeedbackStatus.failed);
  expect(c.read(feedbackProvider).message, 'hello');
  await n.send();
  expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
  expect(service.attempts.map((e) => e.docId).toSet(), hasLength(1));
  expect(service.attempts.map((e) => e.attempt), [1, 2]);
});

test('a timeout leaves the text pending, not failed', () async {
  SharedPreferences.setMockInitialValues({});
  final c = containerWith(
    FakeFeedbackService(hang: true),
    timeout: const Duration(milliseconds: 20),
  );
  addTearDown(c.dispose);
  final n = await loaded(c);
  await n.setMessage('offline');
  await n.send();
  expect(c.read(feedbackProvider).status, FeedbackStatus.pending);
  expect(c.read(feedbackProvider).message, 'offline');
});

test('alreadyRecorded from a retry counts as sent', () async {
  SharedPreferences.setMockInitialValues({});
  final c = containerWith(
    FakeFeedbackService(failing: 1, failure: FeedbackSendFailure.alreadyRecorded),
  );
  addTearDown(c.dispose);
  final n = await loaded(c);
  await n.setMessage('landed twice');
  await n.send();                 // failed: permission-denied on attempt 1 -> rejected
  await n.send();                 // retry: alreadyRecorded -> success
  expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
});

test('the draft and its docId survive a new container', () async {
  SharedPreferences.setMockInitialValues({});
  final a = containerWith(FakeFeedbackService());
  await (await loaded(a)).setMessage('restored');
  a.dispose();
  final b = containerWith(FakeFeedbackService());
  addTearDown(b.dispose);
  await loaded(b);
  expect(b.read(feedbackProvider).message, 'restored');
  expect(b.read(feedbackProvider).docId, isNotNull);
});

test('cooldown blocks a repeat send for 60s but never a retry', () async {
  SharedPreferences.setMockInitialValues({});
  var now = DateTime(2026, 11, 8, 12);
  final service = FakeFeedbackService(failing: 1);
  final c = containerWith(service, clock: () => now);
  addTearDown(c.dispose);
  final n = await loaded(c);
  await n.setMessage('same words');
  await n.send();                 // fails, no cooldown
  await n.send();                 // retry, succeeds
  expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
  await n.setMessage('same words');
  await n.send();                 // blocked
  expect(service.attempts, hasLength(2));
  now = now.add(const Duration(seconds: 61));
  await n.send();
  expect(service.attempts, hasLength(3));
});

test('an empty message never reaches the service', () async {
  SharedPreferences.setMockInitialValues({});
  final service = FakeFeedbackService();
  final c = containerWith(service);
  addTearDown(c.dispose);
  final n = await loaded(c);
  await n.send();
  expect(service.attempts, isEmpty);
  expect(c.read(feedbackProvider).error, 'Write a message first.');
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/store/feedback_store_test.dart`
Expected: FAIL — `feedbackProvider` is not defined.

- [ ] **Step 3: Implement `lib/store/feedback_store.dart`**

`build()` returns `FeedbackState(sessionId: const Uuid().v4())`. `send()`: validate the message; skip while `sending`; skip when `sent` and the same text was sent under 60 s ago; otherwise `docId ??= const Uuid().v4()`, `attempt + 1`, status `sending`, then `service.send(entry).timeout(timeout)`. Success clears message, contact, error, `docId` and `attempt` — a resend must never reuse a document ID that already landed — and clears the stored draft. `TimeoutException` sets `pending` with *Still trying… your text is saved.* `alreadyRecorded` is treated as success. Anything else is `failed` with *Couldn't send. Your text is saved — try again.* Every mutation persists `{message, category, contact, docId, attempt, lastSentAt, lastSentMessage}`; `hydrate()` restores it and generates a fresh `sessionId`. If `FakeFeedbackService` from Task 4 still throws only `unreachable`, add the `failure` parameter described in this task's Interfaces before writing the tests.

- [ ] **Step 4: Run the test**

Run: `flutter test test/store/feedback_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Hydrate at startup**

Add `await read(feedbackProvider.notifier).hydrate();` after the settings hydration in `hydrateStores`, plus the import. Run `flutter test test/store/app_bootstrap_startup_test.dart` — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/store/feedback_store.dart lib/store/app_bootstrap.dart test/store/feedback_store_test.dart
git commit -m "feat: add feedback draft store"
```

---

### Task 6: Sheet and Settings entry

**Files:**
- Create: `lib/ui/core/feedback_sheet.dart`
- Modify: `lib/main.dart` (`_SettingsScreen`, after `const DataRecoveryPanel()`)
- Test: `test/ui/core/feedback_sheet_test.dart`

**Interfaces:**
- Consumes: the store, the service provider, the fake.
- Produces: `class FeedbackSheet extends ConsumerStatefulWidget { static Future<void> show(BuildContext context); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/core/feedback_sheet_test.dart
Future<void> pumpSheet(WidgetTester tester, FakeFeedbackService service) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: [feedbackServiceProvider.overrideWithValue(service)],
      ),
      child: const MaterialApp(home: Scaffold(body: FeedbackSheet())),
    ),
  );
  await tester.pumpAndSettle();
}

testWidgets('cannot send an empty message', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await pumpSheet(tester, FakeFeedbackService());
  await tester.tap(find.byKey(const ValueKey('feedback_send')));
  await tester.pumpAndSettle();
  expect(find.textContaining('Write a message'), findsOneWidget);
});

testWidgets('sends the typed message with its category', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final service = FakeFeedbackService();
  await pumpSheet(tester, service);
  await tester.enterText(find.byKey(const ValueKey('feedback_message')), 'bug!');
  await tester.tap(find.byKey(const ValueKey('feedback_category_confusing')));
  await tester.tap(find.byKey(const ValueKey('feedback_send')));
  await tester.pumpAndSettle();
  expect(service.sent.single.message, 'bug!');
  expect(service.sent.single.category, FeedbackCategory.confusing);
});

testWidgets('a failure keeps the text and offers Retry and Copy', (
  tester,
) async {
  SharedPreferences.setMockInitialValues({});
  await pumpSheet(tester, FakeFeedbackService(failing: 1));
  await tester.enterText(find.byKey(const ValueKey('feedback_message')), 'oops');
  await tester.tap(find.byKey(const ValueKey('feedback_send')));
  await tester.pumpAndSettle();
  expect(find.text('oops'), findsOneWidget);
  expect(find.byKey(const ValueKey('feedback_retry')), findsOneWidget);
  expect(find.byKey(const ValueKey('feedback_copy')), findsOneWidget);
});

testWidgets('scrolls with the keyboard open on a 320x568 screen', (
  tester,
) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpSheet(tester, FakeFeedbackService());
  await tester.enterText(
    find.byKey(const ValueKey('feedback_message')),
    'x' * 400,
  );
  tester.view.viewInsets = const FakeViewPadding(bottom: 280);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('feedback_send')));
  expect(find.byKey(const ValueKey('feedback_send')), findsOneWidget);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/ui/core/feedback_sheet_test.dart`
Expected: FAIL — `FeedbackSheet` is not defined.

- [ ] **Step 3: Implement the sheet**

`initState` calls `captureDiagnostics(screen: 'Settings')` and `attachDiagnostics`. Body: `SingleChildScrollView` in `SafeArea`; category `ChoiceChip`s keyed `feedback_category_<wireName>`; message `TextField` keyed `feedback_message` with `maxLength: FeedbackEntry.maxMessageLength` and `MaxLengthEnforcement.enforced`, disabled while `sending`; contact `TextField` keyed `feedback_contact`; an `ExpansionTile` keyed `feedback_what_is_sent` holding the full policy text and `diagnostics?.summary`; a `Copy` text button keyed `feedback_copy` whenever `hasDraft`, writing `'${state.message}\n\n${state.diagnostics?.summary ?? ''}'`; and one primary button whose key is `feedback_retry` when `hasDraft && (failed || pending)`, `feedback_send` when `hasDraft`, `feedback_sent` when the previous send succeeded and no draft remains — disabled while `sending`. Close the sheet only when `await send()` returns `true` (a send can succeed while a draft typed mid-flight remains, so `status` alone cannot decide this); show `showGlassSnackbar(contentType: ContentType.success)` on the way out. `pending` keeps the sheet open with its copy; `failed` shows the store's error inline.

- [ ] **Step 4: Add the Settings entry**

After `const DataRecoveryPanel()`, `if (isFeedbackAvailable)` insert a `_SettingsGroup` with a `ListTile` keyed `settings_send_feedback`, icon `Icons.feedback_outlined`, title *Send feedback*, subtitle `state.hasDraft ? 'Draft saved' : 'Bugs, ideas, anything confusing'`, `onTap: () => FeedbackSheet.show(context)`.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/ui/core/feedback_sheet_test.dart test/main_navigation_rail_test.dart`
Expected: PASS, and Settings still renders in both themes.

- [ ] **Step 6: Verify the whole path by hand**

`flutter run -d chrome`: Settings → Send feedback → send. Expected: the document appears in the Firestore console with every field, the sheet closes with the success snackbar, and a relaunch shows no draft. Then `flutter build apk --release` and confirm the merged manifest contains `INTERNET`.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/core/feedback_sheet.dart lib/main.dart test/ui/core/feedback_sheet_test.dart
git commit -m "feat: add feedback sheet to settings"
```

---

### Task 7: Docs, privacy page, and the Reddit post

**Files:**
- Create: `docs/feedback.md`, `web/privacy.html`
- Modify: `README.md`, `AGENTS.md`, the design doc

- [ ] **Step 1: Write `docs/feedback.md`**

Where the entry lives, the exact fields sent, the draft/retry behaviour, the 60 s cooldown, where to read feedback (Firestore console, `feedback` collection), how to answer a deletion request, and the Data safety answers from the spec.

- [ ] **Step 2: Write `web/privacy.html`**

Static page, same text as the sheet's expandable, contact `bytebakehouseinc@gmail.com`. Confirm `/privacy` is served after `flutter build web` despite the SPA rewrite.

- [ ] **Step 3: Update README, AGENTS and the design doc**

README: a **Feedback** row in the feature table and a mention in the Settings row. AGENTS: *The feedback sheet is the only outbound write; it sends the message, an optional contact address and diagnostics, never project content.* Design doc: replace the "Open with the owner" section with the resolved address and setup ownership.

- [ ] **Step 4: Fix the Reddit post wording**

Replace *Everything stays on your device. No account, no cloud, no analytics.* with *Your projects stay on your device — no account, no cloud sync, no analytics. The only thing that ever leaves is a feedback message you choose to send.*

- [ ] **Step 5: Verify and commit**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: clean analyze, all tests pass.

```bash
git add docs/feedback.md web/privacy.html README.md AGENTS.md docs/superpowers/specs/2026-11-08-feedback-capture-design.md
git commit -m "docs: document feedback capture and privacy"
```
