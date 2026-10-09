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
        appVersionLabel(
          version: '0.1.0',
          buildNumber: '42',
          commit: null,
          channel: channel,
        ),
        expected,
      );
    });
  }

  test('missing build number is omitted', () {
    expect(
      appVersionLabel(
        version: '0.1.0',
        buildNumber: null,
        commit: null,
        channel: 'main',
      ),
      '0.1.0',
    );
  });

  test('missing version defaults to unknown', () {
    expect(appVersionLabel(version: null), 'Unknown');
  });

  for (final (buildNumber, commit, expected) in [
    (
      '123',
      'a1b2c3d4e5f678901234',
      '0.0.0-nightly (build 123, commit a1b2c3d4e5f6)',
    ),
    (null, 'a1b2c3d4e5f678901234', '0.0.0-nightly (commit a1b2c3d4e5f6)'),
    ('123', null, '0.0.0-nightly (build 123)'),
    ('123', '', '0.0.0-nightly (build 123)'),
    (null, null, '0.0.0-nightly'),
    ('', '', '0.0.0-nightly'),
    (null, 'abc', '0.0.0-nightly (commit abc)'),
  ]) {
    test('build $buildNumber and commit $commit format metadata', () {
      expect(
        appVersionLabel(
          version: '0.0.0',
          buildNumber: buildNumber,
          commit: commit,
          channel: 'nightly',
        ),
        expected,
      );
    });
  }

  test('unknown channel is rejected', () {
    expect(() => appVersionLabel(channel: 'other'), throwsArgumentError);
  });
}
