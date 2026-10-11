#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

rm -f -- .dart_tool/package_config.json
exec fvm flutter pub get --offline
