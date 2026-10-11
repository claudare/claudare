#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || ! "$1" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "Usage: $0 <app-name> [flutter run arguments...]" >&2
  exit 1
fi

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
frontend="$repository/frontends/$1"
if [[ ! -f "$frontend/pubspec.yaml" ]]; then
  echo "Unknown frontend: $1" >&2
  exit 1
fi
shift
cd -- "$frontend"
exec fvm flutter run --flavor dev "$@"
