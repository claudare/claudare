# Claudare

Claudare is exploring a family of local-first applications for personal data.
The long-term goal is software that works offline across mobile and desktop,
does not require a central application server, and can eventually synchronize
data between devices controlled by the user.

## Applications

Only nightly builds are available. Currently, builds are provided for Linux
x64 and Android.

| App | Available builds | Downloads |
| --- | --- | --- |
| [Notes](frontends/notes/README.md) | Linux x64, Android | [Nightly][notes] |
| [Proxy](backend/proxy/README.md) | Linux x64 | [Nightly][proxy] |

## Current status

Claudare is a development prototype, not a finished local-first app suite.
`apps/notes` is a Dart package for note behavior. The Flutter prototype in
`frontends/notes` consumes it and exercises the shared packages through a real
application. The note domain, storage layout, and user interface are examples,
not the architectural center of the repository.

The current code supports local event-sourced application development and
central websocket proxy replication.

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
cd frontends/notes
fvm flutter run
```

Analyze the whole workspace and run all Dart and Flutter tests from the root:

```sh
fvm dart analyze
fvm dart run melos test
```

## Contributing

All development is performed on a `dev` branch. Please open PR's to it. The main
branch is for stable code and CI/CD.

[notes]: https://github.com/claudare/claudare/releases/tag/notes/nightly
[proxy]: https://github.com/claudare/claudare/releases/tag/proxy/nightly
