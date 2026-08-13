# Claudare

Claudare is a Dart Pub workspace developing a reusable core for Dart and
Flutter applications. Core is a logical layer that will span multiple packages.
It currently includes CQRS, common device and sequence primitives, SQLite
isolation, logging, IDs, time, and small CRDT helpers across shared packages.

`apps/notes` is the first prototype consumer of that infrastructure. It exists
to exercise core behavior through a real Flutter application. It is not the
definition of Claudare's architecture or a promise that future applications
will use the same domain model, storage layout, or UI.

It is not an offline-sync or encrypted-notes product yet. There is no working
replication, device enrollment, event encryption, blob storage, or backup.
Those boundaries are intentional documentation constraints: do not describe
them as implemented without corresponding source and validation evidence.

## Workspace map

| Path                        | Purpose                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| `packages/cqrs`             | CQRS portion of the reusable core                                              |
| `packages/common`           | Shared device, sequence, and serialization primitives                          |
| `packages/crdt`             | Timestamp-based CRDT value helpers                                             |
| `packages/id_generator`     | 128-bit ID generator contract and implementations                              |
| `packages/time_provider`    | Time provider contract and implementations                                     |
| `packages/queue`            | Multiple queue implementations                                                 |
| `packages/isolate_sqlite`   | SQLite connection owner running database callbacks in a dedicated isolate      |
| `packages/claudare_logging` | Shared explicit logging abstraction                                            |
| `apps/notes`                | First Flutter prototype consumer of the core packages                          |
| `docs`                      | Source-backed architecture, implementation, security, and improvement guidance |

The root `pubspec.yaml` discovers `apps/*` and `packages/*`. Every member uses
`resolution: workspace`; compatible version constraints resolve other members
locally. Pub owns one root lockfile.

## Start here

Read these documents in order when working on the repository:

1. [AGENTS.md](AGENTS.md) for repository rules and validation boundaries.
2. [Core wiring conventions](CONVENTIONS.md) for contracts, implementations,
   errors, and code-writing practices.
3. [Core architecture](docs/ARCHITECTURE_COMMON.md) for the reusable common,
   CQRS, CRDT, SQLite, and logging contracts.
4. [Application architecture](docs/ARCHITECTURE_APPS.md) for how an application
   composes and consumes the core.
5. [Application patterns](docs/APP_PATTERNS.md) for event codecs and their
   application-owned layout.
6. [Implementation](docs/IMPLEMENTATION.md) for actual behavior and known
   limitations.
7. [Security](docs/SECURITY.md) before making confidentiality, sync, or
   identity claims.
8. [Improvements](docs/IMPROVEMENTS.md) for source-backed next work.

## Setup and run

FVM must be installed and on `PATH`. From the workspace root:

```sh
fvm install
fvm flutter pub get
fvm flutter doctor
```

Run the notes prototype with the pinned Flutter SDK:

```sh
cd apps/notes
fvm flutter run
```

## Validate

For a code change, analyze the workspace and run the relevant tests. The full
Melos test command runs Dart package tests in parallel, then Flutter app tests.

```sh
fvm dart analyze
fvm dart run melos run test
```

For dependency or workspace changes, first resolve from the root and confirm
the discovered members:

```sh
fvm flutter pub get
fvm dart pub workspace list
fvm dart analyze
fvm dart run melos run test
```

Flutter tests run with `--no-pub` to keep their output concise. After changing
dependencies, run `fvm flutter pub get` or `fvm dart run melos bootstrap` before
testing.

For documentation-only changes, inspect the diff and run:

```sh
git diff --check
```

## Pub workflow

Add a dependency to the member that imports it. Use `fvm dart pub` for plain
Dart packages and `fvm flutter pub` for Flutter applications. Do not manually
edit `pubspec.lock`, use relative `path:` dependencies between members, or run
separate root-level resolves for each member. After changing dependencies,
resolve the mixed workspace from the root with `fvm flutter pub get`.
