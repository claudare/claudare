#!/usr/bin/env bash
set -euo pipefail

for variable in FLATPAK_GPG_PRIVATE_KEY_BASE64 FLATPAK_GPG_KEY_ID FLATPAK_GPG_PASSPHRASE; do
  if [[ -z "${!variable:-}" ]]; then
    echo "::error::Missing Flatpak signing secret: $variable"
    exit 1
  fi
done
if [[ ! "$FLATPAK_GPG_KEY_ID" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "::error::FLATPAK_GPG_KEY_ID must be the full GPG fingerprint."
  exit 1
fi

work=$(mktemp -d "${RUNNER_TEMP:?}/notes-flatpak.XXXXXX")
export GNUPGHOME="$work/gnupg"
cleanup() {
  gpgconf --kill gpg-agent || true
  rm -rf "$work"
}
trap cleanup EXIT
umask 077
mkdir -p "$GNUPGHOME"
printf '%s\n' 'pinentry-mode error' > "$GNUPGHOME/gpg.conf"
printf '%s\n' 'allow-preset-passphrase' 'default-cache-ttl 7200' \
  'max-cache-ttl 7200' > "$GNUPGHOME/gpg-agent.conf"
printf '%s' "$FLATPAK_GPG_PRIVATE_KEY_BASE64" | base64 --decode > "$work/private-key.gpg"
gpg --batch --import "$work/private-key.gpg"
rm "$work/private-key.gpg"
fingerprint=$(gpg --batch --with-colons --list-secret-keys "$FLATPAK_GPG_KEY_ID" \
  | awk -F: '$1 == "fpr" { print $10; exit }')
test "$fingerprint" = "${FLATPAK_GPG_KEY_ID^^}"
keygrip=$(gpg --batch --with-colons --with-keygrip --list-secret-keys "$fingerprint" \
  | awk -F: '$1 == "grp" { print $10; exit }')
test -n "$keygrip"
preset="$(gpgconf --list-dirs libexecdir)/gpg-preset-passphrase"
printf '%s' "$FLATPAK_GPG_PASSPHRASE" | "$preset" --preset "$keygrip"
# Verify the passphrase and signing capability before downloading runtimes.
printf 'Claudare Flatpak signing check\n' > "$work/signing-check"
gpg --batch --local-user "$fingerprint" --detach-sign "$work/signing-check"
gpg --batch --export "$fingerprint" > "$work/public-key.gpg"
test -s "$work/public-key.gpg"
unset FLATPAK_GPG_PRIVATE_KEY_BASE64 FLATPAK_GPG_KEY_ID FLATPAK_GPG_PASSPHRASE

assets=frontends/notes/flatpak
mkdir -p "$work/source/bundle"
cp "$assets/com.claudare.notes.nightly.json" "$work/"
cp "$assets/notes.sh" "$assets/com.claudare.notes.nightly.desktop" \
  "$assets/com.claudare.notes.nightly.metainfo.xml" "$work/source/"
cp frontends/notes/web/icons/Icon-512.png "$work/source/icon.png"
tar -xzf dist/notes-linux/notes-nightly-linux-x64.tar.gz -C "$work/source/bundle"
test -x "$work/source/bundle/notes"
test -f "$work/source/bundle/lib/libapp.so"
test -d "$work/source/bundle/data/flutter_assets"
jq -e --arg sha "$GITHUB_SHA" --argjson build "$GITHUB_RUN_NUMBER" \
  --argjson attempt "$GITHUB_RUN_ATTEMPT" \
  '.app == "notes" and .commit == $sha and .channel == "nightly"
    and .buildNumber == $build and .runAttempt == $attempt' \
  "$work/source/bundle/build-info.json" > /dev/null

umask 022
mkdir -p site/flatpak
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak update --user --noninteractive
flatpak-builder --user --arch=x86_64 --install-deps-from=flathub \
  --disable-rofiles-fuse --force-clean \
  "$work/build" "$work/com.claudare.notes.nightly.json"
flatpak build-export --gpg-sign="$fingerprint" --gpg-homedir="$GNUPGHOME" \
  site/flatpak/repo "$work/build" nightly
flatpak build-update-repo --gpg-sign="$fingerprint" \
  --gpg-homedir="$GNUPGHOME" --gpg-import="$work/public-key.gpg" \
  --title='Claudare Nightly' --default-branch=nightly \
  --prune --prune-depth=0 site/flatpak/repo

public_key=$(base64 --wrap=0 "$work/public-key.gpg")
for descriptor in notes-nightly.flatpakref claudare-nightly.flatpakrepo; do
  sed -e 's|@REPO_URL@|https://claudare.github.io/claudare/flatpak/repo/|g' \
    -e "s|@GPG_KEY@|$public_key|g" "$assets/$descriptor.in" \
    > "site/flatpak/$descriptor"
done
cp dist/notes-linux/build-info.json site/flatpak/build-info.json
mkdir -p dist/notes-flatpak
cp site/flatpak/build-info.json dist/notes-flatpak/
touch site/.nojekyll
test "$(du -sb site | cut -f1)" -lt 1000000000
