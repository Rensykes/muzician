# In-App Feedback Capture — Design

## Problem

Testers recruited on Reddit currently have two ways to reach the developer:
a Reddit DM or the email address used to add them to the Play closed test.
Both lose the context needed to act: nobody writes "Android 14, app 2.0.0+2,
Settings screen, and by the way the sheet is 3px tall". The test window is
short (Play requires 12 testers opted in for 14 continuous days), so the
first weeks of feedback are the most valuable ones to capture well.

## Intent

A tester presses **Settings → Send feedback**, types a message, optionally
leaves an email for a reply, and presses Send. The message lands in a
Firestore collection the developer reads in the Firebase console, with the
app version, platform, OS version and screen attached. Nothing about the
user's projects, lyrics or saves is ever sent.

## Approaches considered

| Approach | What it gives | Why not |
|---|---|---|
| **mailto + "copy details"** | Free-form replies in the inbox; no backend | Depends on a configured mail client; free-form means no structure and no automatic context |
| **Hosted form** (Tally / Google Forms) | Structured answers, dashboard, no backend code | Leaves the app; a second service to own; can't attach device context automatically without clipboard gymnastics |
| **In-app form → Firestore** (chosen) | In-app sending, automatic context, structured fields, evidence of tester engagement | Adds the app's first network dependency, a privacy/data-safety obligation, and an anonymous-write spam surface |
| Telemetry (Sentry / GA4) | Whether anyone opens the app, what crashes | Different axis; breaks the "no analytics" promise. Deferred |

The owner chose Firestore. It is the only option that keeps the testers
inside the app and attaches context for free. The cost is accepted
knowingly: this is the one outbound path in an otherwise offline app, and it
must be visible and opt-in in the UI, not silent.

## Goals

1. A tester can send a message in three taps plus typing, from Settings, on
   web and Android.
2. The message carries version, platform, OS, screen and locale automatically.
3. No musical content, project names, save data, or identifiers leave the
   device. A persistent install identifier is explicitly not collected.
4. A failed send never loses the text.
5. The developer reads feedback in the Firebase console without any admin UI.

## Non-goals

- No in-app inbox, thread, or reply channel.
- No usage analytics, crash reporting, or session tracking of any kind.
- No accounts, sign-in, or user identity.
- No iOS, macOS, Windows or Linux configuration in this phase. Those
  platforms ship later; FlutterFire config is added then.
- No Cloud Functions, no email notification on new feedback (Spark plan).

## Current state

- The app is local-only: `shared_preferences` persistence, no network calls,
  no `firebase_*` packages, no auth.
- `firebase.json` is static hosting for `build/web` on project
  `muzician-b0953` (`muzician.bytebakehouseinc.xyz`).
- Firestore API is **not enabled** on that project and no database exists.
- `android/app/src/main/AndroidManifest.xml` has no `INTERNET` permission
  (only the debug and profile manifests do), so a release build cannot reach
  the network today.
- Settings is `_SettingsScreen` in `lib/main.dart:1134`, built from
  `_SettingsGroup` sections.

## User flow

Settings gains a **Feedback** group with one `ListTile`: *Send feedback*,
subtitle *Bugs, ideas, anything confusing*. It opens a modal sheet:

```
┌───────────────────────────────────────────┐
│ Send feedback                         ✕   │
│                                           │
│ [ Bug ] [ Idea ] [ Confusing ] [ Other ]  │  ← single choice, Bug preselected
│                                           │
│ ┌───────────────────────────────────────┐ │
│ │ What happened?                        │ │  ← required, 4000 char cap
│ │                                       │ │
│ └───────────────────────────────────────┘ │
│                                           │
│ Email, if you'd like a reply (optional)   │
│ ┌───────────────────────────────────────┐ │
│ └───────────────────────────────────────┘ │
│                                           │
│ ▸ What gets sent                          │  ← collapsed by default
│   Muzician 2.0.0+2 · Android 14 ·         │
│   Settings · en                           │
│   Only this message and these details.    │
│   Your projects never leave your device.  │
│                                           │
│                        [   Send   ]       │
└───────────────────────────────────────────┘
```

States: `idle` → `sending` (button disabled, spinner) → `sent` (sheet
closes, success snackbar) or `failed` (inline error *Couldn't send. Your
text is saved — try again.*, button becomes **Retry**, plus **Copy** which
copies the message and the detail block to the clipboard).

The draft is persisted (debounced, ~500 ms) as soon as the tester types, and
cleared only after a successful send.

## Data

Collection `feedback`, one document per submission. **The document ID is a
uuid v4 generated on the device** and stored with the draft, so a retry —
including one after the app was killed mid-write and the SDK replayed its
queued write — targets the same document and can never produce a duplicate.
A `uid already exists` error is treated as success.

| Field | Type | Rule |
|---|---|---|
| *(document ID)* | string | uuid v4, client-generated, 36 chars |
| `schemaVersion` | int | must be `1` |
| `message` | string | 1–4000 chars, trimmed |
| `category` | string | one of `bug`, `idea`, `confusing`, `other` |
| `contact` | string | 0–200 chars, `''` when omitted |
| `appVersion` | string | from `package_info_plus`, e.g. `2.0.0+2` |
| `platform` | string | `web` or `android` |
| `osVersion` | string | best effort, `unknown` fallback |
| `screen` | string | call-site label, e.g. `settings` |
| `locale` | string | e.g. `en` |
| `createdAt` | timestamp | must equal `request.time` |
| `clientSessionId` | string | uuid v4 regenerated on each app launch |

`osVersion`: on web parse the user agent into a coarse value (`Chrome 141 /
macOS`, `Safari / iOS 18`); on Android use `Platform.operatingSystemVersion`.
No device model, no advertising ID, no IP capture beyond what Firestore logs.

### Security rules

```
match /feedback/{docId} {
  allow create: if docId.matches('^[0-9a-fA-F-]{36}$')
    && request.resource.data.keys().hasOnly(
      ['schemaVersion','message','category','contact','appVersion',
       'platform','osVersion','screen','locale','createdAt','clientSessionId'])
    && request.resource.data.schemaVersion == 1
    && request.resource.data.message is string
    && request.resource.data.message.size() > 0
    && request.resource.data.message.size() <= 4000
    && request.resource.data.category in ['bug','idea','confusing','other']
    && request.resource.data.contact is string
    && request.resource.data.contact.size() <= 200
    && request.resource.data.createdAt == request.time
    && request.resource.data.clientSessionId is string
    && request.resource.data.clientSessionId.size() <= 40;
  allow read, update, delete: if false;
}
```

Client reads and writes to any other collection are denied. The console
(still authenticated as the owner) is unaffected.

## Spam and abuse

Without auth or App Check, anyone who reads the web bundle can write
documents. Accepted for a closed test, bounded by:

- the rules above (shape, size, enum, server timestamp, uuid document ID);
- a local cooldown of one **successful** send per 60 s, and no second send
  of byte-identical text inside that window. Failed attempts never start the
  cooldown, and **Retry always bypasses it** — recovery is the main path
  after a bad connection;
- monitoring the collection in the console; if it is abused, tighten the
  rules (temporarily deny all creates) while App Check is set up.

This is a courtesy guard against accidental double-taps, not a security
control: it lives in the draft record and carries no identifier.

App Check (reCAPTCHA Enterprise on web, Play Integrity on Android) is the
real fix and is deferred: it needs a Blaze plan, Play Console app signing
details and a new release. Revisit before public launch.

## Failure handling

- `send()` reports success when the write is acknowledged; only then is the
  draft cleared.
- A write still pending after 8 s switches the sheet to *Still trying…* with
  **Retry** and **Copy** enabled, instead of leaving a spinner with no exit.
  Retry reuses the same document ID, so it cannot duplicate an earlier write
  that the SDK later replays from its own queue.
- If the app is killed mid-send, the draft and its document ID are restored
  on the next launch. The Settings tile then reads *Send feedback · Draft
  saved* and the sheet prefills when opened; the sheet never auto-opens on
  launch.
- **Copy** is available whenever the message is non-empty, not just after a
  failure, so a tester on a broken connection can still get their text out.
- Firestore is initialized lazily on the first send, not at startup, so app
  launch never depends on the network.

## Privacy, Play and docs

- New public page `web/privacy.html` (served at `/privacy`), stating exactly
  what the form sends, that projects never leave the device, that there is
  no analytics, retention (until deleted on request) and the contact address.
  The same text, in full rather than a summary, is inside the sheet's
  expandable so the policy is readable in-app and offline.
- Play Console **Data safety**: *Messages* (optional) and *Email address*
  (optional) collected for app functionality and developer communication;
  not shared; encrypted in transit; deleted on request.
- README feature table and `docs/feedback.md` describe the entry point and
  what is sent.
- The Reddit post's "no account, no cloud, no analytics" line becomes
  inaccurate and must be replaced with: work stays on the device, and the
  only thing that ever leaves is a feedback message the tester chooses to
  send.

## Parts of the how

Already decided by the owner: Firestore over mailto / hosted form; in-app
sheet reached from Settings; no accounts; optional reply address; console as
the inbox.

Decided here, open to correction: category chips with `bug` preselected;
4000-character cap; draft persistence with a client-generated document ID
and idempotent retry; 8 s pending threshold; `package_info_plus` for the
version string; no `url_launcher` (the full policy text lives in the sheet,
the public page is for the Play listing); feedback entry visible only on web
and Android until other platforms are configured; Firestore in the `eur3`
multi-region, which is permanent once provisioned.

## Proposed structure

```
lib/models/feedback_entry.dart        immutable entry + toMap/fromDraft
lib/utils/feedback_diagnostics.dart   version/platform/os/screen collection,
                                      user-agent parsing, the detail block text
lib/utils/feedback_service.dart       abstract FeedbackService + Firestore impl
lib/store/feedback_store.dart         Riverpod Notifier: draft, status, send(),
                                      cooldown, restore-on-launch
lib/ui/core/feedback_sheet.dart       the sheet (Studio palette, keyboard-safe)
lib/main.dart                         Settings group + call site
db/firestore.rules                    rules; `firebase deploy --only firestore:rules`
```

Tests mirror `lib/`: `test/models/feedback_entry_test.dart`,
`test/utils/feedback_diagnostics_test.dart`,
`test/store/feedback_store_test.dart` (fake service: success clears the
draft, error keeps it, Retry reuses the document ID and creates one
document, cooldown blocks a second successful send but not a retry, restored
draft is prefilled), `test/ui/core/feedback_sheet_test.dart` (empty message
can't be sent, sent state, failure keeps text), and
`test/utils/feedback_service_test.dart` for the entry validation that rules
and client share.

## Set-up the owner must run

1. Enable Firestore (Native mode) on `muzician-b0953` in location `eur3`
   (Europe multi-region). Permanent once created.
2. `flutterfire configure --platforms=web,android` to generate
   `lib/firebase_options.dart`, `android/app/google-services.json`, and the
   Gradle plugin wiring.
3. Add the privacy policy URL to the Play listing and complete Data safety.

Steps 1–2 need the owner's Google account; the CLI is already logged in as
`bytebakehouseinc@gmail.com`.

## Resolved with the owner

- Public contact address on `/privacy`, in the sheet, and in the Play
  "request deletion" answer: `bytebakehouseinc@gmail.com`.
- The builder runs the two console steps (Firestore database in `eur3`,
  `flutterfire configure`); anything that needs an interactive Google login
  is handed back rather than worked around.

## Success check

- Web (phone and desktop viewport): send a bug from Settings; the document
  appears in the console with the correct fields; the draft is cleared.
- Android release build: `INTERNET` present in the merged manifest; send
  succeeds on Wi-Fi; airplane mode keeps the text across a relaunch, and
  Retry succeeds once reconnected.
- Rules: an unauthenticated client cannot read the collection; a 5000-char
  message and an unknown category are rejected.
- `flutter analyze` clean; the new tests pass.
- `dart format` clean on every touched file.

## Size

Roughly a day and a half including the sheet, store, rules, docs and tests,
plus the two console steps above.
