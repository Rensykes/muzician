/// Coarse browser and platform description.
///
/// Platform strategy:
///   Web    → read the browser's user agent
///   Native → no user agent; the operating system version is used instead
library;

// Conditional import: feedback_user_agent_stub.dart on native,
// feedback_user_agent_web.dart on web.
import 'feedback_user_agent_stub.dart'
    if (dart.library.js_interop) 'feedback_user_agent_web.dart'
    as impl;

/// The current browser user agent, or null where it does not apply.
String? currentUserAgent() => impl.currentUserAgent();

/// The native operating system version, trimmed to its first two tokens
/// (`Android 14`).
///
/// Never called on web: diagnostics read [currentUserAgent] there instead.
String nativeOperatingSystemVersion() => impl.nativeOperatingSystemVersion();
