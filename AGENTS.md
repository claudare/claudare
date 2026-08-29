# Repository guidelines

These instructions apply to the entire repository.

## Workspace

- `apps/*` contains Flutter applications. Use short package names and
  `com.claudare.<app>` for every platform application identifier.
- Shared packages own their respective concerns: `cqrs` owns CQRS and domain
  infrastructure; `common` owns shared async, causal, pagination, and
  serialization primitives; `id_generator` owns IDs; `time_provider` owns time;
  `crdt` owns CRDT helpers; `isolate_sqlite` owns SQLite isolation; and
  `claudare_logging` owns logging. `queue` and `package_template` are support
  packages.
- Shared packages must not depend on applications. `apps/notes` is a prototype
  consumer, not the architectural center.
- Keep repository-wide, documentation in `docs`. Keep package- and app-specific
  documentation beside its owner. Do not use `ideas` as maintained
  documentation.

## Dependencies

- Pub owns the single root `pubspec.lock`. Never edit, copy, merge, or delete a
  lockfile manually, and do not commit member lockfiles.
- Change dependencies through the owning `pubspec.yaml` or Pub command. Use
  `fvm dart pub` for Dart packages and `fvm flutter pub` for Flutter apps.
- Resolve the workspace from its root with `fvm flutter pub get`, not separate
  member-level resolves.
- Reference workspace members by compatible version constraints, never by path,
  Git dependency, or submodule.
- Do not add external dependencies unless requested or approved. Local workspace
  references are allowed.

## Code

- Follow [CONVENTIONS.md](CONVENTIONS.md) for new and modified code. Do not
  refactor unrelated existing deviations.
- Use the logger from `claudare_logging`. There is no global logger. Do not add
  ad hoc prints.
- Breaking changes are allowed as the project is under development. Do not add
  compatibility paths.
- Keep shared analyzer policy at the repository root without member overrides.
- Use `///` to document key classes and interfaces. Use `[]` to reference code.
  Keep documentation short and to the point.

## Documentation

- Do not claim a working replication or synchronization system, device
  enrollment, encryption, blob storage, backup, or production security. They are
  not implemented.
- Treat root and package `README.md` files and `docs/*.md` as orientation
  overviews, not in-depth implementation guides. State ownership, supported
  behavior, significant limitations, setup, security posture, and only
  validation evidence that was actually collected in the relevant documentation.
- During implementation work, update maintained documentation only when one of
  those overview-level facts changes. Do not add internal algorithms, lifecycle
  transitions, coordination details, or similar implementation specifics unless
  documentation was explicitly requested. When unsure, ask before editing
  documentation.
- Verify source before changing implementation status, and fix links when
  documents move.
- Keep normative coding conventions in `CONVENTIONS.md` rather than duplicating
  them elsewhere.

## Tests

- Prefer tests that verify one behavior or invariant. Split unrelated APIs,
  success and failure paths, or outcomes into separate tests, and share setup
  through helpers.
- Use table-driven tests when variants exercise the same behavior.

## Validation

For workspace or dependency changes, run:

```sh
fvm flutter pub get
fvm dart pub workspace list
fvm dart analyze
fvm dart run melos test
```

For a code change within one member, run root analysis and the relevant tests.
Use the full Melos command for cross-workspace code changes. Flutter tests use
`--no-pub`, so resolve dependencies before testing after dependency changes.

For documentation-only changes analysis and tests are unnecessary. Report only
checks actually run, categorized as static checks, tests, builds, or runtime
verification.

## Communication style

Avoid em dashes and unnecessary comments in code and user-facing text. Do not
use meaningless expressive language. Be concise when responding.

When unsure about something, do not guess and ask user instead.
