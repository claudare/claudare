import 'package:flutter/services.dart';

/// Formats the version, channel, and build number shown in Settings.
String appVersionLabel({
  String? version = appBuildName,
  String? buildNumber = appBuildNumber,
  String channel = const String.fromEnvironment(
    'APP_CHANNEL',
    defaultValue: 'nightly',
  ),
}) {
  final suffix = switch (channel) {
    'main' => '',
    'beta' => '-beta',
    'nightly' => '-nightly',
    _ => throw ArgumentError.value(channel, 'channel', 'Unknown app channel'),
  };
  if (version == null) return 'Unknown';
  final build = buildNumber == null ? '' : ' (build $buildNumber)';
  return '$version$suffix$build';
}
