# Claudare

Claudare is exploring a family of local-first applications for personal data.
The long-term goal is software that works offline across mobile and desktop,
does not require a central application server, and can eventually synchronize
encrypted data between devices controlled by the user.

## Current status

Claudare is a development prototype, not a finished local-first product.
`apps/notes` is the first Flutter application and exists to exercise the shared
packages through a real consumer. Its note domain, storage layout, and user
interface are examples, not the architectural center of the repository.

The current code supports local event-sourced application development. It does
not implement network transport, device identity or enrollment, multi-device
convergence, encryption, blob storage, or backup. The `cqrs` package can store
and retrieve complete stored commands, but synchronization is not implemented.

## Documentation

- [App Development Guide](docs/APP_DEVELOPMENT_GUIDE.md) explains how Flutter
  applications compose and consume the shared packages.
- [Implementation Details](docs/IMPLEMENTATION_DETAILS.md) describes package
  ownership and the implemented architecture.
- [Security](docs/SECURITY.md) defines the current security posture and the
  claims the project cannot yet make.
- [AGENTS.md](AGENTS.md) contains repository workflow rules for AI agents.
- [CONVENTIONS.md](CONVENTIONS.md) contains durable coding conventions for
  shared code.

## Setup

Install [FVM](https://fvm.app/) and make it available on `PATH`. From the
workspace root, install the pinned SDK and resolve all workspace dependencies:

```sh
fvm install
fvm flutter pub get
fvm flutter doctor
```

## Run and validate

Run the notes prototype:

```sh
cd apps/notes
fvm flutter run
```

Analyze the whole workspace and run all Dart and Flutter tests from the root:

```sh
fvm dart analyze
fvm dart run melos test
```

After workspace or dependency changes, also verify discovery:

```sh
fvm flutter pub get
fvm dart pub workspace list
```
