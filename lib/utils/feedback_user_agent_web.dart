/// Web implementation – imported instead of feedback_user_agent_stub.dart on
/// dart.library.js_interop. The native operating system version must never be
/// read here; the stub throws so diagnostics use the user agent instead.
library;

import 'dart:js_interop';

@JS('navigator.userAgent')
external JSString? get _userAgent;

/// The browser's user agent, or null when it is unavailable or empty.
String? currentUserAgent() {
  final userAgent = _userAgent;
  if (userAgent == null) return null;
  final value = userAgent.toDart;
  return value.isEmpty ? null : value;
}

String nativeOperatingSystemVersion() => throw UnsupportedError('web');
