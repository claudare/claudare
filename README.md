# Example workspaces

An example [Dart pub workspace](https://dart.dev/tools/pub/workspaces) containing
Flutter applications in `apps/` and shared Dart packages in `packages/`.

The root `pubspec.yaml` discovers members with these globs:

```yaml
workspace:
  - apps/*
  - packages/*
```

Every member must set `resolution: workspace`. Pub then uses one dependency
resolution, one `pubspec.lock`, and one `.dart_tool/package_config.json` at the
repository root.

## Fresh development setup

[FVM](https://fvm.app/) must already be installed and available on `PATH`.
From the repository root:

```sh
# Install the Flutter version pinned in .fvmrc.
fvm install

# Resolve dependencies for the entire workspace.
fvm flutter pub get

# Check that the local Flutter installation and platform toolchains are ready.
fvm flutter doctor
```

This is a mixed Dart and Flutter workspace, so use `fvm flutter pub get` at its
root. It resolves the shared lockfile and runs Flutter's post-processing for the
Flutter members. Do not run `pub get` separately in every app or package.

## Analysis and tests

Analyze the entire workspace from its root:

```sh
fvm dart analyze
```

Run every Dart package test and then every Flutter app test from the workspace
root:

```sh
./scripts/test.sh
```

To test only one member, run the appropriate test command from that member's
directory:

```sh
(cd packages/hello_world && fvm dart test)
(cd apps/hello_world_app && fvm flutter test)
```

## Run a Flutter application

Change into the application's directory and use the pinned Flutter SDK:

```sh
cd apps/hello_world_app
fvm flutter run
```

## Use pub

Choose the pub command based on the member receiving the dependency:

- For a plain Dart package, use `fvm dart pub`.
- For a Flutter app or Flutter package, use `fvm flutter pub`.
- At this mixed workspace's root, use `fvm flutter pub get`.

Both commands use the same Pub package manager. The Flutter form also performs
the Flutter-specific setup required by apps and plugins. When in doubt, just run
`flutter` commands.

### Add a package from pub.dev

Dependencies belong to the workspace member that imports them, not to the root
package. From the repository root, use `-C` to select a Dart package:

```sh
fvm dart pub add http -C packages/hello_world
```

For a Flutter application, use Flutter's pub command from the app directory:

```sh
(cd apps/hello_world_app && fvm flutter pub add url_launcher)
```

Prefix a development-only dependency with `dev:`:

```sh
fvm dart pub add dev:mocktail -C packages/hello_world
```

These commands update the selected member's `pubspec.yaml` and refresh the
workspace's shared dependency resolution.

### Depend on another workspace package

Use the local package name with a version constraint that matches its `version`.
For example, this adds `hello_world` to `hello_world_app`:

```sh
(cd apps/hello_world_app && fvm flutter pub add hello_world@^1.0.0)
```

This produces the following dependency in the consuming app:

```yaml
dependencies:
  hello_world: ^1.0.0
```

Do not add a relative `path:` dependency between workspace members. Pub detects
`hello_world` as a workspace member and resolves the compatible local package
automatically.

## Add another app or package

Create new members below the existing globbed directories:

```sh
fvm flutter create apps/my_app
fvm dart create --template=package packages/my_package
```

Add this top-level field to each generated member's `pubspec.yaml`:

```yaml
resolution: workspace
```

Then resolve the mixed workspace from the repository root:

```sh
fvm flutter pub get
fvm dart pub workspace list
```
