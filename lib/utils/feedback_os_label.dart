/// Formats a native operating-system version for feedback diagnostics.
library;

/// Turns `Platform.operatingSystemVersion` into a short, labelled value.
///
/// Native strings are inconsistent: Android already names itself
/// (`Android 14 (API 34)`), while iOS and macOS only report a version
/// (`Version 27.0.1 (Build 24A335)`), which would arrive with no clue about
/// which OS it belongs to.
String describeNativeOs(String rawVersion, String operatingSystem) {
  final raw = rawVersion.trim();
  if (raw.isEmpty) return 'unknown';
  final version = RegExp(r'\d+(?:\.\d+)*').firstMatch(raw)?.group(0);
  switch (operatingSystem) {
    case 'ios':
      return version == null ? 'iOS' : 'iOS $version';
    case 'macos':
      return version == null ? 'macOS' : 'macOS $version';
    case 'android':
      final name = RegExp(r'^Android\s+\S+').firstMatch(raw)?.group(0);
      if (name != null) return name;
      return version == null ? 'Android' : 'Android $version';
    default:
      // Windows and Linux already lead with their own name.
      final tokens = raw.split(RegExp(r'\s+'));
      return tokens.take(2).join(' ');
  }
}
