# Repository Guidelines

These instructions apply to the entire repository.

## Workspace layout

- `apps/*` are the Flutter applications.
- `packages/core` contains the shared CQRS and domain infrastructure.
- `packages/isolate_sqlite` contains the isolated SQLite implementation.
- `packages/claudare_logging` contains the shared logging abstractions.
- `docs` contains repository-wide, source-backed architecture, implementation,
  security, and improvement documents. Keep package- or app-specific
  documentation beside its owner.
- The root `pubspec.yaml` discovers members through `apps/*` and `packages/*`.
  Every member must declare `resolution: workspace`.

## Naming and namespaces

- Give applications short Dart package names, such as `notes`.
- Namespace every platform application identifier as `com.claudare.<app>`.
  For `notes`, use `com.claudare.notes` consistently for Android namespaces and
  application IDs, Apple bundle identifiers, Linux application IDs, and other
  platform metadata.

## Dependencies and lockfiles

- Never edit, copy, merge, or delete a `pubspec.lock` manually.
- Change dependencies only through the owning member's `pubspec.yaml` or an
  appropriate Pub command, then let Pub regenerate the root lockfile.
- Resolve the mixed Dart/Flutter workspace from the repository root with
  `fvm flutter pub get`. Do not run separate `pub get` commands for every member.
- Use `fvm dart pub` for plain Dart packages and `fvm flutter pub` for Flutter
  applications when adding, removing, or upgrading a dependency.
- Reference another workspace member by a compatible version constraint. Do not
  use a relative path, Git dependency, or submodule for an internal member.
- Do not commit member-level lockfiles; Pub owns the single root lockfile and
  removes stray member lockfiles when resolving the workspace.
- Do not add new external dependencies unless asked explicity or it was approved
  during the planning phase. If unsure, ask. Adding local references is always
  okay.

## Code and ownership

- Avoid em-dashes and unnecessary comments in code. Never use an em-dash in
  code comments or user-facing text. Do not add extra descriptive or help
  messages when implementing a UI feature unless asked. Do not use strong or
  expressive language that has no meaning.
- Follow [CONVENTIONS.md](CONVENTIONS.md) for Core wiring, contracts,
  implementations, entrypoint boundaries, exceptions, and defensive
  invariants. Its conventions apply to new and modified code; existing
  deviations do not require refactoring unless the task calls for it.
- Applications may depend on shared packages; shared packages must not depend
  on applications.
- Keep foundational logging in `claudare_logging`, SQLite isolate behavior in
  `isolate_sqlite`, and CQRS/domain infrastructure in `core`.
- Pass logging through the explicit `Logger` abstraction required by `core`.
  Use `NoopLogger` or `RecordingLogger` where output is intentionally suppressed
  or inspected, rather than adding ad-hoc prints.
- Preserve the configured analyzer rules. Every app and package must inherit
  the root `analysis_options.yaml`; keep shared lint and analyzer policy at the
  repository root rather than duplicating or overriding it in workspace members.

## Current architecture and documentation

- Core is Claudare's reusable, application-independent foundation. It will
  span multiple packages. Today, `packages/core` owns CQRS, IDs, time, and CRDT
  helpers; `isolate_sqlite` owns SQLite isolation; `claudare_logging` owns
  logging. `apps/notes` is the first prototype consumer, not the architectural
  center.
- Do not claim replication, device enrollment, encryption, blob storage,
  backup, or production security. These are not implemented in the current
  workspace. `DeviceId.unassigned()` is still used by the notes runtime.
- Treat root `README.md` and `docs/*.md` as AI orientation material: state
  ownership, supported behavior, limitations, and validation evidence
  explicitly. Reinspect source before changing an implemented/planned status;
  do not retain historical claims about removed packages or old paths.
- Keep repository-wide Core wiring guidance in `CONVENTIONS.md`; architecture,
  implementation, and improvement documents should link to it instead of
  duplicating its normative implementation advice.
- When changing public behavior, package ownership, validation commands, or
  security posture, update the applicable root documentation in the same
  change. Correct all in-repository documentation links when moving a document.

## Validation

- For workspace or dependency changes, run:

  ```sh
  fvm flutter pub get
  fvm dart pub workspace list
  fvm dart analyze
  ./scripts/test.sh
  ```

- `scripts/test.sh` runs Dart tests for every package and Flutter tests for every
  application. Use a focused member test while iterating, then the full script
  for cross-workspace changes.
- For code changes confined to one member, run root analysis plus that member's
  relevant tests.
- For documentation-only changes, inspect the diff and run `git diff --check`;
  code analysis and tests are unnecessary unless documentation generation or
  executable examples changed.
- Report only commands that were actually run and distinguish static checks,
  tests, builds, and runtime verification.
