# Notes

Notes is a Flutter prototype for the Claudare project. It supports editing,
trashing, and restoring local notes. Settings provides the app version, peer
and server configuration, connection diagnostics, and database reset.

Server configuration is optional. Replication is experimental, not a complete
synchronization system. Text search, encryption, and backup are not available.

## Linux installation

Install [Flatpak](https://flatpak.org/setup/), then open the
[Notes Nightly installer][flatpak-install] with your software manager.
Alternatively, install from a terminal:

```sh
flatpak install --user \
  https://claudare.github.io/claudare/flatpak/notes-nightly.flatpakref
flatpak run com.claudare.notes
```

The installer adds the signed Claudare repository and offers to install the
required runtime. The [repository configuration][flatpak-repository] is also
available for adding the repository to your software manager.

Updates follow your software manager's automatic update settings. To update
manually, run `flatpak update --user com.claudare.notes`, then restart Notes.

Nightly builds are experimental. Flatpak stores its data separately from
archive installations; existing notes are not automatically migrated.

The Linux x64 archive `notes-nightly-linux-x64.tar.gz` remains available from
[Notes Nightly][notes-nightly].

## Android nightly updates

Install [Obtainium](https://obtainium.imranr.dev/), then
[import Notes Nightly][obtainium-import]. Confirm the import and check for
updates to install the latest APK.

Alternatively, download the [configuration](obtainium.json) and import it from
Obtainium's **Settings > Import/export** page.

Nightly builds are experimental. Obtainium tracks replaced APKs in the rolling
nightly release. Background checks and installation follow your Obtainium
settings.

The [Dart Notes core](../../apps/notes/README.md) is also available to library
consumers.

[notes-nightly]:
  https://github.com/claudare/claudare/releases/tag/notes/nightly

[flatpak-install]:
  https://claudare.github.io/claudare/flatpak/notes-nightly.flatpakref
[flatpak-repository]:
  https://claudare.github.io/claudare/flatpak/claudare-nightly.flatpakrepo

[obtainium-import]:
  https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22com.claudare.notes%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fclaudare%2Fclaudare%22%2C%22author%22%3A%22claudare%22%2C%22name%22%3A%22Notes%20Nightly%22%2C%22additionalSettings%22%3A%22%7B%5C%22includePrereleases%5C%22%3Atrue%2C%5C%22filterReleaseTitlesByRegEx%5C%22%3A%5C%22%5ENotes%20Nightly%24%5C%22%2C%5C%22apkFilterRegEx%5C%22%3A%5C%22%5Enotes-nightly-android%5C%5C%5C%5C.apk%24%5C%22%2C%5C%22verifyLatestTag%5C%22%3Afalse%2C%5C%22sortMethodChoice%5C%22%3A%5C%22date%5C%22%2C%5C%22useLatestAssetDateAsReleaseDate%5C%22%3Atrue%2C%5C%22releaseDateAsVersion%5C%22%3Atrue%2C%5C%22versionDetection%5C%22%3Afalse%2C%5C%22trackOnly%5C%22%3Afalse%2C%5C%22includeZips%5C%22%3Afalse%2C%5C%22includeTarballs%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Afalse%2C%5C%22fallbackToOlderReleases%5C%22%3Atrue%7D%22%7D
