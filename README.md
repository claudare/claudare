# Claudare

Claudare is exploring local-first applications for personal data. The project
is a development prototype. Only nightly builds are available.

## Applications

Add the [Claudare Flatpak repository][flatpak-repository] to your software
manager to browse and install all available Claudare Flatpak applications.

- [Notes](frontends/notes/README.md): a notes app for Linux and Android.
- [Proxy](backend/proxy/README.md): a development WebSocket server for Linux.

## Development

Install FVM and make it available on `PATH`. From the workspace root:

```sh
fvm install
fvm flutter pub get
./run-frontend.sh notes
```

Analyze the workspace and run the tests:

```sh
fvm dart analyze
fvm dart run melos test
```

Open pull requests against `main`. Pushes to `nightly` build and publish
nightly releases.

[flatpak-repository]:
  https://claudare.github.io/claudare/flatpak/claudare-nightly.flatpakrepo
