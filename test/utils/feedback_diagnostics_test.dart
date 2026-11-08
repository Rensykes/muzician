import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/feedback_diagnostics.dart';

void main() {
  test('describes common user agents coarsely', () {
    expect(
      describeUserAgent(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      ),
      'Chrome / macOS',
    );
    expect(
      describeUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 '
        'Safari/604.1',
      ),
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
        'appVersion',
        'platform',
        'osVersion',
        'screen',
        'locale',
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
}
