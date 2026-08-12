# Repository guidelines

These instructions apply to the entire repository.

## Workspace

- `apps/*` contains Flutter applications. Use short package names and
  `com.claudare.<app>` for every platform application identifier.
- Shared packages own their respective concerns: `core` owns CQRS and domain
  infrastructure, `common` owns shared device, sequence, and serialization
  primitives, `id_generator` owns IDs, `time_provider` owns time, `crdt` owns
  CRDT helpers, `isolate_sqlite` owns SQLite isolation, and `claudare_logging`
  owns logging.
- Shared packages must not depend on applications. `apps/notes` is a prototype
  consumer, not the architectural center.
- Keep repository-wide, source-backed documentation in `docs`; keep package-
  and app-specific documentation beside its owner.
- The root `pubspec.yaml` discovers `apps/*` and `packages/*`. Every member must
  declare `resolution: workspace` and inherit the root `analysis_options.yaml`.

## Dependencies

- Pub owns the single root `pubspec.lock`. Never edit, copy, merge, or delete a
  lockfile manually, and do not commit member lockfiles.
- Change dependencies through the owning `pubspec.yaml` or Pub command. Use
  `fvm dart pub` for Dart packages and `fvm flutter pub` for Flutter apps.
- Resolve the workspace from its root with `fvm flutter pub get`, not separate
  member-level `pub get` commands.
- Reference workspace members by compatible version constraints, never by path,
  Git dependency, or submodule.
- Do not add external dependencies unless requested or approved. Local workspace
  references are always allowed.

## Code

- Follow [CONVENTIONS.md](CONVENTIONS.md) for Core wiring. It applies to new and
  modified code; do not refactor existing deviations unless required by the task.
- Pass logging through Core's `Logger`. Use `NoopLogger` or `RecordingLogger`
  when output is suppressed or inspected; do not add ad-hoc prints.
- Keep shared analyzer policy at the repository root without member overrides.
- Avoid em-dashes and unnecessary comments in code and user-facing text. Do not
  add unrequested UI help text or meaningless expressive language.

## Documentation

- Do not claim replication, device enrollment, encryption, blob storage, backup,
  or production security. They are not implemented. The notes runtime still uses
  `DeviceId.unassigned()`.
- Treat the root `README.md` and `docs/*.md` as AI orientation material. State
  ownership, supported behavior, limitations, and actual validation evidence.
- Verify source before changing implementation status or retaining old paths.
- Keep normative Core wiring in `CONVENTIONS.md`; other documents should link to
  it instead of duplicating it.
- Update relevant root documentation when public behavior, ownership, validation,
  or security posture changes. Fix repository links when moving documents.

## Validation

For workspace or dependency changes, run:

```sh
fvm flutter pub get
fvm dart pub workspace list
fvm dart analyze
./scripts/test.sh
```

`scripts/test.sh` runs every package and application test. For code changes within
one member, run root analysis and its relevant tests; use the full script for
cross-workspace code changes. For documentation-only changes, inspect the diff and
run `git diff --check`; analysis and tests are unnecessary unless generated docs
or executable examples changed. Report only checks actually run, categorized as
static checks, tests, builds, or runtime verification.
