import 'package:flutter/services.dart';

/// Formats the version and optional build and commit metadata for Settings.
String appVersionLabel({
  String? version = appBuildName,
  String? buildNumber = appBuildNumber,
  String? commit = const String.fromEnvironment('APP_COMMIT'),
  String? flavor = appFlavor,
}) {
  final suffix = flavor == null ? '' : '-$flavor';
  if (version == null) return 'Unknown';
  final metadata = [
    if (buildNumber != null && buildNumber.isNotEmpty) 'build $buildNumber',
    if (commit != null && commit.isNotEmpty)
      'commit ${commit.substring(0, commit.length > 12 ? 12 : commit.length)}',
  ];
  final details = metadata.isEmpty ? '' : ' (${metadata.join(', ')})';
  return '$version$suffix$details';
}
