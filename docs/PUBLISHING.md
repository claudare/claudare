# Publishing

## Docker image visibility

After the first CI publication, open the `proxy` package settings on GitHub and
set its visibility to **Public** to allow installation without signing in.

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
