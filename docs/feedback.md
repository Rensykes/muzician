# In-App Feedback

Muzician has one outbound write: a feedback message a tester chooses to send
from Settings. Everything else — projects, saves, lyrics, note content and
audio — stays on the device. This guide covers the entry point, the exact
payload, the draft and retry behaviour, where to read submissions, and the
Play Console answers that depend on it.

## Entry point

**Settings → Send feedback** (`settings_send_feedback`), inside its own
Feedback group. The row's subtitle reads *Bugs, ideas, anything confusing*,
or *Draft saved* when an unsent draft is waiting.

The entry appears only where Firebase is configured: web and Android.
`isFeedbackAvailable` in `lib/utils/feedback_diagnostics.dart` gates it, so
iOS, macOS, Windows and Linux do not show the row until those platforms are
wired to a Firebase app.

The sheet opens from the current workspace and stays inside the app. It shows
four category chips — **Bug** (default), **Idea**, **Confusing**, **Other** —
a required message field capped at 4000 characters (counted in runes), an optional email field,
and a collapsed **What gets sent** section containing the same privacy text
as `/privacy`. **Copy** puts the message and the diagnostics line on the
clipboard so a tester can rescue their text offline, even before a send
succeeds.

## Fields sent

One Firestore document per submission, in collection `feedback`. The document
ID is a uuid v4 generated on the device and reused by every retry, so a retry
can never create a duplicate.

| Field | Example | Notes |
|---|---|---|
| `schemaVersion` | `1` | Payload version; rules require exactly `1` |
| `message` | `Chords vanish when I…` | Trimmed; 1–4000 runes on the client |
| `category` | `bug` | One of `bug`, `idea`, `confusing`, `other` |
| `contact` | `name@example.com` | Optional; `''` when omitted; 0–200 runes |
| `appVersion` | `2.0.0+2` | From `package_info_plus`; `unknown` on failure |
| `platform` | `web` or `android` | Coarse platform name |
| `osVersion` | `Chrome / macOS` | Coarse user agent on web; trimmed `Platform.operatingSystemVersion` on Android (`Android 14`); `unknown` when unclassifiable |
| `screen` | `Settings` | Call-site label |
| `locale` | `en`, `it` | Device language code |
| `createdAt` | server timestamp | Set by Firestore; rules require `request.time` |
| `clientSessionId` | uuid v4 | Regenerated on every app launch; used only to spot repeated sends, never to identify a person; not persisted |

There is no device model, advertising ID, install identifier, account, or
persistent user ID. Firestore itself logs request metadata such as the source
IP, as any hosted service does; the app does not read or store it in the
document.

What is never sent: project names, keys, chords, notes, lyrics, Writer
sections, Save System entries, audio recordings, file names, or anything else
from the workspace.

`appVersion` is the version string from `pubspec.yaml`; the current release
is `2.0.0+2`.

## Drafts, retries and the cooldown

- **Draft persistence.** Every edit is written to `shared_preferences` under
  `@muzician/feedback_draft/v1` as `{message, category, contact, docId,
  attempt, possiblyWritten, lastSentAt, lastSentMessage}`. It survives a
  relaunch and is restored by `hydrate()` at startup. The sheet never
  auto-opens; the Settings tile shows *Draft saved* instead.
- **One document per draft.** The first edit mints a uuid v4, and every send
  or retry of that draft targets the same document. The id is cleared only
  after a successful send, so a later message always gets a new document.
- **Success clears the draft.** The message and contact are cleared only when
  the write is acknowledged. A `permission-denied` on a retry also counts as
  success, but only when the draft records `possiblyWritten`: the previous
  attempt timed out or failed as unreachable, so its write may have reached
  the server (the rules allow `create` only). A retry after a rejected
  payload, misdeployed rules or a future rules tightening clears
  `possiblyWritten`, so its denial stays a failure and the text is kept. Text
  typed while a send was in flight is kept, not discarded.
- **Failure keeps the text.** A rejected or unreachable send leaves the
  draft, its document ID and the attempt counter intact, and offers **Retry**
  plus **Copy**. The store recomputes `possiblyWritten` from the failure:
  `true` after a timeout or an unreachable error, `false` after a rejection.
  Editing the message or contact after a possibly-written attempt mints a new
  document and clears `possiblyWritten`, so the edited text is its own
  submission and a denial aimed at the old document cannot clear it.
- **Pending after 8 seconds.** A write still unanswered after 8 s switches to
  *Still trying… your text is saved.* with **Retry** and **Copy**, instead of
  an endless spinner. Retry reuses the document ID, so a write the SDK later
  replays from its own queue cannot produce a second document.
- **60-second cooldown.** After a *successful* send, the same trimmed message
  is held back for 60 s (`feedbackSendCooldown`) and the sheet says *You just
  sent this — give it a minute.* Failed and pending sends never record a send
  time, so a Retry is never inside the cooldown window; recovery after a bad
  connection is the main path. A clock that moves backwards does not block a
  resend.
- **Offline.** Firestore is initialized lazily when the feedback sheet opens
  (a warm-up that keeps the 8 s send deadline for the write itself), never at
  app launch, so startup never depends on the network. In airplane mode the
  text is saved and can be copied out; Retry works once connectivity returns.

## Reading feedback

Open the Firebase console for the project:

<https://console.firebase.google.com/project/muzician-b0953/firestore/data>

- Project `muzician-b0953`, database `(default)`, location `eur3`
  (Europe multi-region; permanent once provisioned).
- Collection `feedback`, one document per submission.
- Sort by `createdAt` descending to read the newest first. Each document
  carries the fields above.

The rules in `firestore.rules` allow `create` only; clients cannot read,
update or delete. The console, authenticated as the project owner, is
unaffected.

Deploy rules after editing them:

```bash
firebase deploy --only firestore:rules --project muzician-b0953
```

### Answering a deletion request

A tester can ask for their feedback to be removed by writing to
`bytebakehouseinc@gmail.com` (the address is on `/privacy` and in the sheet).
To action it:

1. Find the document(s) in the console, using the contact address, the
   message text, or the approximate `createdAt` the tester mentions. There is
   no other identifier to search by.
2. Delete the document in the console. Deletion is immediate and permanent.
3. Reply to the tester to confirm, and say if you could not find a matching
   submission.

No separate retention job exists: feedback is kept until it is deleted on
request.

## Setup and build notes

- Firestore `(default)` exists on `muzician-b0953` in `eur3`. FlutterFire
  generated `lib/firebase_options.dart`, `android/app/google-services.json`
  and the Android Gradle wiring for web and Android.
- The Android release manifest needs `android.permission.INTERNET`; it is
  present in `android/app/src/main/AndroidManifest.xml`. Without it a release
  build cannot reach Firestore.
- **Run `flutter clean` after adding or upgrading Firebase dependencies,
  before `flutter build web`.** Otherwise the generated
  `web_plugin_registrant.dart` can be stale (for example `firebase_core_web`
  missing from it), and the first send fails with
  `PlatformException(channel-error, … FirebaseCoreHostApi.initializeCore)`.
  A clean rebuild regenerates the registrant.
- `lib/firebase_options.dart` contains a GA4 `measurementId` emitted by the
  Firebase tooling. No analytics package is used (`firebase_analytics`,
  `google_analytics` and similar are absent from `pubspec.yaml`), and nothing
  in the app sends analytics events or screen views. The id is config, not
  instrumentation.
- The privacy page is `web/privacy.html`, served at `/privacy`. `firebase.json`
  has an explicit `/privacy → /privacy.html` rewrite ahead of the SPA
  catch-all so the policy is not swallowed by `index.html`.
- Client and rules ceilings differ on purpose: the client caps the message at
  4000 runes and the contact at 200 runes, while the rules cap the stored
  strings at 16000 and 800 bytes. Firestore rules `size()` counts UTF-8
  bytes, and a rune can occupy up to 4 bytes, so the larger ceiling keeps an
  all-emoji message that the client accepts from being rejected on the
  server.

## Play Console answers

### Data safety

| Question | Answer |
|---|---|
| Does your app collect or share user data? | Yes — only feedback the user chooses to send |
| Data type: **Messages** | Collected; optional (only when the tester sends feedback); purpose **App functionality** and **Developer communications**; not shared; encrypted in transit; users can request deletion; deleted on request |
| Data type: **Email address** | Collected; optional (only when the tester types one for a reply); purpose **Developer communications** (and app functionality for replying); not shared; encrypted in transit; deleted on request |
| Other data types | Not collected — no location, contacts, persistent identifiers, usage or diagnostics beyond the coarse app/device fields above, and no advertising ID |
| Is data encrypted in transit? | Yes (HTTPS to Firestore) |
| Can users request data deletion? | Yes — email `bytebakehouseinc@gmail.com`; the submission is deleted from the console |
| Is data shared with third parties? | No. Google Firestore is a data processor for storage, not a sharing recipient |

### "How did you collect feedback?" (closed test)

The Play closed-testing questionnaire asks how feedback was gathered. Answer:

> In-app feedback form. Testers open Settings → Send feedback, choose a
> category, write a message and optionally leave an email for a reply. The
> form submits to a private Cloud Firestore collection owned by the developer;
> there is no third-party survey, no analytics SDK and no public review
> channel. App version, platform, coarse OS version, screen and language are
> attached automatically. Submissions are read in the Firebase console and
> deleted on request.

Point to this document and to `/privacy` if a reviewer asks for detail.
