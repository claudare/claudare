#!/usr/bin/env bash

set -euo pipefail

workspace_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for package_dir in "$workspace_root"/packages/*; do
  [[ -f "$package_dir/pubspec.yaml" ]] || continue
  echo "==> Dart tests: ${package_dir#"$workspace_root"/}"
  (cd "$package_dir" && fvm dart test)
done

for app_dir in "$workspace_root"/apps/*; do
  [[ -f "$app_dir/pubspec.yaml" ]] || continue
  echo "==> Flutter tests: ${app_dir#"$workspace_root"/}"
  (cd "$app_dir" && fvm flutter test)
done
