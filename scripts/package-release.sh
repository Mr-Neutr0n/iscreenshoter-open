#!/bin/zsh
# Package an already verified, clean, exact-tag build. Never creates tags or publishes.
set -euo pipefail
cd "${0:A:h:h}"
TAG="${1:?Usage: ./scripts/package-release.sh v1.1.0}"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || { print -u2 'Release packaging requires a clean working tree.'; exit 1; }
[[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] || { print -u2 'Tag must identify HEAD.'; exit 1; }
APP="$PWD/build/Screen Shoter Open.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$TAG" == "v$VERSION" ]] || { print -u2 'Tag and app version differ.'; exit 1; }
codesign --verify --strict "$APP"
python3 - "$APP/Contents/Resources/build-manifest.json" <<'PY'
import json, subprocess, sys
manifest = json.load(open(sys.argv[1]))
assert manifest['source_commit'] == subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(), 'Build is from another commit'
assert manifest['source_dirty'] is False, 'Build was created from a dirty tree'
PY
mkdir -p dist
STAGE=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
PAYLOAD="$STAGE/payload"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/Screen Shoter Open.app"
cp LICENSE THIRD_PARTY_NOTICES.md README.md "$PAYLOAD/"
cp "$APP/Contents/Resources/build-manifest.json" "$PAYLOAD/build-manifest.json"
NAME="Screen-Shoter-Open-${TAG}-arm64"
ditto -c -k --sequesterRsrc "$PAYLOAD" "$STAGE/$NAME.zip"
cp "$PAYLOAD/build-manifest.json" "$STAGE/$NAME-build-manifest.json"
(cd "$STAGE"; shasum -a 256 "$NAME.zip" "$NAME-build-manifest.json" > "$NAME-SHA256SUMS.txt")
mv "$STAGE/$NAME.zip" "$STAGE/$NAME-build-manifest.json" "$STAGE/$NAME-SHA256SUMS.txt" dist/
print -r -- "Packaged $PWD/dist/$NAME.zip"
