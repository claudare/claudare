#!/usr/bin/env bash
set -euo pipefail

app=${1:?App name is required}
case "$app" in
  notes) pubspec=frontends/notes/pubspec.yaml ;;
  proxy) pubspec=backend/proxy/pubspec.yaml ;;
  *) echo "Unknown app: $app" >&2; exit 1 ;;
esac
version=$(awk '/^version:/ { print $2 }' "$pubspec")
test -n "$version"
jq -n \
  --arg app "$app" \
  --arg version "$version" \
  --arg commit "$GITHUB_SHA" \
  --argjson buildNumber "$GITHUB_RUN_NUMBER" \
  --argjson runAttempt "$GITHUB_RUN_ATTEMPT" \
  --arg workflowUrl "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
  '{app: $app, version: $version, channel: "nightly",
    buildNumber: $buildNumber, commit: $commit, runAttempt: $runAttempt,
    workflowUrl: $workflowUrl}'
