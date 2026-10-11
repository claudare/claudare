# Publishing

## Application naming

Prefix command-line application names with `claudare-APPNAME`, using the
lowercase app name. For example, Notes uses `claudare-notes`.

Capitalize application display names and append `Nightly` for nightly builds.
For example, use `Notes Nightly`.

## Docker image visibility

After the first CI publication, open the `proxy` package settings on GitHub and
set its visibility to **Public** to allow installation without signing in.

## Flatpak repository

The application Flatpak repository uses this repository's GitHub Pages site.
In **Settings > Pages > Build and deployment**, select **GitHub Actions** as
the source. Keep the site public. If the `github-pages` environment has branch
restrictions, allow deployments from `main`.

The repository URL is
`https://claudare.github.io/claudare/flatpak/repo/`. Install descriptors are
published beside it and linked from the application READMEs. No separate server
or personal access token is required.

### Create a signing key

Use one persistent GPG signing key for the Claudare Flatpak repository. These
commands require GnuPG and Bash on Linux. Keep signing files outside Git:

```bash
umask 077
signing_dir="$HOME/.local/share/claudare/signing/flatpak"
mkdir -p "$signing_dir/gnupg"
chmod 700 "$signing_dir/gnupg"

gpg --homedir "$signing_dir/gnupg" --quick-generate-key \
  'Claudare Flatpak signing' rsa4096 sign 0
gpg --homedir "$signing_dir/gnupg" --list-secret-keys \
  --keyid-format long --fingerprint
```

Choose a strong passphrase and save it in a password manager. The command
creates a signing-only key without an expiry date. Copy its full 40-character
fingerprint into the command below:

```bash
flatpak_fingerprint='REPLACE_WITH_FULL_FINGERPRINT'
gpg --homedir "$signing_dir/gnupg" --export-secret-keys \
  "$flatpak_fingerprint" > "$signing_dir/private-key.gpg"
base64 --wrap=0 "$signing_dir/private-key.gpg" \
  > "$signing_dir/private-key.base64"
```

### Configure signing and publish

In **Settings > Secrets and variables > Actions**, add these repository secrets:

| Secret | Value |
| --- | --- |
| `FLATPAK_GPG_PRIVATE_KEY_BASE64` | Contents of `private-key.base64` |
| `FLATPAK_GPG_KEY_ID` | Full signing key fingerprint |
| `FLATPAK_GPG_PASSPHRASE` | Signing key passphrase |

Keep a secure backup of the key, its GnuPG directory, revocation certificate,
and passphrase. Base64 is not encryption. Reuse the same key for subsequent
publications. Replacing it requires updating the trust configuration of existing
installations.

Push to `main`, or rerun a failed workflow after configuring Pages and secrets.
After the first successful publication, open the Notes installation link from
its README, or verify installation from a terminal:

```sh
flatpak install --user \
  https://claudare.github.io/claudare/flatpak/notes-nightly.flatpakref
flatpak run com.claudare.notes
flatpak update --user com.claudare.notes
```

The installer imports the public signing key. Keep signature verification
enabled. Automatic updates depend on the user's desktop software manager.

## Android signing keys

Use a separate signing key and PKCS12 keystore for each Android app. This limits
the effect of a compromised key to the app that uses it. Reuse an app's key for
all subsequent releases so installed APKs can receive updates.

Sharing a signing key across apps is supported. Choose this when the apps need
to trust each other through Android signature permissions. Sharing the Claudare
name alone does not require a shared key. See
[Android signing considerations][android-signing].

If a Notes key already exists, keep using it. Converting its keystore format
preserves the key; generating another key changes the app's signing identity.

## Generate a key

These commands use Bash on Linux and require a JDK with `keytool`. Store signing
files outside the repository. For a future app, replace `notes` with its name
and run the commands once to create its own key.

```bash
umask 077
signing_dir="$HOME/.local/share/claudare/signing"
mkdir -p "$signing_dir"

keytool -genkeypair -v \
  -storetype PKCS12 \
  -keystore "$signing_dir/notes-release.p12" \
  -alias notes-release \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Choose a strong password and save it in a password manager. PKCS12 uses the same
password for the keystore and private key with this command.

For the first and last name prompt, enter your name or `Claudare`. Fill in the
remaining certificate identity fields as appropriate. These values are visible
in the certificate and do not need to match a GitHub account.

Check that the keystore contains the expected key:

```bash
keytool -list -v \
  -storetype PKCS12 \
  -keystore "$signing_dir/notes-release.p12" \
  -alias notes-release
```

The entry type should be `PrivateKeyEntry`.

## Configure GitHub Actions

Encode the Notes keystore into a file:

```bash
umask 077
signing_dir="$HOME/.local/share/claudare/signing"
base64 --wrap=0 "$signing_dir/notes-release.p12" \
  > "$signing_dir/notes-release.base64"
```

In the repository, open **Settings > Secrets and variables > Actions** and
choose **New repository secret** for each value:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Entire contents of `notes-release.base64` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `notes-release` |
| `ANDROID_KEY_PASSWORD` | Same password as the keystore |

These secrets currently sign Notes. When adding another Android app, create
dedicated secrets for its keystore and configure its workflow to use them.
`ANDROID_KEYSTORE_PATH` is supplied by the workflow, not a repository secret.

Push to `main`, or rerun a failed workflow after configuring the secrets. The
Android job builds the release APK and checks its signature.

Keep a secure backup of the keystore and password. Keep keystores, Base64
copies, and passwords out of Git. Base64 is an encoding, not encryption. Losing
the signing key prevents publishing updates to existing installations through
this APK workflow.

[android-signing]:
  https://developer.android.com/studio/publish/app-signing#considerations
