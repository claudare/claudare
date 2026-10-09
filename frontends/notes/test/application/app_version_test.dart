import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/app_version.dart';

void main() {
  for (final (channel, expected) in [
    ('main', '0.1.0 (build 42)'),
    ('beta', '0.1.0-beta (build 42)'),
    ('nightly', '0.1.0-nightly (build 42)'),
  ]) {
    test('$channel labels the version and build number', () {
      expect(
        appVersionLabel(version: '0.1.0', buildNumber: '42', channel: channel),
        expected,
      );
    });
  }

  test('missing build number is omitted', () {
    expect(
      appVersionLabel(version: '0.1.0', buildNumber: null, channel: 'main'),
      '0.1.0',
    );
  });

  test('missing version defaults to unknown', () {
    expect(appVersionLabel(version: null), 'Unknown');
  });

  test('unknown channel is rejected', () {
    expect(() => appVersionLabel(channel: 'other'), throwsArgumentError);
  });
}
