#!/usr/bin/env bash
set -euo pipefail

repository="repos/$GITHUB_REPOSITORY"
head_sha=$(gh api "$repository/commits/main" --jq .sha)
if [[ "$head_sha" != "$GITHUB_SHA" ]]; then
  echo "Skipping publication: main has superseded $GITHUB_SHA."
  exit 0
fi

# Check every input before publishing the image or changing either release.
for app in notes proxy; do
  jq -e --arg app "$app" --arg sha "$GITHUB_SHA" \
    --argjson build "$GITHUB_RUN_NUMBER" --argjson attempt "$GITHUB_RUN_ATTEMPT" \
    '.app == $app and .commit == $sha and .channel == "nightly"
      and .buildNumber == $build and .runAttempt == $attempt' \
    "dist/$app-linux/build-info.json" > /dev/null
  test -s "dist/$app-linux/$app-nightly-linux-x64.tar.gz"
done
test -s dist/notes-android/notes-nightly-android.apk
test -s dist/proxy-container/proxy-container.tar

container_owner="${GITHUB_REPOSITORY%%/*}"
container_image="ghcr.io/${container_owner,,}/proxy:nightly"
printf '%s' "$GH_TOKEN" | docker login ghcr.io \
  --username "$GITHUB_ACTOR" --password-stdin
trap 'docker logout ghcr.io' EXIT
docker load --input dist/proxy-container/proxy-container.tar
docker tag proxy-nightly:ci "$container_image"
docker push "$container_image"

for app in notes proxy; do
  tag="$app/nightly"
  title="${app^} Nightly"
  metadata="dist/$app-linux/build-info.json"
  version=$(jq -r .version "$metadata")
  workflow_url=$(jq -r .workflowUrl "$metadata")
  notes_file="$RUNNER_TEMP/$app-release-notes.md"
  cat > "$notes_file" <<EOF
$title rolling prerelease.

Version: $version-nightly (build $GITHUB_RUN_NUMBER, commit ${GITHUB_SHA:0:12}).
Run attempt: $GITHUB_RUN_ATTEMPT.

[Commit]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/commit/$GITHUB_SHA)
[Workflow]($workflow_url)
[Downloads]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/tag/$tag)

Downloads are replaced after successful validation and builds on main.
EOF

  # Listing refs and releases lets API failures propagate instead of treating
  # every lookup failure as a missing tag or release.
  tag_ref=$(gh api "$repository/git/matching-refs/tags/$tag" \
    --jq ".[] | select(.ref == \"refs/tags/$tag\") | .ref")
  if [[ -n "$tag_ref" ]]; then
    gh api --method PATCH "$repository/git/refs/tags/$tag" \
      -f sha="$GITHUB_SHA" -F force=true > /dev/null
  else
    gh api --method POST "$repository/git/refs" \
      -f ref="refs/tags/$tag" -f sha="$GITHUB_SHA" > /dev/null
  fi

  release_id=$(gh api --paginate "$repository/releases" \
    --jq ".[] | select(.tag_name == \"$tag\") | .id")
  if [[ -n "$release_id" ]]; then
    gh release edit "$tag" --repo "$GITHUB_REPOSITORY" \
      --title "$title" --notes-file "$notes_file" --prerelease --latest=false
    asset_ids=$(gh api --paginate "$repository/releases/$release_id/assets" --jq '.[].id')
    for asset_id in $asset_ids; do
      gh api --method DELETE "$repository/releases/assets/$asset_id"
    done
  else
    gh release create "$tag" --repo "$GITHUB_REPOSITORY" --verify-tag \
      --title "$title" --notes-file "$notes_file" --prerelease --latest=false
  fi

  assets=("dist/$app-linux/$app-nightly-linux-x64.tar.gz" "$metadata")
  if [[ "$app" == notes ]]; then
    assets+=(dist/notes-android/notes-nightly-android.apk)
  fi
  gh release upload "$tag" --repo "$GITHUB_REPOSITORY" "${assets[@]}" --clobber
done
